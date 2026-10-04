/// The routing engine both clients share (ADR-001: one router implementation).
///
/// The Flutter app runs it in-process on the phone; `services/router_api`
/// runs the same class on a server for the web app; the evaluation harness
/// still uses the CLI. This file holds no routing algorithm of its own -- it
/// assembles the inputs `planRouteDetailed` needs (per-edge hazard
/// configuration, observations attached to edges) from a [MapPack], and turns
/// a pair of coordinates into a pair of nodes.
///
/// Three KNOWN_FLAWS items are closed here for the on-device path:
///  * F-06: any origin and destination, a prior for **every** edge (so a new
///    report on a previously unmapped street takes effect), no 152 MB prior.
///  * F-02: a report is attached to every edge within [attachRadiusM], which
///    includes both directions of a two-way street.
///  * F-09: the static prior is applied only when the [EventState] is `watch`
///    or `active`; on a `dry` day routes ignore it (observations still count).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pulse_belief/pulse_belief.dart';
import 'package:pulse_router/src/csr_graph.dart';
import 'package:pulse_router/src/decision_trace.dart';
import 'package:pulse_router/src/edge_snapper.dart';
import 'package:pulse_router/src/map_pack.dart';
import 'package:pulse_router/src/path_simplify.dart';
import 'package:pulse_router/src/query_orchestrator.dart';
import 'package:pulse_router/src/travel_profile.dart';

/// A latitude/longitude pair in degrees.
typedef GeoPoint = ({double lat, double lon});

/// Per-hazard-class constants, from `config/hazard_classes.yaml`.
class HazardClassParams {
  /// Creates the parameters for one class.
  const HazardClassParams({
    required this.decayTauSeconds,
    required this.severity,
    required this.hMaxMm,
    required this.epsilon,
  });

  /// `T_c`, seconds (a placeholder in the shipped config -- F-15).
  final double decayTauSeconds;

  /// `s`.
  final double severity;

  /// `h_max`, millimetres.
  final double hMaxMm;

  /// `ε`.
  final double epsilon;
}

/// A user class's pessimism and harm weight.
class UserClassParams {
  /// Creates the parameters for one user class.
  const UserClassParams({required this.z, required this.lambda, this.profile = 'car'});

  /// `z`.
  final double z;

  /// `λ`.
  final double lambda;

  /// Which [TravelProfile] this class moves with (ADR-019): its speeds, the
  /// roads it may use and whether it obeys one-way streets. `'car'` is the
  /// pack's own graph.
  final String profile;
}

/// Whether the static hazard prior should be treated as describing the
/// present (KNOWN_FLAWS F-09). The prior is a susceptibility map, not "water
/// is here now": applied on a dry day it made emergency routes pay twice the
/// free-flow time on 8,759 edges for nothing.
enum EventState {
  /// No rain event. The prior is **not** applied; reports still are.
  dry,

  /// A forecast or alert is in force. The prior is applied.
  watch,

  /// A flood event is under way. The prior is applied.
  active;

  /// Parses `"dry" | "watch" | "active"`.
  static EventState parse(String value) => EventState.values.firstWhere(
    (e) => e.name == value,
    orElse: () => throw ArgumentError.value(value, 'value', 'unknown state'),
  );

  /// Whether the static prior applies in this state.
  bool get appliesPrior => this != EventState.dry;
}

/// One report as the engine needs it. The caller maps its own observation
/// type (local database row, server record) to this.
class EngineObservation {
  /// Creates an observation. `polarity` is `+1` (hazard present) or `-1`.
  const EngineObservation({
    required this.id,
    required this.hazardClass,
    required this.polarity,
    required this.lat,
    required this.lon,
    required this.observedAt,
    required this.sourceClass,
    this.depthMm,
  });

  /// Parses one `HazardObservation` JSON object (`docs/CONTRACTS.md` §1, as
  /// returned by the ingest server) or returns `null` if it is malformed. The
  /// phone and `router_api` both use this, so they accept exactly the same
  /// rows. It does not check that the classes are known to a particular
  /// engine; [RoutingEngine.addObservation] does that.
  static EngineObservation? tryParseWire(Object? raw) {
    if (raw is! Map) return null;
    try {
      final geometry = raw['geometry']! as Map;
      final coords = geometry['coordinates']! as List;
      final intensity = raw['intensity'];
      final depth = intensity is Map ? intensity['depth_mm'] : null;
      return EngineObservation(
        id: raw['id']! as String,
        hazardClass: raw['hazard_class']! as String,
        polarity: raw['polarity']! as int,
        lon: (coords[0]! as num).toDouble(),
        lat: (coords[1]! as num).toDouble(),
        observedAt: DateTime.parse(raw['observed_at']! as String).toUtc(),
        sourceClass: raw['source_class']! as String,
        depthMm: depth is num ? depth.toDouble() : null,
      );
      // A malformed row from the network must never crash the caller.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      return null;
    }
  }

  /// Stable id (UUID); the engine ignores a second observation with the same
  /// id (the log is a G-Set, ADR-008).
  final String id;

  /// A key of the engine's hazard classes.
  final String hazardClass;

  /// `+1` present, `-1` absent/cleared.
  final int polarity;

  /// Report latitude.
  final double lat;

  /// Report longitude.
  final double lon;

  /// When the hazard was observed (decay runs on this).
  final DateTime observedAt;

  /// A key of the engine's source reliabilities.
  final String sourceClass;

  /// Standing-water depth if reported.
  final double? depthMm;
}

/// A hazard-configured edge with its current belief, for drawing a risk map.
class RiskEdge {
  /// Creates a risk edge.
  const RiskEdge({
    required this.edgeId,
    required this.from,
    required this.to,
    required this.pMean,
    required this.pPessimistic,
    required this.nEff,
    required this.hasObservation,
    required this.newestObservationAgeSeconds,
    required this.hazardClass,
    required this.streetName,
  });

  /// Edge id.
  final int edgeId;

  /// Segment start.
  final GeoPoint from;

  /// Segment end.
  final GeoPoint to;

  /// Posterior mean `p̄`.
  final double pMean;

  /// The user class's pessimistic index `p̃`.
  final double pPessimistic;

  /// Net reliability-weighted evidence.
  final double nEff;

  /// Whether any report contributes (false = prior only).
  final bool hasObservation;

  /// Age of the newest contributing report, seconds; `null` if none.
  final double? newestObservationAgeSeconds;

  /// The hazard class this edge is treated as.
  final String hazardClass;

  /// OSM street name, if any.
  final String? streetName;
}

/// Why no route could be produced.
enum RouteFailure {
  /// The origin is not within reach of a drivable road in the pack.
  originOutsideCoverage,

  /// The destination is not within reach of a drivable road in the pack.
  destinationOutsideCoverage,

  /// Origin and destination snap to the same junction.
  sameLocation,

  /// The graph has no path between the two points.
  noRoute,
}

/// A planned route, ready to draw and explain.
class RoutePlan {
  /// Creates a plan.
  const RoutePlan({
    required this.trace,
    required this.path,
    required this.fastestPath,
    required this.detours,
    required this.origin,
    required this.destination,
    required this.originSnapMetres,
    required this.destinationSnapMetres,
    required this.eventState,
    required this.computeMilliseconds,
    required this.avoidedHazards,
  });

  /// The decision trace; the only input to explanations.
  final DecisionTrace trace;

  /// The chosen route as coordinates, junction to junction.
  final List<GeoPoint> path;

  /// The fastest route ignoring hazards, as coordinates.
  final List<GeoPoint> fastestPath;

  /// Whether the chosen route differs from the fastest one.
  final bool detours;

  /// The junction the origin snapped to.
  final GeoPoint origin;

  /// The junction the destination snapped to.
  final GeoPoint destination;

  /// How far the origin point was from its junction, metres.
  final double originSnapMetres;

  /// How far the destination point was from its junction, metres.
  final double destinationSnapMetres;

  /// The event state the query ran under.
  final EventState eventState;

  /// Wall-clock time spent in the engine, milliseconds.
  final double computeMilliseconds;

  /// Midpoints of hazard edges the chosen route avoids (the trace's
  /// blocking edges), for map markers.
  final List<GeoPoint> avoidedHazards;
}

/// The result of [RoutingEngine.route]: a plan or a reason there is none.
sealed class RouteOutcome {
  const RouteOutcome();
}

/// A route was found.
class RouteFound extends RouteOutcome {
  /// Wraps [plan].
  const RouteFound(this.plan);

  /// The plan.
  final RoutePlan plan;
}

/// No route could be produced.
class RouteNotFound extends RouteOutcome {
  /// Wraps [reason].
  const RouteNotFound(this.reason);

  /// Why.
  final RouteFailure reason;
}

class _Attached {
  const _Attached(this.observation, this.distanceM);
  final EngineObservation observation;
  final double distanceM;
}

/// Plans routes and builds risk maps over a [MapPack].
class RoutingEngine {
  /// Creates an engine. [hazardClasses], [userClasses] and
  /// [sourceReliability] come from `config/hazard_classes.yaml`.
  RoutingEngine({
    required this.pack,
    required this.hazardClasses,
    required this.userClasses,
    required this.sourceReliability,
    this.beliefParams,
    this.priorThreshold = 0.25,
    this.priorOnlyClass = 'flood',
    this.attachRadiusM = 75,
    this.maxEdgesPerObservation = 24,
    this.depthMinReliability = 0.85,
    this.eventState = EventState.active,
    this.travelProfiles = const {},
    this.maxPathPoints = 1500,
    EdgeSnapper? snapper,
  }) : snapper = snapper ?? EdgeSnapper(pack) {
    for (final u in userClasses.entries) {
      if (u.value.profile != 'car' && !travelProfiles.containsKey(u.value.profile)) {
        throw ArgumentError.value(
          u.value.profile,
          'userClasses.${u.key}.profile',
          'no such travel profile',
        );
      }
    }
    if (!hazardClasses.containsKey(priorOnlyClass)) {
      throw ArgumentError.value(priorOnlyClass, 'priorOnlyClass', 'unknown');
    }
  }

  /// The map pack.
  final MapPack pack;

  /// The spatial index over [pack].
  final EdgeSnapper snapper;

  /// Per-class constants.
  final Map<String, HazardClassParams> hazardClasses;

  /// Per-user-class constants.
  final Map<String, UserClassParams> userClasses;

  /// `α_c` per source class.
  final Map<String, double> sourceReliability;

  /// Beta-belief parameters (defaults: ADR-015 placeholders).
  final BeliefParams? beliefParams;

  /// An edge enters the static-prior hazard set when its prior probability is
  /// at least this (the harness's `PRIOR_ONLY_THRESHOLD`, 0.25: the "High"
  /// and "Very High" GCC categories). A documented choice, not a fitted one.
  final double priorThreshold;

  /// The hazard class the static prior is treated as.
  final String priorOnlyClass;

  /// A report is attached to every edge within this many metres (F-02).
  final double attachRadiusM;

  /// Upper bound on edges one report is attached to.
  final int maxEdgesPerObservation;

  /// A depth reading removes an edge outright (the chance constraint) only if
  /// its source is at least this reliable. The shipped classes put sensors
  /// (0.97), official feeds (0.92) and responders (0.90) above 0.85 and crowd
  /// (0.60) and traversal (0.70) below, so **one anonymous "knee-deep" report
  /// cannot close a road for everyone** (PLAN.md §12, abuse: one report must
  /// not flip a status). A crowd depth still raises the soft penalty through
  /// the belief; it just does not act as a hard block until a reliable source
  /// agrees. A modelling policy, not a fitted value.
  final double depthMinReliability;

  /// Longest polyline handed to a map (ADR-020). A route with more nodes is thinned with a
  /// stated tolerance; its length, time and the trace are unaffected.
  final int maxPathPoints;

  /// Movement profiles by name (ADR-019). `'car'` is implicit and means the
  /// pack's own graph.
  final Map<String, TravelProfile> travelProfiles;

  /// The default event state for queries that do not pass one.
  EventState eventState;

  // One routing graph per non-car profile, built the first time it is needed
  // (about 20 MB each for the Chennai pack).
  final Map<String, _ProfileView> _views = {};

  _ProfileView _viewFor(String profileId) {
    if (profileId == 'car') return _carView ??= _ProfileView.of(pack.graph);
    return _views[profileId] ??= _buildProfileView(travelProfiles[profileId]!);
  }

  _ProfileView? _carView;

  _ProfileView _buildProfileView(TravelProfile profile) {
    final n = pack.edgeCount;
    final nodes = pack.nodeCount;
    final from = Int32List(2 * n);
    final to = Int32List(2 * n);
    final ids = Int32List(2 * n);
    final seconds = Float64List(2 * n);
    final kmh = Float64List(2 * n);
    var count = 0;
    final present = <int>{};
    int key(int a, int b) => a * nodes + b;
    for (var e = 0; e < n; e++) {
      final code = pack.highwayCode[e];
      final highway = kHighwayCodes[code < kHighwayCodes.length ? code : 0];
      final carKmh = pack.edgeFreeFlowKmh[e];
      final speed = profile.speedOn(highway, carKmh);
      if (speed == null) continue;
      final metres = pack.edgeFreeFlowSeconds[e] * carKmh / 3.6;
      from[count] = pack.edgeFrom[e];
      to[count] = pack.edgeTo[e];
      ids[count] = e;
      seconds[count] = metres / (speed / 3.6);
      kmh[count] = speed;
      present.add(key(pack.edgeFrom[e], pack.edgeTo[e]));
      count++;
    }
    if (profile.ignoreOneWay) {
      // A walker may go against a one-way street. The reverse edge shares its
      // forward edge's id, so a hazard on the street counts both ways; the
      // search resolves each step by (node, id), which stays unambiguous.
      final forward = count;
      for (var i = 0; i < forward; i++) {
        final reverse = key(to[i], from[i]);
        if (present.add(reverse)) {
          from[count] = to[i];
          to[count] = from[i];
          ids[count] = ids[i];
          seconds[count] = seconds[i];
          kmh[count] = kmh[i];
          count++;
        }
      }
    }
    return _ProfileView.of(
      CsrGraph.fromArrays(
        nodeCount: nodes,
        from: Int32List.sublistView(from, 0, count),
        to: Int32List.sublistView(to, 0, count),
        freeFlowSeconds: Float64List.sublistView(seconds, 0, count),
        freeFlowKmh: Float64List.sublistView(kmh, 0, count),
        edgeId: Int32List.sublistView(ids, 0, count),
      ),
    );
  }

  final Map<String, EngineObservation> _observations = {};
  final Map<int, List<_Attached>> _byEdge = {};
  Map<int, EdgeHazardConfig>? _priorOnly;

  /// Number of distinct observations held.
  int get observationCount => _observations.length;

  /// Adds one observation. A repeated id is ignored. Returns how many edges
  /// it was attached to (`0` if it lies far from any road).
  int addObservation(EngineObservation o) {
    if (_observations.containsKey(o.id)) return 0;
    if (!hazardClasses.containsKey(o.hazardClass)) {
      throw ArgumentError.value(o.hazardClass, 'hazardClass', 'unknown class');
    }
    if (!sourceReliability.containsKey(o.sourceClass)) {
      throw ArgumentError.value(o.sourceClass, 'sourceClass', 'unknown source');
    }
    if (o.polarity != 1 && o.polarity != -1) {
      throw ArgumentError.value(o.polarity, 'polarity', 'must be +1 or -1');
    }
    if (!o.lat.isFinite || !o.lon.isFinite) {
      throw ArgumentError('observation ${o.id} has a non-finite position');
    }
    var matches = snapper.edgesNear(
      o.lat,
      o.lon,
      radiusM: attachRadiusM,
      limit: maxEdgesPerObservation,
    );
    // A GPS fix 100 m off the road should still land on the road.
    if (matches.isEmpty) {
      matches = snapper.edgesNear(o.lat, o.lon, radiusM: 200, limit: 4);
    }
    _observations[o.id] = o;
    for (final m in matches) {
      (_byEdge[m.edgeId] ??= []).add(_Attached(o, m.distanceM));
    }
    return matches.length;
  }

  /// Adds many observations.
  void addObservations(Iterable<EngineObservation> all) {
    all.forEach(addObservation);
  }

  /// Removes every observation (used when a client reloads its cache).
  void clearObservations() {
    _observations.clear();
    _byEdge.clear();
  }

  Map<int, EdgeHazardConfig> _priorOnlyConfigs() {
    final cached = _priorOnly;
    if (cached != null) return cached;
    final params = hazardClasses[priorOnlyClass]!;
    final out = <int, EdgeHazardConfig>{};
    for (var e = 0; e < pack.edgeCount; e++) {
      final prior = pack.priorLogOdds(e);
      if (sigmoid(prior) >= priorThreshold) {
        out[e] = EdgeHazardConfig(
          hazardClass: priorOnlyClass,
          priorLogOdds: prior,
          decayTauSeconds: params.decayTauSeconds,
          severity: params.severity,
          hMaxMm: params.hMaxMm,
          epsilon: params.epsilon,
        );
      }
    }
    return _priorOnly = out;
  }

  ({
    Map<int, EdgeHazardConfig> configs,
    Map<int, List<WeightedObservation>> observations,
    Map<String, String> sourceClassById,
  })
  _assemble(DateTime at, EventState state) {
    final configs = <int, EdgeHazardConfig>{
      if (state.appliesPrior) ..._priorOnlyConfigs(),
    };
    final observations = <int, List<WeightedObservation>>{};
    final sourceClassById = <String, String>{};

    for (final entry in _byEdge.entries) {
      final live = [
        for (final a in entry.value)
          if (!a.observation.observedAt.isAfter(at)) a,
      ];
      if (live.isEmpty) continue;

      // One hazard class per edge (the orchestrator's contract): the class
      // with most reports, ties broken towards the higher severity.
      final counts = <String, int>{};
      for (final a in live) {
        counts.update(
          a.observation.hazardClass,
          (n) => n + 1,
          ifAbsent: () => 1,
        );
      }
      final dominant = counts.keys.reduce((a, b) {
        final byCount = counts[b]!.compareTo(counts[a]!);
        if (byCount != 0) return byCount < 0 ? b : a;
        final bySeverity = hazardClasses[b]!.severity.compareTo(
          hazardClasses[a]!.severity,
        );
        if (bySeverity != 0) return bySeverity > 0 ? b : a;
        return a.compareTo(b) <= 0 ? a : b;
      });
      final kept = [
        for (final a in live)
          if (a.observation.hazardClass == dominant) a,
      ];
      final params = hazardClasses[dominant]!;

      EngineObservation? newestDepth;
      for (final a in kept) {
        final o = a.observation;
        if (o.depthMm == null) continue;
        if (sourceReliability[o.sourceClass]! < depthMinReliability) continue;
        if (newestDepth == null ||
            o.observedAt.isAfter(newestDepth.observedAt)) {
          newestDepth = o;
        }
      }

      configs[entry.key] = EdgeHazardConfig(
        hazardClass: dominant,
        priorLogOdds: pack.priorLogOdds(entry.key),
        decayTauSeconds: params.decayTauSeconds,
        severity: params.severity,
        hMaxMm: params.hMaxMm,
        epsilon: params.epsilon,
        depthMm: newestDepth?.depthMm,
      );
      observations[entry.key] = [
        for (final a in kept)
          WeightedObservation(
            id: a.observation.id,
            polarity: a.observation.polarity,
            distanceM: a.distanceM,
            observedAt: a.observation.observedAt,
            sourceReliability: sourceReliability[a.observation.sourceClass]!,
          ),
      ];
      for (final a in kept) {
        sourceClassById[a.observation.id] = a.observation.sourceClass;
      }
    }
    return (
      configs: configs,
      observations: observations,
      sourceClassById: sourceClassById,
    );
  }

  GeoPoint _node(int n) => (lat: pack.nodeLat[n], lon: pack.nodeLon[n]);

  GeoPoint _edgeMidpoint(int e) {
    final a = _node(pack.edgeFrom[e]);
    final b = _node(pack.edgeTo[e]);
    return (lat: (a.lat + b.lat) / 2, lon: (a.lon + b.lon) / 2);
  }


  /// Plans a route between two coordinates.
  RouteOutcome route({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
    required String userClass,
    required DateTime at,
    EventState? eventState,
    String queryId = 'engine-query',
    double maxSnapMetres = 1500,
  }) {
    final user = userClasses[userClass];
    if (user == null) {
      throw ArgumentError.value(userClass, 'userClass', 'unknown user class');
    }
    final stopwatch = Stopwatch()..start();
    final state = eventState ?? this.eventState;

    final view = _viewFor(user.profile);
    final source = snapper.nearestNode(
      fromLat,
      fromLon,
      maxM: maxSnapMetres,
      accept: view.usable,
    );
    if (source == null) {
      return const RouteNotFound(RouteFailure.originOutsideCoverage);
    }
    final target = snapper.nearestNode(
      toLat,
      toLon,
      maxM: maxSnapMetres,
      accept: view.usable,
    );
    if (target == null) {
      return const RouteNotFound(RouteFailure.destinationOutsideCoverage);
    }
    if (source == target) return const RouteNotFound(RouteFailure.sameLocation);

    final world = _assemble(at.toUtc(), state);
    final planned = planRouteDetailed(
      graph: view.graph,
      source: source,
      target: target,
      computedAt: at.toUtc(),
      userClass: userClass,
      z: user.z,
      lambda: user.lambda,
      hazardConfigByEdge: world.configs,
      observationsByEdge: world.observations,
      sourceClassByObservationId: world.sourceClassById,
      queryId: queryId,
      edgeLabel: (id) => pack.streetName(id) ?? 'an unnamed stretch',
      beliefParams: beliefParams,
    );
    if (planned == null) return const RouteNotFound(RouteFailure.noRoute);

    final avoided = <GeoPoint>[
      for (final alt in planned.trace.alternatives)
        for (final b in alt.blockingEdges) _edgeMidpoint(b.edgeId),
    ];
    stopwatch.stop();
    return RouteFound(
      RoutePlan(
        trace: planned.trace,
        path: simplifyPath(
          [for (final n in planned.chosenNodes) _node(n)],
          maxPoints: maxPathPoints,
        ),
        fastestPath: simplifyPath(
          [for (final n in planned.fastestNodes) _node(n)],
          maxPoints: maxPathPoints,
        ),
        detours: planned.detours,
        origin: _node(source),
        destination: _node(target),
        originSnapMetres: snapper.distanceMetres(
          fromLat,
          fromLon,
          pack.nodeLat[source],
          pack.nodeLon[source],
        ),
        destinationSnapMetres: snapper.distanceMetres(
          toLat,
          toLon,
          pack.nodeLat[target],
          pack.nodeLon[target],
        ),
        eventState: state,
        computeMilliseconds: stopwatch.elapsedMicroseconds / 1000,
        avoidedHazards: avoided,
      ),
    );
  }

  /// Every hazard-configured edge with its current belief, for drawing the
  /// risk overlay. [userClass] selects the pessimism `z` for `pPessimistic`.
  ///
  /// With [bbox] only edges with an end inside the box are computed, so a map showing one
  /// neighbourhood does not pay for a whole state (ADR-020). With [limit], if more edges match,
  /// the most hazardous are kept.
  List<RiskEdge> riskEdges({
    required DateTime at,
    String userClass = 'commuter',
    EventState? eventState,
    ({double minLon, double minLat, double maxLon, double maxLat})? bbox,
    int? limit,
  }) {
    final user = userClasses[userClass];
    if (user == null) {
      throw ArgumentError.value(userClass, 'userClass', 'unknown user class');
    }
    final world = _assemble(at.toUtc(), eventState ?? this.eventState);
    final out = <RiskEdge>[];
    bool inside(double lat, double lon) =>
        lon >= bbox!.minLon &&
        lon <= bbox.maxLon &&
        lat >= bbox.minLat &&
        lat <= bbox.maxLat;
    for (final entry in world.configs.entries) {
      final config = entry.value;
      if (bbox != null) {
        final e = entry.key;
        final a = pack.edgeFrom[e];
        final b = pack.edgeTo[e];
        if (!inside(pack.nodeLat[a], pack.nodeLon[a]) &&
            !inside(pack.nodeLat[b], pack.nodeLon[b])) {
          continue;
        }
      }
      final belief = fuseBeta(
        observations: world.observations[entry.key] ?? const [],
        priorLogOdds: config.priorLogOdds,
        t: at.toUtc(),
        decayTauSeconds: config.decayTauSeconds,
        params: beliefParams,
      );
      final newest = belief.newestObservationAt;
      out.add(
        RiskEdge(
          edgeId: entry.key,
          from: _node(pack.edgeFrom[entry.key]),
          to: _node(pack.edgeTo[entry.key]),
          pMean: belief.pMean,
          pPessimistic: pessimisticBeta(belief: belief, z: user.z),
          nEff: belief.nEff,
          hasObservation: newest != null,
          newestObservationAgeSeconds: newest == null
              ? null
              : math.max(0, at.difference(newest).inSeconds.toDouble()),
          hazardClass: config.hazardClass,
          streetName: pack.streetName(entry.key),
        ),
      );
    }
    if (limit != null && out.length > limit) {
      out.sort((a, b) => b.pPessimistic.compareTo(a.pPessimistic));
      return out.sublist(0, limit);
    }
    return out;
  }
}

/// A routing graph for one travel profile and the nodes a traveller on it can
/// start or end at (a node needs a way in and a way out).
class _ProfileView {
  _ProfileView.of(this.graph);

  final CsrGraph graph;

  bool usable(int node) => graph.outDegree(node) > 0 && graph.inDegree(node) > 0;
}

double _round6(double v) => (v * 1e6).roundToDouble() / 1e6;

double _round5(double v) => (v * 1e5).roundToDouble() / 1e5;

/// Encodes [edges] as a GeoJSON `FeatureCollection` of two-point `LineString`s
/// with the belief as properties. The phone and `router_api` both use this so
/// the map draws the same thing from either source.
///
/// Properties: `id`, `p_mean`, `p_pessimistic`, `n_eff`, `has_observation`,
/// `age_s` (or `null`), `hazard_class`, `name` (or `null`).
///
/// With [compact] (what the maps use) coordinates are rounded to 5 decimals (about a metre) and
/// only `id`, `p_pessimistic` and `has_observation` are written, which is all the map draws. Measured
/// on Chennai's 8,921 hazard edges that is 1.6 MB against 2.4 MB, a third smaller; the coordinates
/// dominate, so the larger saving comes from sending only the visible area (`riskEdges` `bbox`).
Map<String, Object?> riskEdgesToGeoJson(
  List<RiskEdge> edges, {
  bool compact = false,
}) => {
  'type': 'FeatureCollection',
  'features': [
    for (final e in edges)
      {
        'type': 'Feature',
        'geometry': {
          'type': 'LineString',
          'coordinates': compact
              ? [
                  [_round5(e.from.lon), _round5(e.from.lat)],
                  [_round5(e.to.lon), _round5(e.to.lat)],
                ]
              : [
                  [_round6(e.from.lon), _round6(e.from.lat)],
                  [_round6(e.to.lon), _round6(e.to.lat)],
                ],
        },
        'properties': compact
            ? {
                'id': e.edgeId,
                'p_pessimistic': double.parse(e.pPessimistic.toStringAsFixed(3)),
                'has_observation': e.hasObservation,
              }
            : {
          'id': e.edgeId,
          'p_mean': double.parse(e.pMean.toStringAsFixed(4)),
          'p_pessimistic': double.parse(e.pPessimistic.toStringAsFixed(4)),
          'n_eff': double.parse(e.nEff.toStringAsFixed(3)),
          'has_observation': e.hasObservation,
          'age_s': e.newestObservationAgeSeconds?.round(),
          'hazard_class': e.hazardClass,
          'name': e.streetName,
        },
      },
  ],
};
