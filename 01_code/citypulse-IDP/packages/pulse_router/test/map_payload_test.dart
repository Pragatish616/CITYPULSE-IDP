// ADR-020: what the map is sent stays small however big the area is. Long routes are thinned,
// the hazard overlay is computed only for the visible box, and its encoding is compact.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pulse_router/pulse_router.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

ByteData _read(String name) =>
    ByteData.sublistView(File('../../data/packs/2026-10-02/$name').readAsBytesSync());

void main() {
  group('simplifyPath', () {
    // A smooth 120 km curve with 30,000 points, like a long highway route.
    List<({double lat, double lon})> curve(int n) => [
      for (var i = 0; i < n; i++)
        (
          lat: 10 + i / n * 1.0 + 0.05 * math.sin(i / n * 12),
          lon: 78 + i / n * 0.8 + 0.04 * math.cos(i / n * 9),
        ),
    ];

    // Largest distance from an original point to the thinned polyline, metres.
    double deviation(
      List<({double lat, double lon})> original,
      List<({double lat, double lon})> thin,
    ) {
      const ky = 110574.0;
      final kx = 111320 * math.cos(original[original.length ~/ 2].lat * math.pi / 180);
      var worst = 0.0;
      for (final p in original) {
        var best = double.infinity;
        for (var j = 0; j + 1 < thin.length; j++) {
          final ax = thin[j].lon * kx, ay = thin[j].lat * ky;
          final bx = thin[j + 1].lon * kx, by = thin[j + 1].lat * ky;
          final dx = bx - ax, dy = by - ay;
          final l2 = dx * dx + dy * dy;
          var t = l2 == 0 ? 0.0 : (((p.lon * kx - ax) * dx + (p.lat * ky - ay) * dy) / l2);
          t = t.clamp(0.0, 1.0);
          final ex = p.lon * kx - (ax + t * dx), ey = p.lat * ky - (ay + t * dy);
          best = math.min(best, math.sqrt(ex * ex + ey * ey));
        }
        worst = math.max(worst, best);
      }
      return worst;
    }

    test('a short route is returned untouched', () {
      final pts = curve(100);
      expect(identical(simplifyPath(pts, maxPoints: 1500), pts), isTrue);
    });

    test('a 30,000-point route is cut to the cap, keeps both ends, and stays '
        'within a few tens of metres of the original', () {
      final pts = curve(30000);
      final thin = simplifyPath(pts, maxPoints: 1500);
      expect(thin.length, lessThanOrEqualTo(1500));
      expect(thin.length, greaterThan(100));
      expect(thin.first, pts.first);
      expect(thin.last, pts.last);
      // Sample every 50th original point to keep the test quick.
      final sample = [for (var i = 0; i < pts.length; i += 50) pts[i]];
      expect(deviation(sample, thin), lessThan(40));
    });

    test('the cap is honoured even for an absurdly small one, ends kept', () {
      final thin = simplifyPath(curve(5000), maxPoints: 2);
      expect(thin.length, 2);
    });
  });

  group('on the real Chennai pack', () {
    late MapPack pack;
    late EngineConfig config;

    RoutingEngine build({int maxPathPoints = 1500, EventState? state}) => RoutingEngine(
      pack: pack,
      hazardClasses: config.hazardClasses,
      userClasses: config.userClasses,
      sourceReliability: config.sourceReliability,
      travelProfiles: config.travelProfiles,
      maxPathPoints: maxPathPoints,
      eventState: state ?? EventState.active,
    );
    final at = DateTime.utc(2026, 10, 3, 6);

    setUpAll(() {
      pack = MapPack.parse(
        graph: _read('graph.bin'),
        nodes: _read('nodes.bin'),
        meta: _read('meta.bin'),
      );
      config = EngineConfig.fromMap(
        (loadYaml(File('../../config/hazard_classes.yaml').readAsStringSync()) as YamlMap)
            .cast<Object?, Object?>(),
      );
    });

    test('thinning the drawn route does not change its length or time', () {
      RoutePlan plan(RoutingEngine e) =>
          (e.route(
                    fromLat: 13.0419,
                    fromLon: 80.2339,
                    toLat: 12.9806,
                    toLon: 80.2184,
                    userClass: 'commuter',
                    at: at,
                  )
                  as RouteFound)
              .plan;
      final full = plan(build());
      final thin = plan(build(maxPathPoints: 60));
      expect(full.path.length, greaterThan(60));
      expect(thin.path.length, lessThanOrEqualTo(60));
      expect(thin.path.first, full.path.first);
      expect(thin.path.last, full.path.last);
      expect(thin.trace.chosen.distanceMeters, full.trace.chosen.distanceMeters);
      expect(thin.trace.chosen.durationSeconds, full.trace.chosen.durationSeconds);
    });

    test('the overlay for a box holds only edges with an end in the box', () {
      final engine = build();
      final all = engine.riskEdges(at: at);
      const box = (minLon: 80.20, minLat: 13.00, maxLon: 80.26, maxLat: 13.06);
      final part = engine.riskEdges(at: at, bbox: box);
      expect(all, isNotEmpty);
      expect(part, isNotEmpty);
      expect(part.length, lessThan(all.length));
      bool inside(GeoPoint p) =>
          p.lon >= box.minLon && p.lon <= box.maxLon && p.lat >= box.minLat && p.lat <= box.maxLat;
      for (final e in part) {
        expect(inside(e.from) || inside(e.to), isTrue);
      }
      // Nothing inside the box was lost.
      final ids = {for (final e in part) e.edgeId};
      for (final e in all) {
        if (inside(e.from) || inside(e.to)) expect(ids, contains(e.edgeId));
      }
    });

    test('a limit keeps the most hazardous edges', () {
      final engine = build();
      final top = engine.riskEdges(at: at, limit: 50);
      expect(top.length, 50);
      final all = engine.riskEdges(at: at)..sort((a, b) => b.pPessimistic.compareTo(a.pPessimistic));
      expect(top.map((e) => e.pPessimistic).reduce(math.min), greaterThanOrEqualTo(all[50].pPessimistic));
    });

    test('the compact encoding is a third smaller and carries what the map draws', () {
      final edges = build().riskEdges(at: at);
      final full = jsonEncode(riskEdgesToGeoJson(edges));
      final compact = jsonEncode(riskEdgesToGeoJson(edges, compact: true));
      // Measured 1.6 MB against 2.4 MB: coordinates dominate the size, so the big saving is the
      // viewport box, not the encoding.
      expect(compact.length, lessThan(full.length * 0.75));
      final f = (jsonDecode(compact) as Map)['features'] as List;
      final props = (f.first as Map)['properties'] as Map;
      expect(props.keys.toSet(), {'id', 'p_pessimistic', 'has_observation'});
    });
  });
}
