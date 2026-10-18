// C8: traffic signals on the route. Parsing the places layer, and counting the distinct signal nodes a route goes through.
import 'dart:convert';

import 'package:pulse_router/pulse_router.dart';
import 'package:test/test.dart';

RouteEdge _e(int id, int from, int to) =>
    RouteEdge(edgeId: id, from: from, to: to, freeFlowSeconds: 10, freeFlowKmh: 30);

void main() {
  final asOf = DateTime.utc(2026, 10, 17);

  group('parseSignalPoints', () {
    test('keeps only rows whose category is signal', () {
      final json = jsonEncode({
        'version': 1,
        'categories': [
          {'id': 'shop'},
          {'id': 'signal'},
        ],
        'fields': ['lat', 'lon', 'category', 'name', 'kind', 'name_ta'],
        'places': [
          [13.0, 80.2, 0, 'A shop', 'shop', ''],
          [13.01, 80.21, 1, '', 'traffic signals', ''],
          [13.02, 80.22, 1, 'Signal', 'traffic signals', ''],
        ],
      });
      expect(parseSignalPoints(json), [(13.01, 80.21), (13.02, 80.22)]);
    });

    test('a layer without a signal category has no signals; a broken file is an error', () {
      expect(parseSignalPoints(jsonEncode({'categories': [{'id': 'shop'}], 'places': <Object?>[]})), isEmpty);
      expect(() => parseSignalPoints('[]'), throwsFormatException);
      expect(() => parseSignalPoints(jsonEncode({'places': <Object?>[]})), throwsFormatException);
    });
  });

  group('routeSignalFact', () {
    final route = [_e(0, 1, 2), _e(1, 2, 3), _e(2, 3, 4), _e(3, 4, 5)];

    test('counts distinct signal nodes the route goes through', () {
      final f = routeSignalFact(route, {2, 4, 99}, asOf)!;
      expect(f.key, 'route_signals');
      expect(f.value, 2);
      expect(f.label, 'traffic signals on this route');
    });

    test('the start node is not passed through, so it does not count', () {
      expect(routeSignalFact(route, {1}, asOf), isNull);
    });

    test('a node visited twice counts once', () {
      final loop = [_e(0, 1, 2), _e(1, 2, 3), _e(2, 3, 2), _e(3, 2, 5)];
      expect(routeSignalFact(loop, {2}, asOf)!.value, 1);
    });

    test('no signal data, or none on the route, says nothing (OpenStreetMap is incomplete)', () {
      expect(routeSignalFact(route, const {}, asOf), isNull);
      expect(routeSignalFact(route, {42}, asOf), isNull);
    });
  });
}
