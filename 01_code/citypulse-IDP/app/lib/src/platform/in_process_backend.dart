/// [RoutingBackend] that runs `pulse_router`'s [RoutingEngine] inside the app,
/// with the bundled map pack. This is the offline path (ADR-005): once the
/// pack is installed nothing here touches the network except the optional
/// refresh of reports and the event state.
///
/// The engine itself lives in an [EngineHost]: a background isolate on a phone
/// (so the pack parse and the route searches never block the UI thread), the
/// calling isolate in tests and in the browser.
library;

import 'package:citypulse_app/src/domain/models.dart';
import 'package:citypulse_app/src/platform/engine_host.dart';
import 'package:citypulse_app/src/platform/routing_backend.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:pulse_router/pulse_router.dart';

/// Builds an [EngineHost] from loaded inputs.
typedef EngineHostFactory = Future<EngineHost> Function(EngineInputs inputs);

/// The default: a background isolate on devices, the calling isolate on web.
Future<EngineHost> defaultEngineHost(EngineInputs inputs) async =>
    kIsWeb ? LocalEngineHost(inputs) : IsolateEngineHost.spawn(inputs);

/// Loads the pack from an [AssetBundle] and routes locally.
class InProcessBackend implements RoutingBackend {
  /// Creates a backend.
  ///
  /// [pullObservations] fetches reports from the ingest server (optional; may
  /// throw when offline). [pullEventState] reads the event state from
  /// `router_api` (optional). When the state is unknown the engine assumes
  /// `active`, i.e. it applies the hazard map, the more cautious choice.
  InProcessBackend({
    required AssetBundle bundle,
    this.pullObservations,
    this.pullEventState,
    this.packPath = 'assets/packs',
    this.configPath = 'assets/config/hazard_classes.yaml',
    DateTime Function()? clock,
    EngineHostFactory hostFactory = defaultEngineHost,
  }) : _bundle = bundle,
       _hostFactory = hostFactory,
       _clock = clock ?? (() => DateTime.now().toUtc());

  final AssetBundle _bundle;
  final DateTime Function() _clock;
  final EngineHostFactory _hostFactory;

  /// Directory of `graph.bin`, `nodes.bin`, `meta.bin` inside the bundle.
  final String packPath;

  /// Path of `hazard_classes.yaml` inside the bundle.
  final String configPath;

  /// Optional report source.
  final Future<List<EngineObservation>> Function()? pullObservations;

  /// Optional event-state source.
  final Future<EventState> Function()? pullEventState;

  Future<EngineHost>? _engineFuture;
  DateTime? _lastPull;

  @override
  ComputeSite get site => ComputeSite.device;

  Future<EngineHost> _load() async {
    try {
      // The bundle reads run off the UI thread; the parse happens in the host.
      Future<Uint8List> bytes(String name) async {
        final d = await _bundle.load('$packPath/$name');
        return Uint8List.sublistView(d);
      }

      final (graph, nodes, meta, yaml) = await (
        bytes('graph.bin'),
        bytes('nodes.bin'),
        bytes('meta.bin'),
        _bundle.loadString(configPath),
      ).wait;
      return await _hostFactory(
        EngineInputs(graph: graph, nodes: nodes, meta: meta, configYaml: yaml),
      );
      // Missing assets, a corrupt pack or a bad config all mean "not ready".
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      _engineFuture = null; // allow a retry
      throw RoutingException(RoutingFailure.notReady, '$e');
    }
  }

  Future<EngineHost> get _engine => _engineFuture ??= _load();

  @override
  Future<void> warmUp() async {
    final engine = await _engine;
    await _refresh(engine);
  }

  /// Pulls reports and the event state at most once a minute; failures
  /// (offline) are expected and ignored -- the cache simply stays as it was.
  Future<void> _refresh(EngineHost engine) async {
    final last = _lastPull;
    if (last != null &&
        _clock().difference(last) < const Duration(minutes: 1)) {
      return;
    }
    _lastPull = _clock();
    final pull = pullObservations;
    if (pull != null) {
      try {
        await engine.addObservations(await pull());
        // Offline or a bad row must not stop routing.
        // ignore: avoid_catches_without_on_clauses
      } catch (_) {}
    }
    final state = pullEventState;
    if (state != null) {
      try {
        await engine.setEventState(await state());
        // ignore: avoid_catches_without_on_clauses
      } catch (_) {}
    }
  }

  @override
  Future<RouteView> route({
    required GeoPoint from,
    required GeoPoint to,
    required TravelType travel,
    DateTime? at,
  }) async {
    final engine = await _engine;
    await _refresh(engine);
    final outcome = await engine.route(
      fromLat: from.lat,
      fromLon: from.lon,
      toLat: to.lat,
      toLon: to.lon,
      userClass: travel.wire,
      at: at ?? _clock(),
      queryId: 'q-${_clock().microsecondsSinceEpoch}',
    );
    switch (outcome) {
      case RouteNotFound(:final reason):
        throw RoutingException(switch (reason) {
          RouteFailure.originOutsideCoverage => RoutingFailure.originOutside,
          RouteFailure.destinationOutsideCoverage =>
            RoutingFailure.destinationOutside,
          RouteFailure.sameLocation => RoutingFailure.sameLocation,
          RouteFailure.noRoute => RoutingFailure.noRoute,
        });
      case RouteFound(:final plan):
        return RouteView(
          trace: plan.trace,
          path: plan.path,
          fastestPath: plan.fastestPath,
          detours: plan.detours,
          avoidedHazards: plan.avoidedHazards,
          eventState: plan.eventState,
          computeMilliseconds: plan.computeMilliseconds,
          computedOn: ComputeSite.device,
          origin: plan.origin,
          destination: plan.destination,
          originSnapMetres: plan.originSnapMetres,
          destinationSnapMetres: plan.destinationSnapMetres,
        );
    }
  }

  @override
  Future<String> riskGeoJson({
    required TravelType travel,
    GeoBounds? bounds,
  }) async {
    final engine = await _engine;
    return engine.riskGeoJson(
      at: _clock(),
      userClass: travel.wire,
      bounds: bounds,
    );
  }

  @override
  Future<List<Place>> searchPlaces(String query, {GeoPoint? near}) async {
    final engine = await _engine;
    return [
      for (final m in await engine.search(query, near: near))
        Place(
          name: m.name,
          point: m.point,
          detail: m.distanceMetres == null
              ? null
              : '${(m.distanceMetres! / 1000).toStringAsFixed(1)} km',
        ),
    ];
  }

  @override
  Future<EventState> eventState() async => (await _engine).getEventState();

  @override
  void addLocalObservation(EngineObservation observation) {
    // Only matters once the engine is loaded; a report made before that is
    // picked up by the next pull instead.
    final future = _engineFuture;
    if (future == null) return;
    future.then(
      (engine) => engine.addObservations([observation]),
      onError: (_) {},
    );
  }

  @override
  void dispose() {
    _engineFuture?.then((host) => host.dispose(), onError: (_) {});
  }
}
