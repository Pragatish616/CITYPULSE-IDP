// ADR-018: a pack built by scripts/city_pipeline.py for a city that is not Chennai loads and routes
// with the same Dart code. "Testville" is a SYNTHETIC 6 x 6 grid (scripts/tests/make_testville_fixture.py).
import 'dart:io';
import 'dart:typed_data';

import 'package:pulse_router/pulse_router.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

ByteData _read(String name) => ByteData.sublistView(
  File('test/fixtures/testville/$name').readAsBytesSync(),
);

// Grid node (row r, column c): lat 20.000 + 0.004 r, lon 78.000 + 0.004 c.
double _lat(int r) => 20.0 + 0.004 * r;
double _lon(int c) => 78.0 + 0.004 * c;

void main() {
  late RoutingEngine engine;
  late CityConfig city;
  late MapPack pack;
  final at = DateTime.utc(2026, 10, 3, 6);

  setUpAll(() {
    pack = MapPack.parse(
      graph: _read('graph.bin'),
      nodes: _read('nodes.bin'),
      meta: _read('meta.bin'),
    );
    final hazards = EngineConfig.fromMap(
      loadYaml(File('../../config/hazard_classes.yaml').readAsStringSync())
          as YamlMap,
    );
    engine = RoutingEngine(
      pack: pack,
      hazardClasses: hazards.hazardClasses,
      userClasses: hazards.userClasses,
      travelProfiles: hazards.travelProfiles,
      sourceReliability: hazards.sourceReliability,
    );
    city = CityConfig.fromMap(
      (loadYaml(File('test/fixtures/testville/cities.yaml').readAsStringSync())
              as YamlMap)
          .cast<Object?, Object?>(),
      'testville',
    );
  });

  RouteOutcome route(double fromLat, double fromLon, double toLat, double toLon) =>
      engine.route(
        fromLat: fromLat,
        fromLon: fromLon,
        toLat: toLat,
        toLon: toLon,
        userClass: 'commuter',
        at: at,
        queryId: 'testville',
      );

  test('the pack parses to the size the Python builder reported', () {
    expect(pack.nodeCount, 36);
    expect(pack.edgeCount, 113);
  });

  test('the city config and the pack agree: the centre is inside the roads',
      () {
    expect(city.hazardLayer, isFalse);
    expect(city.contains(city.centreLat, city.centreLon), isTrue);
    expect(city.centreLat, inInclusiveRange(_lat(0), _lat(5)));
    expect(city.centreLon, inInclusiveRange(_lon(0), _lon(5)));
  });

  test('the router minimises time, not distance: it takes the faster primary '
      'Ring Road even though the grid path is shorter', () {
    final outcome = route(_lat(0), _lon(0), _lat(4), _lon(4));
    expect(outcome, isA<RouteFound>());
    final plan = (outcome as RouteFound).plan;
    // The shortest way is 4 blocks north + 4 east, about 3.45 km. The Ring Road
    // (row 6, lat 20.02) is primary class, so the route goes up the west side,
    // along the Ring Road and back down: longer but quicker.
    expect(plan.trace.chosen.distanceMeters, inInclusiveRange(3400, 4600));
    expect(
      plan.path.any((p) => (p.lat - _lat(5)).abs() < 1e-9),
      isTrue,
      reason: 'the route uses the primary-class Ring Road',
    );
    expect(plan.trace.chosen.durationSeconds, greaterThan(0));
  });

  test('the broken link in Column Street 4 forces a detour', () {
    // Nodes (2,3) and (3,3) are one block apart but only joined through other streets.
    final outcome = route(_lat(2), _lon(3), _lat(3), _lon(3));
    final metres = (outcome as RouteFound).plan.trace.chosen.distanceMeters;
    expect(metres, greaterThan(1000), reason: 'three blocks around, not one');
  });

  test('the one-way Ring Road can only be driven one way', () {
    final forward = route(_lat(5), _lon(2), _lat(5), _lon(3)) as RouteFound;
    final back = route(_lat(5), _lon(3), _lat(5), _lon(2)) as RouteFound;
    expect(forward.plan.trace.chosen.distanceMeters, lessThan(600));
    expect(
      back.plan.trace.chosen.distanceMeters,
      greaterThan(1000),
      reason: 'against the one-way the route goes down a row and back',
    );
  });

  test('a point in Chennai is outside this city\'s network, with no crash', () {
    final outcome = route(13.0419, 80.2339, _lat(3), _lon(3));
    expect(outcome, isA<RouteNotFound>());
    expect(
      (outcome as RouteNotFound).reason,
      RouteFailure.originOutsideCoverage,
    );
  });

  test('with no hazard layer nothing is flagged as a hazard-map edge', () {
    expect(engine.riskEdges(at: at, userClass: 'commuter'), isEmpty);
  });

  test('street search works on a pack from another city', () {
    final hits = PlaceIndex(pack).search('column street 4');
    expect(hits, isNotEmpty);
    expect(hits.first.name, 'Column Street 4');
  });
}
