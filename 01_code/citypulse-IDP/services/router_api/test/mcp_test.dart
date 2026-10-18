// C6: CityPulse as an MCP server. The protocol (JSON-RPC 2.0, MCP lifecycle and tools) and the rules: every route sentence passes the
// verifier, safety questions are refused, and a tool cannot do anything the HTTP API would refuse.
import 'dart:io';
import 'dart:typed_data';

import 'package:pulse_router/pulse_router.dart';
import 'package:router_api/router_api.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

const _packDir = '../../data/packs/2026-10-02';

ByteData _read(String name) => ByteData.sublistView(File('$_packDir/$name').readAsBytesSync());

void main() {
  late McpServer mcp;
  var nextId = 0;

  setUpAll(() {
    final pack = MapPack.parse(graph: _read('graph.bin'), nodes: _read('nodes.bin'), meta: _read('meta.bin'));
    final config = EngineConfig.fromMap(loadYaml(File('../../config/hazard_classes.yaml').readAsStringSync()) as YamlMap);
    final engine = RoutingEngine(
      pack: pack,
      snapper: EdgeSnapper(pack),
      hazardClasses: config.hazardClasses,
      userClasses: config.userClasses,
      travelProfiles: config.travelProfiles,
      sourceReliability: config.sourceReliability,
      restrictionConfig: config.restrictions,
      eventState: EventState.active,
    );
    final handler = buildHandler(
      engine,
      places: PlaceIndex(pack),
      config: const ApiConfig(),
      now: () => DateTime.utc(2026, 10, 2, 6),
    );
    mcp = McpServer(api: handler, hazardNouns: config.displayNouns);
  });

  Future<Map<String, Object?>> rpc(String method, [Map<String, Object?>? params]) async {
    final res = await mcp.handle({'jsonrpc': '2.0', 'id': ++nextId, 'method': method, 'params': ?params});
    expect(res, isNotNull);
    expect(res!['jsonrpc'], '2.0');
    expect(res['id'], nextId);
    return res;
  }

  Future<Map<String, Object?>> call(String tool, Map<String, Object?> args) async {
    final res = await rpc('tools/call', {'name': tool, 'arguments': args});
    expect(res['error'], isNull, reason: '$res');
    return (res['result']! as Map).cast<String, Object?>();
  }

  String text(Map<String, Object?> result) =>
      ((result['content']! as List).first as Map)['text']! as String;

  group('protocol', () {
    test('initialize answers with a supported version, the tools capability and server info', () async {
      final res = await rpc('initialize', {
        'protocolVersion': '2025-06-18',
        'capabilities': <String, Object?>{},
        'clientInfo': {'name': 'test', 'version': '1'},
      });
      final r = (res['result']! as Map).cast<String, Object?>();
      expect(r['protocolVersion'], '2025-06-18');
      expect((r['capabilities']! as Map).containsKey('tools'), isTrue);
      expect((r['serverInfo']! as Map)['name'], 'citypulse');
    });

    test('an unknown protocol version gets the newest one this server speaks', () async {
      final res = await rpc('initialize', {'protocolVersion': '1999-01-01'});
      expect((res['result']! as Map)['protocolVersion'], kMcpProtocolVersions.first);
    });

    test('notifications get no response; ping gets an empty result', () async {
      expect(await mcp.handle({'jsonrpc': '2.0', 'method': 'notifications/initialized'}), isNull);
      expect((await rpc('ping'))['result'], <String, Object?>{});
    });

    test('unknown methods, bad messages and unknown tools are JSON-RPC errors', () async {
      expect(((await rpc('resources/list'))['error']! as Map)['code'], -32601);
      expect(((await mcp.handle('not an object'))!['error']! as Map)['code'], -32600);
      expect(((await mcp.handle({'jsonrpc': '1.0', 'id': 1, 'method': 'ping'}))!['error']! as Map)['code'], -32600);
      expect(((await rpc('tools/call', {'name': 'drop_tables', 'arguments': <String, Object?>{}}))['error']! as Map)['code'], -32602);
    });

    test('tools/list names the four tools, each with an object input schema', () async {
      final tools = ((await rpc('tools/list'))['result']! as Map)['tools']! as List;
      expect([for (final t in tools) (t as Map)['name']], ['search_places', 'plan_route', 'ask_about_route', 'flood_event_state']);
      for (final t in tools) {
        expect(((t as Map)['inputSchema']! as Map)['type'], 'object');
        expect(t['description'], isNotEmpty);
      }
    });
  });

  group('tools', () {
    test('search_places finds places by name', () async {
      final r = await call('search_places', {'query': 'Velachery', 'limit': 3});
      expect(r['isError'], isFalse);
      expect(text(r), contains('Velachery'));
      expect(((r['structuredContent']! as Map)['results']! as List), isNotEmpty);
    });

    test('plan_route by coordinates gives a verified briefing with streets, never a verdict', () async {
      final r = await call('plan_route', {
        'from': {'lat': 13.0418, 'lon': 80.2341},
        'to': {'lat': 12.9791, 'lon': 80.2209},
        'travel_mode': 'car',
      });
      expect(r['isError'], isFalse, reason: text(r));
      final s = (r['structuredContent']! as Map).cast<String, Object?>();
      expect(s['answer_verified'], isTrue);
      expect(s['used_fallback'], isFalse);
      expect(s['distance_m'], greaterThan(3000));
      expect(s['streets'], isNotEmpty);
      final t = text(r);
      expect(t, contains(kMcpGuide));
      for (final street in (s['streets']! as List).cast<String>()) {
        expect(t, contains(street));
      }
      // The guide itself says CityPulse never states a road is safe; check the answer without it.
      expect(t.replaceAll(kMcpGuide, '').toLowerCase(), isNot(contains('is safe')));
    });

    test('plan_route resolves place names through the same search', () async {
      final r = await call('plan_route', {'from': 'Adyar', 'to': 'Guindy', 'travel_mode': 'walking'});
      expect(r['isError'], isFalse, reason: text(r));
      expect(text(r), startsWith('Route from '));
      expect((r['structuredContent']! as Map)['travel_mode'], 'walking');
    });

    test('ask_about_route answers from the route; a safety question is refused with the risk', () async {
      final why = await call('ask_about_route', {
        'from': {'lat': 13.0418, 'lon': 80.2341},
        'to': {'lat': 12.9791, 'lon': 80.2209},
        'question': 'How long will it take?',
      });
      expect((why['structuredContent']! as Map)['understood_as'], 'time_distance');
      expect((why['structuredContent']! as Map)['answer_verified'], isTrue);
      final safe = await call('ask_about_route', {
        'from': {'lat': 13.0418, 'lon': 80.2341},
        'to': {'lat': 12.9791, 'lon': 80.2209},
        'question': 'Is this route safe to drive now?',
      });
      expect(text(safe), contains('I cannot confirm the condition of any road'));
    });

    test('bad arguments are tool errors the assistant can read, not crashes', () async {
      for (final (tool, args) in [
        ('search_places', <String, Object?>{'query': ''}),
        ('plan_route', <String, Object?>{'from': 'Adyar', 'to': 'Guindy', 'travel_mode': 'helicopter'}),
        ('plan_route', <String, Object?>{'from': 42, 'to': 'Guindy'}),
        ('plan_route', <String, Object?>{'from': 'Zzqxv Nowhere', 'to': 'Guindy'}),
        ('ask_about_route', <String, Object?>{'from': 'Adyar', 'to': 'Guindy', 'question': ''}),
        ('plan_route', <String, Object?>{'from': {'lat': 28.61, 'lon': 77.2}, 'to': {'lat': 28.7, 'lon': 77.1}}),
      ]) {
        final r = await call(tool, args);
        expect(r['isError'], isTrue, reason: '$tool $args');
        expect(text(r), isNotEmpty);
      }
    });

    test('flood_event_state says in plain words whether the hazard map is applied', () async {
      final r = await call('flood_event_state', <String, Object?>{});
      expect(text(r), contains('Flood event'));
    });
  });
}
