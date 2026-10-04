// Tests for the binary map pack, the spatial snapper and the routing engine
// (PLAN.md M2.1 / F-06, M1.1 / F-02, M1.5 / F-09). They run against the real
// pack built by scripts/build_packs.py from the pinned 2026-09-14 snapshot, so
// they need data/packs/2026-10-02/ and data/graph/2026-09-14/ on disk.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pulse_router/pulse_router.dart';
import 'package:pulse_router/src/cli_io.dart';
import 'package:test/test.dart';

const _packDir = '../../data/packs/2026-10-02';
const _jsonGraph = '../../data/graph/2026-09-14/chennai_graph_cli.json';

ByteData _read(String name) {
  final bytes = File('$_packDir/$name').readAsBytesSync();
  return ByteData.sublistView(bytes);
}

MapPack _loadPack() => MapPack.parse(
  graph: _read('graph.bin'),
  nodes: _read('nodes.bin'),
  meta: _read('meta.bin'),
);

// config/hazard_classes.yaml, transcribed (placeholders included).
const _classes = {
  'flood': HazardClassParams(
    decayTauSeconds: 7200,
    severity: 1,
    hMaxMm: 300,
    epsilon: 0.1,
  ),
  'waterlogging': HazardClassParams(
    decayTauSeconds: 5400,
    severity: 0.6,
    hMaxMm: 200,
    epsilon: 0.15,
  ),
};
const _users = {
  'commuter': UserClassParams(z: 0, lambda: 0.3),
  'pedestrian': UserClassParams(z: 1.28, lambda: 1.2),
  'emergency': UserClassParams(z: 2, lambda: 1),
};
const _reliability = {
  'municipal_sensor': 0.97,
  'official_feed': 0.92,
  'verified_responder': 0.9,
  'crowd': 0.6,
  'app_traversal': 0.7,
};

void main() {
  late MapPack pack;
  late EdgeSnapper snapper;
  final t = DateTime.utc(2026, 10, 2, 6);

  setUpAll(() {
    pack = _loadPack();
    snapper = EdgeSnapper(pack);
  });

  RoutingEngine newEngine({EventState state = EventState.active}) =>
      RoutingEngine(
        pack: pack,
        snapper: snapper,
        hazardClasses: _classes,
        userClasses: _users,
        sourceReliability: _reliability,
        eventState: state,
      );

  // ---- pack ---------------------------------------------------------------
  group('MapPack', () {
    test('has the pinned snapshot\'s counts and first-edge data', () {
      expect(pack.nodeCount, 193191);
      expect(pack.edgeCount, 471240);
      expect(pack.priorLogOdds(0), closeTo(-2.758, 1e-12));
      expect(pack.streetName(0), 'Muthuswamy Road');
      expect(pack.edgeFrom[0], 0);
      expect(pack.edgeTo[0], 1);
      expect(pack.edgeFreeFlowSeconds[0], closeTo(32.488, 1e-12));
    });

    test('routes identically to the JSON graph it was built from '
        '(100 seeded pairs: same cost, same edge path)', () {
      final jsonGraph = graphFromJson(
        jsonDecode(File(_jsonGraph).readAsStringSync()) as Map<String, Object?>,
      );
      final rng = math.Random(20261002);
      var compared = 0;
      while (compared < 100) {
        final s = rng.nextInt(pack.nodeCount);
        final g = rng.nextInt(pack.nodeCount);
        if (s == g) continue;
        double? freeFlow(RouteEdge e) => e.freeFlowSeconds;
        final a = bidirectionalDijkstra(
          graph: pack.graph,
          source: s,
          target: g,
          edgeCost: freeFlow,
        );
        final b = bidirectionalDijkstra(
          graph: jsonGraph,
          source: s,
          target: g,
          edgeCost: freeFlow,
        );
        expect(a == null, b == null, reason: '$s -> $g reachability');
        if (a == null || b == null) continue;
        expect(a.totalCostSeconds, closeTo(b.totalCostSeconds, 1e-9));
        expect(a.edgePath, equals(b.edgePath), reason: '$s -> $g');
        compared++;
      }
    });

    test('rejects a truncated or mislabelled file with a clear error', () {
      final graph = File('$_packDir/graph.bin').readAsBytesSync();
      expect(
        () => MapPack.parse(
          graph: ByteData.sublistView(graph.sublist(0, graph.length - 7)),
          nodes: _read('nodes.bin'),
          meta: _read('meta.bin'),
        ),
        throwsA(isA<MapPackFormatException>()),
      );
      final wrongMagic = Uint8List.fromList(graph)..[0] = 0x58;
      expect(
        () => MapPack.parse(
          graph: ByteData.sublistView(wrongMagic),
          nodes: _read('nodes.bin'),
          meta: _read('meta.bin'),
        ),
        throwsA(isA<MapPackFormatException>()),
      );
      expect(
        () => MapPack.parse(
          graph: _read('graph.bin'),
          nodes: _read('graph.bin'), // wrong file in the nodes slot
          meta: _read('meta.bin'),
        ),
        throwsA(isA<MapPackFormatException>()),
      );
    });
  });

  // ---- snapper ------------------------------------------------------------
  group('EdgeSnapper', () {
    test('a node\'s own coordinates snap back to that node', () {
      for (final n in [0, 1234, 31140, 47036, 150000]) {
        if (pack.graph.outDegree(n) == 0 && pack.graph.inDegree(n) == 0) {
          continue;
        }
        final got = snapper.nearestNode(pack.nodeLat[n], pack.nodeLon[n]);
        expect(
          snapper.distanceMetres(
            pack.nodeLat[n],
            pack.nodeLon[n],
            pack.nodeLat[got!],
            pack.nodeLon[got],
          ),
          lessThan(0.5),
          reason: 'node $n snapped to $got',
        );
      }
    });

    test('a point in the sea is outside coverage', () {
      expect(snapper.nearestNode(13.05, 80.60), isNull);
      expect(snapper.nearestNode(0, 0), isNull);
    });

    test('nearestNode honours the accept filter', () {
      final lat = pack.nodeLat[31140];
      final lon = pack.nodeLon[31140];
      final other = snapper.nearestNode(lat, lon, accept: (n) => n != 31140);
      expect(other, isNotNull);
      expect(other, isNot(31140));
    });

    test('a point on a two-way street matches BOTH directions at the same '
        'distance (the on-device half of F-02)', () {
      // Find an edge with a reverse twin.
      int? edge;
      int? twin;
      for (var e = 5000; e < 20000 && edge == null; e++) {
        for (var i = 0; i < pack.graph.outDegree(pack.edgeTo[e]); i++) {
          final r = pack.graph.outEdge(pack.edgeTo[e], i);
          if (r.to == pack.edgeFrom[e]) {
            edge = e;
            twin = r.edgeId;
            break;
          }
        }
      }
      expect(edge, isNotNull);
      final a = edge!;
      final lat =
          (pack.nodeLat[pack.edgeFrom[a]] + pack.nodeLat[pack.edgeTo[a]]) / 2;
      final lon =
          (pack.nodeLon[pack.edgeFrom[a]] + pack.nodeLon[pack.edgeTo[a]]) / 2;
      final matches = snapper.edgesNear(lat, lon, radiusM: 30);
      final byId = {for (final m in matches) m.edgeId: m.distanceM};
      expect(byId.containsKey(a), isTrue);
      expect(byId.containsKey(twin), isTrue);
      expect(byId[a]!, closeTo(byId[twin]!, 1e-6));
      expect(byId[a]!, lessThan(1));
    });

    test('edgesNear is sorted, bounded by the limit and the radius', () {
      final lat = pack.nodeLat[31140];
      final lon = pack.nodeLon[31140];
      final matches = snapper.edgesNear(lat, lon, radiusM: 120, limit: 5);
      expect(matches.length, lessThanOrEqualTo(5));
      for (var i = 1; i < matches.length; i++) {
        expect(
          matches[i].distanceM,
          greaterThanOrEqualTo(matches[i - 1].distanceM),
        );
      }
      expect(matches.every((m) => m.distanceM <= 120), isTrue);
      expect(snapper.edgesNear(lat, lon, radiusM: 0), isEmpty);
    });
  });

  // ---- engine -------------------------------------------------------------
  group('RoutingEngine', () {
    GeoPoint node(int n) => (lat: pack.nodeLat[n], lon: pack.nodeLon[n]);

    RouteFound route(
      RoutingEngine engine,
      int from,
      int to, {
      String user = 'commuter',
      EventState? state,
    }) {
      final a = node(from);
      final b = node(to);
      final out = engine.route(
        fromLat: a.lat,
        fromLon: a.lon,
        toLat: b.lat,
        toLon: b.lon,
        userClass: user,
        at: t,
        eventState: state,
      );
      expect(out, isA<RouteFound>(), reason: '$out');
      return out as RouteFound;
    }

    test('routes T. Nagar to Velachery from coordinates alone and returns a '
        'valid trace and drawable path', () {
      final found = route(newEngine(), 31140, 47036);
      final plan = found.plan;
      expect(plan.path.length, greaterThan(10));
      expect(plan.trace.chosen.distanceMeters, greaterThan(3000));
      expect(plan.originSnapMetres, lessThan(1));
      expect(plan.trace.chosen.geometryRef, startsWith('nodes:31140,'));
      expect(plan.computeMilliseconds, greaterThan(0));
    });

    test('unknown user class throws; far-away points are reported as '
        'outside coverage, not as a crash', () {
      final engine = newEngine();
      expect(
        () => engine.route(
          fromLat: 13,
          fromLon: 80.2,
          toLat: 13.01,
          toLon: 80.21,
          userClass: 'cyclist',
          at: t,
        ),
        throwsArgumentError,
      );
      final outside = engine.route(
        fromLat: 0,
        fromLon: 0,
        toLat: pack.nodeLat[31140],
        toLon: pack.nodeLon[31140],
        userClass: 'commuter',
        at: t,
      );
      expect(
        (outside as RouteNotFound).reason,
        RouteFailure.originOutsideCoverage,
      );
      final here = node(31140);
      final same = engine.route(
        fromLat: here.lat,
        fromLon: here.lon,
        toLat: here.lat,
        toLon: here.lon,
        userClass: 'commuter',
        at: t,
      );
      expect((same as RouteNotFound).reason, RouteFailure.sameLocation);
    });

    test('F-09: on a dry day the static prior is ignored -- even the '
        'emergency class routes at free-flow cost', () {
      final engine = newEngine();
      final dry = route(
        engine,
        31140,
        47036,
        user: 'emergency',
        state: EventState.dry,
      );
      expect(dry.plan.trace.chosen.hazardTimePenaltySeconds, closeTo(0, 1e-6));
      expect(dry.plan.detours, isFalse);
      expect(dry.plan.trace.alternatives, isEmpty);
      expect(dry.plan.eventState, EventState.dry);

      final active = route(
        engine,
        31140,
        47036,
        user: 'emergency',
        state: EventState.active,
      );
      // With the prior applied the emergency class pays for hazard-map edges.
      expect(
        active.plan.trace.chosen.hazardTimePenaltySeconds,
        greaterThanOrEqualTo(dry.plan.trace.chosen.hazardTimePenaltySeconds),
      );
    });

    test('a report is attached to both directions of its street, and '
        'riskEdges shows both with the report counted (F-02)', () {
      final engine = newEngine(state: EventState.dry);
      // Pick a two-way edge well away from the GCC hazard zones' prior set.
      int? edge;
      for (var e = 100000; e < 120000 && edge == null; e++) {
        if (pack.priorLogOdds(e) > -3.5) continue;
        for (var i = 0; i < pack.graph.outDegree(pack.edgeTo[e]); i++) {
          if (pack.graph.outEdge(pack.edgeTo[e], i).to == pack.edgeFrom[e]) {
            edge = e;
          }
        }
      }
      final e = edge!;
      final lat =
          (pack.nodeLat[pack.edgeFrom[e]] + pack.nodeLat[pack.edgeTo[e]]) / 2;
      final lon =
          (pack.nodeLon[pack.edgeFrom[e]] + pack.nodeLon[pack.edgeTo[e]]) / 2;

      expect(engine.riskEdges(at: t), isEmpty, reason: 'dry, no reports');

      final attached = engine.addObservation(
        EngineObservation(
          id: 'r1',
          hazardClass: 'flood',
          polarity: 1,
          lat: lat,
          lon: lon,
          observedAt: t.subtract(const Duration(minutes: 10)),
          sourceClass: 'verified_responder',
        ),
      );
      expect(attached, greaterThanOrEqualTo(2));
      final risk = engine.riskEdges(at: t);
      final ids = risk.map((r) => r.edgeId).toSet();
      expect(ids.contains(e), isTrue);
      expect(risk.every((r) => r.hasObservation), isTrue);
      // The same street the other way round also carries it.
      final twin = risk.where(
        (r) =>
            r.from ==
                (
                  lat: pack.nodeLat[pack.edgeTo[e]],
                  lon: pack.nodeLon[pack.edgeTo[e]],
                ) &&
            r.to ==
                (
                  lat: pack.nodeLat[pack.edgeFrom[e]],
                  lon: pack.nodeLon[pack.edgeFrom[e]],
                ),
      );
      expect(twin, isNotEmpty);
    });

    test('adding the same observation id twice is a no-op (G-Set)', () {
      final engine = newEngine();
      final o = EngineObservation(
        id: 'dup',
        hazardClass: 'flood',
        polarity: 1,
        lat: pack.nodeLat[31140],
        lon: pack.nodeLon[31140],
        observedAt: t,
        sourceClass: 'crowd',
      );
      expect(engine.addObservation(o), greaterThan(0));
      expect(engine.addObservation(o), 0);
      expect(engine.observationCount, 1);
    });

    test('invalid observations are rejected with a clear error', () {
      final engine = newEngine();
      EngineObservation make({
        String cls = 'flood',
        String src = 'crowd',
        int pol = 1,
        double lat = 13,
      }) => EngineObservation(
        id: 'x$cls$src$pol$lat',
        hazardClass: cls,
        polarity: pol,
        lat: lat,
        lon: 80.2,
        observedAt: t,
        sourceClass: src,
      );
      expect(
        () => engine.addObservation(make(cls: 'earthquake')),
        throwsArgumentError,
      );
      expect(
        () => engine.addObservation(make(src: 'rumour')),
        throwsArgumentError,
      );
      expect(() => engine.addObservation(make(pol: 0)), throwsArgumentError);
      expect(
        () => engine.addObservation(make(lat: double.nan)),
        throwsArgumentError,
      );
    });

    test('a deep-water report on an ordinary street (no hazard-map entry, '
        'so previously invisible to routing) reroutes the traveller and is '
        'explained as a removed edge (F-06)', () {
      final engine = newEngine(state: EventState.dry);
      final base = route(engine, 31140, 47036);
      expect(base.plan.trace.alternatives, isEmpty);

      // Put a 450 mm sensor reading on a mid-route street.
      final path = base.plan.path;
      final mid = path.length ~/ 2;
      final lat = (path[mid].lat + path[mid + 1].lat) / 2;
      final lon = (path[mid].lon + path[mid + 1].lon) / 2;
      engine.addObservation(
        EngineObservation(
          id: 'deep',
          hazardClass: 'flood',
          polarity: 1,
          lat: lat,
          lon: lon,
          observedAt: t.subtract(const Duration(minutes: 5)),
          sourceClass: 'municipal_sensor',
          depthMm: 450,
        ),
      );
      final after = route(engine, 31140, 47036);
      expect(after.plan.detours, isTrue);
      expect(after.plan.trace.alternatives, hasLength(1));
      final alt = after.plan.trace.alternatives.single;
      expect(alt.rejectedBecause, RejectedBecause.chanceConstraint);
      expect(alt.blockingEdges, isNotEmpty);
      expect(
        alt.blockingEdges.every((b) => b.removedByChanceConstraint),
        isTrue,
      );
      expect(alt.blockingEdges.first.hasObservation, isTrue);
      expect(alt.blockingEdges.first.sourceClass, 'municipal_sensor');
      expect(after.plan.avoidedHazards, isNotEmpty);
    });

    test(
      'a future-dated report is ignored by an earlier query (replay-safe)',
      () {
        final engine = newEngine(state: EventState.dry);
        engine.addObservation(
          EngineObservation(
            id: 'future',
            hazardClass: 'flood',
            polarity: 1,
            lat: pack.nodeLat[31140],
            lon: pack.nodeLon[31140],
            observedAt: t.add(const Duration(hours: 2)),
            sourceClass: 'municipal_sensor',
            depthMm: 500,
          ),
        );
        expect(engine.riskEdges(at: t), isEmpty);
        expect(
          engine.riskEdges(at: t.add(const Duration(hours: 3))),
          isNotEmpty,
        );
      },
    );
  });

  // ---- crowd depth cannot hard-block -----------------------------------------
  group('depth reliability gate', () {
    test('a knee-deep CROWD report does not remove a road by itself, but the '
        'same reading from a municipal sensor does', () {
      RoutePlan plan(String sourceClass) {
        final engine = RoutingEngine(
          pack: pack,
          snapper: snapper,
          hazardClasses: _classes,
          userClasses: _users,
          sourceReliability: _reliability,
          eventState: EventState.dry,
        );
        const from = 31140;
        const to = 47036;
        GeoPoint n(int i) => (lat: pack.nodeLat[i], lon: pack.nodeLon[i]);
        final base = engine.route(
          fromLat: n(from).lat,
          fromLon: n(from).lon,
          toLat: n(to).lat,
          toLon: n(to).lon,
          userClass: 'commuter',
          at: t,
        ) as RouteFound;
        final path = base.plan.path;
        final mid = path.length ~/ 2;
        engine.addObservation(
          EngineObservation(
            id: 'depth-$sourceClass',
            hazardClass: 'flood',
            polarity: 1,
            lat: (path[mid].lat + path[mid + 1].lat) / 2,
            lon: (path[mid].lon + path[mid + 1].lon) / 2,
            observedAt: t.subtract(const Duration(minutes: 5)),
            sourceClass: sourceClass,
            depthMm: 450,
          ),
        );
        return (engine.route(
          fromLat: n(from).lat,
          fromLon: n(from).lon,
          toLat: n(to).lat,
          toLon: n(to).lon,
          userClass: 'commuter',
          at: t,
        ) as RouteFound).plan;
      }

      final crowd = plan('crowd');
      final sensor = plan('municipal_sensor');
      expect(
        crowd.trace.alternatives
            .expand((a) => a.blockingEdges)
            .where((b) => b.removedByChanceConstraint),
        isEmpty,
        reason: 'one anonymous report must not close a road',
      );
      expect(
        sensor.trace.alternatives
            .expand((a) => a.blockingEdges)
            .where((b) => b.removedByChanceConstraint),
        isNotEmpty,
      );
    });
  });

  // ---- place search ------------------------------------------------------------
  group('PlaceIndex', () {
    late PlaceIndex places;
    setUpAll(() => places = PlaceIndex(pack));

    test('indexes thousands of named stretches, more than distinct names '
        '(the same name recurs in different parts of the city)', () {
      expect(places.stretchCount, greaterThan(7808));
    });

    test('prefix matches rank before substring matches', () {
      final r = places.search('mount');
      expect(r, isNotEmpty);
      expect(r.first.name.toLowerCase(), startsWith('mount'));
    });

    test(
      'with a "near" point, results of equal relevance are nearest first',
      () {
        final near = (lat: pack.nodeLat[31140], lon: pack.nodeLon[31140]);
        final r = places.search('main road', near: near, limit: 40);
        expect(r.length, greaterThan(5));
        final starts = r
            .where((m) => m.name.toLowerCase().startsWith('main road'))
            .toList();
        for (var i = 1; i < starts.length; i++) {
          expect(
            starts[i].distanceMetres!,
            greaterThanOrEqualTo(starts[i - 1].distanceMetres!),
          );
        }
      },
    );

    test('too short, empty or unmatched queries return nothing', () {
      expect(places.search(''), isEmpty);
      expect(places.search('a'), isEmpty);
      expect(places.search('zzzzqqqq'), isEmpty);
      expect(places.search('mount', limit: 0), isEmpty);
    });

    test('every result lies inside the mapped area', () {
      for (final m in places.search('road', limit: 8)) {
        expect(m.point.lat, inInclusiveRange(12.75, 13.25));
        expect(m.point.lon, inInclusiveRange(79.95, 80.35));
      }
    });
  });
}
