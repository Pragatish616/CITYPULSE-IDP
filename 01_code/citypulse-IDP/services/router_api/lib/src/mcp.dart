/// CityPulse as a Model Context Protocol (MCP) server (C6): any MCP-capable assistant can search places, plan a flood-aware route,
/// ask about a route and read the flood-event state, through tools.
///
/// The rules that make it CityPulse and not just another map tool:
/// - **The assistant never writes the facts.** Every sentence a tool returns comes from `pulse_explain`'s rule-based answerer and has
///   passed the symbolic verifier (or is the fixed fallback). The numbers come from the router's decision trace.
/// - **No verdicts (ADR-011).** A question about whether a road is safe, dry, open or passable is answered with the refusal and the
///   risk, exactly as in the app. Every route result carries the guide sentence.
/// - **Same router, same validation.** Tools call the HTTP API's own handler in-process, so a tool can do nothing the API would refuse.
///
/// Protocol: JSON-RPC 2.0, one message per line on stdin/stdout (the MCP stdio transport). Implemented methods: `initialize`,
/// `notifications/initialized`, `ping`, `tools/list`, `tools/call`. Logs go to stderr, never stdout.
library;

import 'dart:convert';

import 'package:pulse_explain/pulse_explain.dart';
import 'package:pulse_router/pulse_router.dart';
import 'package:shelf/shelf.dart';

/// Protocol versions this server can speak, newest first.
const List<String> kMcpProtocolVersions = ['2025-06-18', '2025-03-26', '2024-11-05'];

/// Travel modes as the tools name them, mapped to the router's user classes.
const Map<String, String> kMcpTravelModes = {
  'car': 'commuter',
  'bicycle': 'cyclist',
  'walking': 'pedestrian',
  'emergency': 'emergency',
};

/// Appended to every route result.
const String kMcpGuide =
    'CityPulse is a research prototype. It estimates flood risk from limited data and never states that a road is safe or '
    'passable; this is a guide from the data held, not a guarantee. In an emergency call 112.';

/// One MCP server over an API [Handler].
class McpServer {
  /// Creates a server. [api] is the router's HTTP handler; [hazardNouns] the display nouns the verifier needs.
  McpServer({
    required this.api,
    required this.hazardNouns,
    this.name = 'citypulse',
    this.version = '0.1.0',
  });

  /// The router API, called in-process.
  final Handler api;

  /// Hazard class to display noun.
  final Map<String, String> hazardNouns;

  /// Server name reported to clients.
  final String name;

  /// Server version reported to clients.
  final String version;

  static Map<String, Object?> _ok(Object? id, Object? result) => {'jsonrpc': '2.0', 'id': id, 'result': result};

  static Map<String, Object?> _err(Object? id, int code, String message) => {
    'jsonrpc': '2.0',
    'id': id,
    'error': {'code': code, 'message': message},
  };

  /// Handles one parsed message. Returns the response, or `null` for a notification (no response is sent).
  Future<Map<String, Object?>?> handle(Object? message) async {
    if (message is! Map) return _err(null, -32600, 'Invalid request: not a JSON object.');
    final msg = message.cast<String, Object?>();
    final id = msg['id'];
    final method = msg['method'];
    final isNotification = !msg.containsKey('id');
    if (msg['jsonrpc'] != '2.0' || method is! String) {
      return isNotification ? null : _err(id, -32600, 'Invalid request.');
    }
    final params = msg['params'] is Map ? (msg['params']! as Map).cast<String, Object?>() : const <String, Object?>{};
    switch (method) {
      case 'initialize':
        final asked = params['protocolVersion'];
        final version = asked is String && kMcpProtocolVersions.contains(asked) ? asked : kMcpProtocolVersions.first;
        return _ok(id, {
          'protocolVersion': version,
          'capabilities': {
            'tools': {'listChanged': false},
          },
          'serverInfo': {'name': name, 'version': this.version},
          'instructions':
              'Flood-aware routing for Chennai. Quote the tool text as given: it is verified against the route data. '
              'Never tell a user that a road is safe or passable.',
        });
      case 'notifications/initialized':
      case 'notifications/cancelled':
        return null;
      case 'ping':
        return isNotification ? null : _ok(id, <String, Object?>{});
      case 'tools/list':
        return _ok(id, {'tools': tools});
      case 'tools/call':
        final toolName = params['name'];
        final args = params['arguments'] is Map
            ? (params['arguments']! as Map).cast<String, Object?>()
            : const <String, Object?>{};
        if (toolName is! String || !tools.any((t) => t['name'] == toolName)) {
          return _err(id, -32602, 'Unknown tool: $toolName');
        }
        try {
          return _ok(id, await _call(toolName, args));
          // A tool failure is reported to the model as a tool result with isError, never as a crash.
          // ignore: avoid_catches_without_on_clauses
        } catch (e) {
          return _ok(id, _toolError('$e'));
        }
      default:
        return isNotification ? null : _err(id, -32601, 'Method not found: $method');
    }
  }

  /// The tool definitions (`tools/list`).
  static final List<Map<String, Object?>> tools = [
    {
      'name': 'search_places',
      'description': 'Find places and streets in the CityPulse map (Chennai, and Tamil Nadu main roads) by name, in English or Tamil.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': 'A place or street name, for example "Adyar" or "Velachery Main Road".'},
          'limit': {'type': 'integer', 'minimum': 1, 'maximum': 10},
        },
        'required': ['query'],
      },
    },
    {
      'name': 'plan_route',
      'description':
          'Plan a flood-aware route between two places (names or coordinates) for a travel mode, and get a short verified '
          'briefing: distance, time at free-flow speed, main streets, flood-risk rating with how much evidence it rests on.',
      'inputSchema': _routeSchema(withQuestion: false),
    },
    {
      'name': 'ask_about_route',
      'description':
          'Plan a route and answer a question about it ("why this route?", "what was avoided?", "how sure is the data?"). '
          'Questions about whether a road is safe or passable are always answered with what CityPulse cannot confirm.',
      'inputSchema': _routeSchema(withQuestion: true),
    },
    {
      'name': 'flood_event_state',
      'description': 'Whether CityPulse is currently applying its flood-hazard map to routes (dry, watch or active), and why.',
      'inputSchema': {'type': 'object', 'properties': <String, Object?>{}},
    },
  ];

  static Map<String, Object?> _routeSchema({required bool withQuestion}) {
    const place = {
      'description': 'A place name (searched in CityPulse) or {"lat": number, "lon": number}.',
      'anyOf': [
        {'type': 'string'},
        {
          'type': 'object',
          'properties': {
            'lat': {'type': 'number'},
            'lon': {'type': 'number'},
          },
          'required': ['lat', 'lon'],
        },
      ],
    };
    return {
      'type': 'object',
      'properties': {
        'from': place,
        'to': place,
        'travel_mode': {
          'type': 'string',
          'enum': kMcpTravelModes.keys.toList(),
          'description': 'Default car.',
        },
        'avoid_accidents': {'type': 'boolean', 'description': 'Keep off road segments with a live accident report.'},
        if (withQuestion) 'question': {'type': 'string', 'maxLength': 200},
      },
      'required': ['from', 'to', if (withQuestion) 'question'],
    };
  }

  static Map<String, Object?> _text(String text, {Map<String, Object?>? structured}) => {
    'content': [
      {'type': 'text', 'text': text},
    ],
    'structuredContent': ?structured,
    'isError': false,
  };

  static Map<String, Object?> _toolError(String text) => {
    'content': [
      {'type': 'text', 'text': text},
    ],
    'isError': true,
  };

  Future<Map<String, Object?>> _get(String path) async {
    final res = await api(Request('GET', Uri.parse('http://citypulse.local$path')));
    final body = jsonDecode(await res.readAsString());
    if (res.statusCode != 200) throw StateError(_message(body, res.statusCode));
    return (body as Map).cast<String, Object?>();
  }

  Future<Map<String, Object?>> _post(String path, Map<String, Object?> json) async {
    final res = await api(
      Request(
        'POST',
        Uri.parse('http://citypulse.local$path'),
        body: jsonEncode(json),
        headers: {'content-type': 'application/json'},
      ),
    );
    final body = jsonDecode(await res.readAsString());
    if (res.statusCode != 200) throw StateError(_message(body, res.statusCode));
    return (body as Map).cast<String, Object?>();
  }

  static String _message(Object? body, int status) {
    if (body is Map && body['error'] is Map) {
      final e = (body['error']! as Map).cast<String, Object?>();
      return '${e['message'] ?? e['code'] ?? 'error'} (HTTP $status)';
    }
    if (body is Map && body['message'] is String) return '${body['message']} (HTTP $status)';
    return 'The router refused the request (HTTP $status).';
  }

  Future<Map<String, Object?>> _call(String tool, Map<String, Object?> args) async {
    switch (tool) {
      case 'search_places':
        final query = args['query'];
        if (query is! String || query.trim().isEmpty) return _toolError('"query" must be a non-empty string.');
        final limit = (args['limit'] is num ? (args['limit']! as num).toInt() : 5).clamp(1, 10);
        final res = await _get('/places?q=${Uri.encodeQueryComponent(query.trim())}&limit=$limit');
        final rows = (res['results'] as List? ?? const []).cast<Map<String, Object?>>();
        if (rows.isEmpty) return _text('No place in the CityPulse map matches "$query".', structured: {'results': rows});
        final lines = [
          for (var i = 0; i < rows.length; i++)
            '${i + 1}. ${rows[i]['name']} (${rows[i]['kind']}) at ${rows[i]['lat']}, ${rows[i]['lon']}',
        ];
        return _text(lines.join('\n'), structured: {'results': rows});
      case 'flood_event_state':
        final res = await _get('/event-state');
        final state = res['event_state'];
        final reason = res['reason'];
        final lead = switch (state) {
          'active' => 'Flood event: the hazard map is applied to routes.',
          'watch' => 'Flood watch: the hazard map is applied to routes with extra caution.',
          'dry' => 'No flood event is declared, so the hazard map is not applied to routes.',
          _ => 'Flood-event state: $state.',
        };
        return _text(reason is String ? '$lead $reason' : lead, structured: res);
      case 'plan_route':
      case 'ask_about_route':
        final route = await _planned(args);
        if (route is String) return _toolError(route);
        final r = route! as _Route;
        String question;
        if (tool == 'ask_about_route') {
          final q = args['question'];
          if (q is! String || q.trim().isEmpty) return _toolError('"question" must be a non-empty string.');
          if (q.length > 200) return _toolError('"question" is longer than 200 characters.');
          question = q;
        } else {
          question = 'Give me the picture';
        }
        final answer = answerQuestion(
          question: question,
          trace: r.trace,
          eventState: r.eventState,
          hazardDisplayNouns: hazardNouns,
          forceIntent: tool == 'plan_route' ? QaIntent.summary : null,
        );
        final text = '${r.header}\n${answer.text}\n\n$kMcpGuide';
        return _text(text, structured: {
          'from': r.fromName,
          'to': r.toName,
          'travel_mode': r.mode,
          'distance_m': r.trace.chosen.distanceMeters.round(),
          'free_flow_minutes': (r.trace.chosen.freeFlowDurationSeconds / 60).round(),
          'streets': [
            for (final f in r.trace.contextFacts)
              if (f.key.startsWith('route_street_')) f.label,
          ],
          // C8: OpenStreetMap signals the route passes; null when none were counted (the map is incomplete, so not "zero").
          'traffic_signals': [
            for (final f in r.trace.contextFacts)
              if (f.key == 'route_signals') f.value,
          ].firstOrNull,
          'confidence_band': r.trace.confidenceBand.name,
          'event_state': r.eventState.name,
          'answer_verified': answer.verification.passed,
          'used_fallback': answer.usedFallback,
          if (answer.usedFallback) 'rejected_claims': answer.rejectedClaims,
          if (tool == 'ask_about_route') 'understood_as': answer.classification.intent.wireName,
        });
      default:
        return _toolError('Unknown tool: $tool');
    }
  }

  /// A place argument resolved to a point and a display name, or an error message.
  Future<Object> _resolve(Object? arg, String field) async {
    if (arg is Map) {
      final lat = arg['lat'];
      final lon = arg['lon'];
      if (lat is num && lon is num) {
        return (point: (lat: lat.toDouble(), lon: lon.toDouble()), name: '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}');
      }
      return '"$field" must be a place name or {"lat": number, "lon": number}.';
    }
    if (arg is! String || arg.trim().isEmpty) return '"$field" must be a place name or {"lat": number, "lon": number}.';
    final res = await _get('/places?q=${Uri.encodeQueryComponent(arg.trim())}&limit=1');
    final rows = (res['results'] as List? ?? const []).cast<Map<String, Object?>>();
    if (rows.isEmpty) return 'No place in the CityPulse map matches "$arg" (used for "$field").';
    final top = rows.first;
    return (
      point: (lat: (top['lat']! as num).toDouble(), lon: (top['lon']! as num).toDouble()),
      name: top['name']! as String,
    );
  }

  Future<Object?> _planned(Map<String, Object?> args) async {
    final mode = args['travel_mode'] ?? 'car';
    if (mode is! String || !kMcpTravelModes.containsKey(mode)) {
      return '"travel_mode" must be one of ${kMcpTravelModes.keys.join(", ")}.';
    }
    final from = await _resolve(args['from'], 'from');
    if (from is String) return from;
    final to = await _resolve(args['to'], 'to');
    if (to is String) return to;
    final f = from as ({GeoPoint point, String name});
    final t = to as ({GeoPoint point, String name});
    final body = await _post('/route', {
      'from': {'lat': f.point.lat, 'lon': f.point.lon},
      'to': {'lat': t.point.lat, 'lon': t.point.lon},
      'user_class': kMcpTravelModes[mode],
      if (args['avoid_accidents'] == true) 'avoid': ['accident'],
    });
    final trace = DecisionTrace.fromJson((body['trace']! as Map).cast<String, Object?>());
    final state = EventState.parse(body['event_state'] as String? ?? 'active');
    final hazardLayer = body['hazard_layer'] != false;
    final header =
        'Route from ${f.name} to ${t.name} ($mode)${hazardLayer ? '' : ' — main roads only; this region has no flood data'}:';
    return _Route(trace, state, header, f.name, t.name, mode);
  }
}

class _Route {
  _Route(this.trace, this.eventState, this.header, this.fromName, this.toName, this.mode);
  final DecisionTrace trace;
  final EventState eventState;
  final String header;
  final String fromName;
  final String toName;
  final String mode;
}
