/// Where a [RoutingEngine] lives: in the calling isolate ([LocalEngineHost]) or
/// in a background isolate ([IsolateEngineHost]).
///
/// On a phone the engine runs in a background isolate, so parsing the 15 MB
/// pack at start-up and the 150-650 ms route searches (desktop numbers; phone
/// numbers are not measured yet) never block the frames that draw the map. The
/// browser has no isolates for this, and the web build normally routes on the
/// server anyway, so it uses [LocalEngineHost]. Tests use it too.
///
/// Everything crossing the isolate boundary is plain data: the pack bytes, a
/// YAML string, observations, the route outcome. Closures never cross; the
/// network pulls stay in the main isolate and push their results in.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:citypulse_app/src/domain/models.dart' show GeoBounds;
import 'package:pulse_router/pulse_router.dart';
import 'package:yaml/yaml.dart';

/// The most hazard edges one overlay request returns; the most hazardous are kept (ADR-020).
const int kRiskEdgeLimit = 8000;

String _riskJson(
  RoutingEngine engine,
  DateTime at,
  String userClass,
  GeoBounds? bounds,
) => jsonEncode(
  riskEdgesToGeoJson(
    engine.riskEdges(
      at: at,
      userClass: userClass,
      bbox: bounds == null
          ? null
          : (
              minLon: bounds.minLon,
              minLat: bounds.minLat,
              maxLon: bounds.maxLon,
              maxLat: bounds.maxLat,
            ),
      limit: kRiskEdgeLimit,
    ),
    compact: true,
  ),
);

/// The three pack files and the hazard config, as loaded from the bundle.
class EngineInputs {
  /// Creates the inputs.
  const EngineInputs({
    required this.graph,
    required this.nodes,
    required this.meta,
    required this.configYaml,
  });

  /// `graph.bin`.
  final Uint8List graph;

  /// `nodes.bin`.
  final Uint8List nodes;

  /// `meta.bin`.
  final Uint8List meta;

  /// `config/hazard_classes.yaml` text.
  final String configYaml;
}

RoutingEngine _buildEngine(EngineInputs inputs) {
  ByteData view(Uint8List b) =>
      ByteData.view(b.buffer, b.offsetInBytes, b.lengthInBytes);
  final pack = MapPack.parse(
    graph: view(inputs.graph),
    nodes: view(inputs.nodes),
    meta: view(inputs.meta),
  );
  final config = EngineConfig.fromMap(loadYaml(inputs.configYaml) as YamlMap);
  return RoutingEngine(
    pack: pack,
    hazardClasses: config.hazardClasses,
    userClasses: config.userClasses,
    sourceReliability: config.sourceReliability,
    travelProfiles: config.travelProfiles,
  );
}

/// The operations the app needs from an engine, all asynchronous so a
/// background isolate can serve them.
abstract class EngineHost {
  /// Plans a route; see [RoutingEngine.route].
  Future<RouteOutcome> route({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
    required String userClass,
    required DateTime at,
    required String queryId,
  });

  /// The risk overlay as a compact GeoJSON string, for [bounds] only when given (ADR-020).
  Future<String> riskGeoJson({
    required DateTime at,
    required String userClass,
    GeoBounds? bounds,
  });

  /// Street search; see [PlaceIndex.search].
  Future<List<PlaceMatch>> search(String query, {GeoPoint? near});

  /// Adds reports (idempotent, bad rows are skipped).
  Future<void> addObservations(List<EngineObservation> observations);

  /// Current event state.
  Future<EventState> getEventState();

  /// Sets the event state.
  Future<void> setEventState(EventState state);

  /// Stops the host and frees what it holds.
  void dispose();
}

/// Engine in the calling isolate.
class LocalEngineHost implements EngineHost {
  /// Builds the engine from [inputs] synchronously.
  LocalEngineHost(EngineInputs inputs) : _engine = _buildEngine(inputs);

  final RoutingEngine _engine;
  PlaceIndex? _places;

  @override
  Future<RouteOutcome> route({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
    required String userClass,
    required DateTime at,
    required String queryId,
  }) async => _engine.route(
    fromLat: fromLat,
    fromLon: fromLon,
    toLat: toLat,
    toLon: toLon,
    userClass: userClass,
    at: at,
    queryId: queryId,
  );

  @override
  Future<String> riskGeoJson({
    required DateTime at,
    required String userClass,
    GeoBounds? bounds,
  }) async => _riskJson(_engine, at, userClass, bounds);

  @override
  Future<List<PlaceMatch>> search(String query, {GeoPoint? near}) async =>
      (_places ??= PlaceIndex(_engine.pack)).search(query, near: near);

  @override
  Future<void> addObservations(List<EngineObservation> observations) async {
    for (final o in observations) {
      try {
        _engine.addObservation(o);
        // A bad row must not stop the rest (ArgumentError from validation).
        // ignore: avoid_catching_errors
      } on ArgumentError {
        continue;
      }
    }
  }

  @override
  Future<EventState> getEventState() async => _engine.eventState;

  @override
  Future<void> setEventState(EventState state) async =>
      _engine.eventState = state;

  @override
  void dispose() {}
}

// --- isolate protocol -------------------------------------------------------

sealed class _Command {
  const _Command();
}

class _Route extends _Command {
  const _Route(
    this.fromLat,
    this.fromLon,
    this.toLat,
    this.toLon,
    this.userClass,
    this.at,
    this.queryId,
  );
  final double fromLat;
  final double fromLon;
  final double toLat;
  final double toLon;
  final String userClass;
  final DateTime at;
  final String queryId;
}

class _Risk extends _Command {
  const _Risk(this.at, this.userClass, this.bounds);
  final DateTime at;
  final String userClass;
  final GeoBounds? bounds;
}

class _Search extends _Command {
  const _Search(this.query, this.near);
  final String query;
  final GeoPoint? near;
}

class _Add extends _Command {
  const _Add(this.observations);
  final List<EngineObservation> observations;
}

class _GetState extends _Command {
  const _GetState();
}

class _SetState extends _Command {
  const _SetState(this.state);
  final EventState state;
}

class _Request {
  const _Request(this.command, this.reply);
  final _Command command;
  final SendPort reply;
}

class _Failure {
  const _Failure(this.message);
  final String message;
}

class _Boot {
  const _Boot(this.graph, this.nodes, this.meta, this.configYaml, this.ready);
  final TransferableTypedData graph;
  final TransferableTypedData nodes;
  final TransferableTypedData meta;
  final String configYaml;
  final SendPort ready;
}

/// Runs in the background isolate.
void _workerMain(_Boot boot) {
  final RoutingEngine engine;
  try {
    engine = _buildEngine(
      EngineInputs(
        graph: boot.graph.materialize().asUint8List(),
        nodes: boot.nodes.materialize().asUint8List(),
        meta: boot.meta.materialize().asUint8List(),
        configYaml: boot.configYaml,
      ),
    );
    // Anything that stops the engine loading is reported, not swallowed.
    // ignore: avoid_catches_without_on_clauses
  } catch (e) {
    boot.ready.send(_Failure('$e'));
    return;
  }
  PlaceIndex? places;
  final inbox = ReceivePort();
  boot.ready.send(inbox.sendPort);
  inbox.listen((Object? message) {
    final request = message! as _Request;
    try {
      final Object? result = switch (request.command) {
        _Route c => engine.route(
          fromLat: c.fromLat,
          fromLon: c.fromLon,
          toLat: c.toLat,
          toLon: c.toLon,
          userClass: c.userClass,
          at: c.at,
          queryId: c.queryId,
        ),
        _Risk c => _riskJson(engine, c.at, c.userClass, c.bounds),
        _Search c => (places ??= PlaceIndex(
          engine.pack,
        )).search(c.query, near: c.near),
        _Add c => () {
          for (final o in c.observations) {
            try {
              engine.addObservation(o);
              // ignore: avoid_catching_errors
            } on ArgumentError {
              continue;
            }
          }
          return null;
        }(),
        _GetState() => engine.eventState,
        _SetState c => () {
          engine.eventState = c.state;
          return null;
        }(),
      };
      request.reply.send(result);
      // Reported to the caller instead of killing the isolate.
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      request.reply.send(_Failure('$e'));
    }
  });
}

/// Engine in a background isolate.
class IsolateEngineHost implements EngineHost {
  IsolateEngineHost._(this._isolate, this._inbox);

  /// Starts the isolate and loads the engine in it. The returned future
  /// completes when the engine is ready, or throws [StateError] if loading
  /// failed.
  static Future<IsolateEngineHost> spawn(EngineInputs inputs) async {
    final ready = ReceivePort();
    final isolate = await Isolate.spawn(
      _workerMain,
      _Boot(
        TransferableTypedData.fromList([inputs.graph]),
        TransferableTypedData.fromList([inputs.nodes]),
        TransferableTypedData.fromList([inputs.meta]),
        inputs.configYaml,
        ready.sendPort,
      ),
      errorsAreFatal: false,
    );
    final first = await ready.first;
    ready.close();
    if (first is _Failure) {
      isolate.kill(priority: Isolate.immediate);
      throw StateError(first.message);
    }
    final host = IsolateEngineHost._(isolate, first as SendPort);
    // If the isolate ever dies (out of memory, killed by the OS), fail every
    // waiting request instead of leaving the UI waiting for an answer.
    final exit = ReceivePort();
    isolate.addOnExitListener(exit.sendPort);
    exit.listen((_) {
      exit.close();
      host._stopped();
    });
    return host;
  }

  final Isolate _isolate;
  final SendPort _inbox;
  final Set<ReceivePort> _pending = {};
  var _disposed = false;

  void _stopped() {
    _disposed = true;
    for (final port in _pending.toList()) {
      port.close(); // makes the waiting `first` throw
    }
    _pending.clear();
  }

  Future<T> _call<T>(_Command command) async {
    if (_disposed) throw StateError('engine host stopped');
    final reply = ReceivePort();
    _pending.add(reply);
    _inbox.send(_Request(command, reply.sendPort));
    final Object? answer;
    try {
      answer = await reply.first;
    } on StateError {
      throw StateError('engine host stopped');
    } finally {
      _pending.remove(reply);
      reply.close();
    }
    if (answer is _Failure) throw StateError(answer.message);
    return answer as T;
  }

  @override
  Future<RouteOutcome> route({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
    required String userClass,
    required DateTime at,
    required String queryId,
  }) => _call(_Route(fromLat, fromLon, toLat, toLon, userClass, at, queryId));

  @override
  Future<String> riskGeoJson({
    required DateTime at,
    required String userClass,
    GeoBounds? bounds,
  }) => _call(_Risk(at, userClass, bounds));

  @override
  Future<List<PlaceMatch>> search(String query, {GeoPoint? near}) async =>
      List<PlaceMatch>.from(await _call<List<Object?>>(_Search(query, near)));

  @override
  Future<void> addObservations(List<EngineObservation> observations) =>
      _call<Object?>(_Add(observations));

  @override
  Future<EventState> getEventState() => _call(const _GetState());

  @override
  Future<void> setEventState(EventState state) =>
      _call<Object?>(_SetState(state));

  @override
  void dispose() {
    if (_disposed) return;
    _stopped();
    _isolate.kill(priority: Isolate.immediate);
  }
}
