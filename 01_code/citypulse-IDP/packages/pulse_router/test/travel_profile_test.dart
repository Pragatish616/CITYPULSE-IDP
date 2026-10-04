// ADR-019: each kind of traveller gets its own speeds, its own roads and its own route.
// Uses the synthetic Testville grid (scripts/tests/make_testville_fixture.py) and the real
// config/hazard_classes.yaml, so the shipped profiles are what is exercised.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pulse_router/pulse_router.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

ByteData _read(String name) =>
    ByteData.sublistView(File('test/fixtures/testville/$name').readAsBytesSync());

double _lat(int r) => 20.0 + 0.004 * r;
double _lon(int c) => 78.0 + 0.004 * c;

Map<Object?, Object?> _yaml(String text) =>
    (loadYaml(text) as YamlMap).cast<Object?, Object?>();

void main() {
  late MapPack pack;
  late EngineConfig config;
  late RoutingEngine engine;
  final at = DateTime.utc(2026, 10, 3, 6);

  RoutingEngine build({
    Map<String, UserClassParams>? users,
    Map<String, TravelProfile>? profiles,
  }) => RoutingEngine(
    pack: pack,
    hazardClasses: config.hazardClasses,
    userClasses: users ?? config.userClasses,
    sourceReliability: config.sourceReliability,
    travelProfiles: profiles ?? config.travelProfiles,
  );

  RoutePlan plan(RoutingEngine e, String user, (int, int) from, (int, int) to) {
    final o = e.route(
      fromLat: _lat(from.$1),
      fromLon: _lon(from.$2),
      toLat: _lat(to.$1),
      toLon: _lon(to.$2),
      userClass: user,
      at: at,
      queryId: 'profile-test',
    );
    expect(o, isA<RouteFound>(), reason: '$user $from -> $to');
    return (o as RouteFound).plan;
  }

  bool usesRing(RoutePlan p) => p.path.any((pt) => (pt.lat - _lat(5)).abs() < 1e-9);

  setUpAll(() {
    pack = MapPack.parse(
      graph: _read('graph.bin'),
      nodes: _read('nodes.bin'),
      meta: _read('meta.bin'),
    );
    config = EngineConfig.fromMap(
      _yaml(File('../../config/hazard_classes.yaml').readAsStringSync()),
    );
    engine = build();
  });

  group('the shipped profiles', () {
    test('four user classes map to four movement models', () {
      expect(config.userClasses['commuter']!.profile, 'car');
      expect(config.userClasses['pedestrian']!.profile, 'foot');
      expect(config.userClasses['cyclist']!.profile, 'bicycle');
      expect(config.userClasses['emergency']!.profile, 'emergency');
      expect(
        config.travelProfiles.keys,
        containsAll(['foot', 'bicycle', 'emergency']),
      );
    });

    test('the highway class order matches the shipped Chennai pack manifest', () {
      final manifest =
          jsonDecode(
                File('../../data/packs/2026-10-02/manifest.json').readAsStringSync(),
              )
              as Map<String, Object?>;
      expect(manifest['highway_codes'], kHighwayCodes);
    });
  });

  group('speeds and access', () {
    final foot = TravelProfile.fromMap(
      'foot',
      _yaml(
        'speed_kmh: { default: 5.0, primary: 4.5 }\n'
        'forbidden: [motorway]\n'
        'ignore_oneway: true\n',
      ),
    );

    test('a fixed speed per class, a default, and forbidden classes', () {
      expect(foot.speedOn('residential', 20), 5.0);
      expect(foot.speedOn('primary', 50), 4.5);
      expect(foot.speedOn('motorway', 70), isNull);
      expect(foot.isCar, isFalse);
      expect(TravelProfile.car.isCar, isTrue);
    });

    test('a multiplier scales the car speed and a cap limits it', () {
      const p = TravelProfile(speedMultiplier: 1.3, maxSpeedKmh: 90);
      expect(p.speedOn('residential', 20), closeTo(26, 1e-9));
      expect(p.speedOn('motorway', 70), 90, reason: '91 is capped to 90');
    });

    test('typos and nonsense are refused with the profile named', () {
      void bad(String yaml, Pattern message) => expect(
        () => TravelProfile.fromMap('x', _yaml(yaml)),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains(message),
          ),
        ),
      );
      bad('speed_kmh: { residental: 5 }', 'unknown road class');
      bad('forbidden: [freeway]', 'unknown road class');
      bad('speed_kmh: { default: -3 }', 'positive');
      bad('speed_multiplier: 0', 'positive');
      bad('speed_kph: 5', 'unknown key');
      bad('ignore_oneway: maybe', 'true or false');
    });

    test('a user class naming a missing profile is refused, at parse and at '
        'engine construction', () {
      expect(
        () => EngineConfig.fromMap(
          _yaml(
            'classes: { flood: { T_c_seconds: 7200, severity: 1.0 } }\n'
            'user_classes: { walker: { z: 1, lambda: 1, profile: foot } }\n'
            'source_reliability: { crowd: 0.6 }\n',
          ),
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => build(
          users: const {
            'walker': UserClassParams(z: 1, lambda: 1, profile: 'foot'),
          },
          profiles: const {},
        ),
        throwsArgumentError,
      );
    });
  });

  group('each mode routes for itself (Testville)', () {
    test('on foot: about 5 km/h on the shortest way, not the car route', () {
      final car = plan(engine, 'commuter', (0, 0), (4, 4));
      final walk = plan(engine, 'pedestrian', (0, 0), (4, 4));
      expect(usesRing(car), isTrue, reason: 'the car takes the faster primary Ring Road');
      expect(usesRing(walk), isFalse, reason: 'on foot the grid is shorter');
      final metres = walk.trace.chosen.distanceMeters;
      expect(metres, inInclusiveRange(3300, 3600), reason: '4 blocks north + 4 east');
      final kmh = metres / walk.trace.chosen.durationSeconds * 3.6;
      expect(kmh, closeTo(5.0, 0.1));
      expect(
        walk.trace.chosen.durationSeconds,
        greaterThan(car.trace.chosen.durationSeconds * 3),
      );
    });

    test('on foot you can walk against a one-way street; a car cannot', () {
      final carBack = plan(engine, 'commuter', (5, 3), (5, 2));
      final walkBack = plan(engine, 'pedestrian', (5, 3), (5, 2));
      expect(carBack.trace.chosen.distanceMeters, greaterThan(1000));
      expect(walkBack.trace.chosen.distanceMeters, lessThan(600));
    });

    test('a bicycle: about 15 km/h on quiet streets, obeys one-way streets, '
        'and shuns the busy primary road', () {
      final bike = plan(engine, 'cyclist', (0, 0), (4, 4));
      expect(usesRing(bike), isFalse);
      final kmh =
          bike.trace.chosen.distanceMeters / bike.trace.chosen.durationSeconds * 3.6;
      expect(kmh, closeTo(15.0, 0.2));
      final bikeBack = plan(engine, 'cyclist', (5, 3), (5, 2));
      expect(bikeBack.trace.chosen.distanceMeters, greaterThan(1000));
      final walk = plan(engine, 'pedestrian', (0, 0), (4, 4));
      expect(
        bike.trace.chosen.durationSeconds,
        closeTo(walk.trace.chosen.durationSeconds / 3, 5),
        reason: 'same streets at three times the speed',
      );
    });

    test('an emergency vehicle gains most on arterial roads and nothing in a '
        'residential lane', () {
      final car = plan(engine, 'commuter', (0, 0), (4, 4));
      final ambulance = plan(engine, 'emergency', (0, 0), (4, 4));
      // The car already takes the primary Ring Road, and so does the ambulance, only faster.
      expect(ambulance.path, car.path);
      final ratio =
          ambulance.trace.chosen.durationSeconds / car.trace.chosen.durationSeconds;
      expect(ratio, lessThan(1.0));
      expect(ratio, greaterThan(1 / 1.4), reason: 'part of the route is residential');
      // A route that never leaves residential lanes gets no benefit at all.
      final lane = plan(engine, 'emergency', (0, 0), (0, 2));
      final laneCar = plan(engine, 'commuter', (0, 0), (0, 2));
      expect(lane.trace.chosen.durationSeconds,
          closeTo(laneCar.trace.chosen.durationSeconds, 0.5));
    });

    test('per-class multipliers are read from the profile', () {
      const p = TravelProfile(
        speedMultiplier: 1.0,
        speedMultiplierByClass: {'primary': 1.4},
      );
      expect(p.speedOn('primary', 50), closeTo(70, 1e-9));
      expect(p.speedOn('residential', 20), 20);
      expect(p.isCar, isFalse);
    });

    test('a profile that closes a road class re-routes around it', () {
      final e = build(
        users: const {
          'commuter': UserClassParams(z: 0, lambda: 0.3, profile: 'noprimary'),
        },
        profiles: const {
          'noprimary': TravelProfile(id: 'noprimary', forbidden: {'primary'}),
        },
      );
      expect(usesRing(plan(e, 'commuter', (0, 0), (4, 4))), isFalse);
    });

    test('a node nobody in that mode can use is outside coverage, not a crash', () {
      final e = build(
        users: const {
          'commuter': UserClassParams(z: 0, lambda: 0.3, profile: 'ghost'),
        },
        profiles: const {
          'ghost': TravelProfile(id: 'ghost', forbidden: {'primary', 'residential'}),
        },
      );
      final o = e.route(
        fromLat: _lat(0),
        fromLon: _lon(0),
        toLat: _lat(4),
        toLon: _lon(4),
        userClass: 'commuter',
        at: at,
      );
      expect(o, isA<RouteNotFound>());
    });

    test('a walker is not shown a car time (the defect this fixes)', () {
      final walk = plan(engine, 'pedestrian', (0, 0), (5, 5));
      final kmh =
          walk.trace.chosen.distanceMeters / walk.trace.chosen.durationSeconds * 3.6;
      expect(kmh, lessThan(6));
    });
  });
}
