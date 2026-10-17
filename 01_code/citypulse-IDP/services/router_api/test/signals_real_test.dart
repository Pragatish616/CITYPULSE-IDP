// C8 on the real Chennai pack: OpenStreetMap traffic signals snap to the graph, and a real route's time answer counts them.
import 'dart:io';

import 'package:pulse_router/pulse_router.dart';
import 'package:router_api/router_api.dart';
import 'package:test/test.dart';

void main() {
  test('Chennai signals snap to the graph and a cross-city route passes some of them', () {
    final s = bootstrapRouter({'CITY': 'chennai', 'EVENT_STATE': 'dry'}, startSync: false, accessLog: (_) {});
    final points = parseSignalPoints(File('../../data/places/chennai-poi-2026-10-15/poi.json').readAsStringSync());
    final nodes = s.engine.signalNodes;
    stderr.writeln('signals: ${points.length} points, ${nodes.length} distinct nodes within 30 m');
    expect(points.length, 485);
    expect(nodes.length, greaterThan(300));
    final r = s.engine.route(
      fromLat: 13.0418,
      fromLon: 80.2341,
      toLat: 12.9791,
      toLon: 80.2209,
      userClass: 'commuter',
      at: DateTime.utc(2026, 10, 17, 6),
    );
    final trace = (r as RouteFound).plan.trace;
    final fact = [for (final f in trace.contextFacts) if (f.key == 'route_signals') f];
    stderr.writeln('T. Nagar -> Velachery: ${fact.isEmpty ? 0 : fact.single.value} signals');
    expect(fact, hasLength(1));
    expect(fact.single.value as int, greaterThan(0));
  });
}
