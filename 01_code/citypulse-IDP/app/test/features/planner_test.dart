import 'package:citypulse_app/src/core/settings.dart';
import 'package:citypulse_app/src/domain/models.dart';
import 'package:citypulse_app/src/features/map/route_controller.dart';
import 'package:citypulse_app/src/platform/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/harness.dart';

const _a = Place(name: 'A Road', point: (lat: 13.04, lon: 80.23));
const _b = Place(name: 'B Road', point: (lat: 12.98, lon: 80.22));

Future<ProviderContainer> _container(FakeBackend backend) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      routingBackendProvider.overrideWithValue(backend),
      clockProvider.overrideWithValue(() => kTestNow),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('setting both ends plans a route; one end alone does not', () async {
    final backend = FakeBackend();
    final c = await _container(backend);
    final planner = c.read(plannerProvider.notifier);

    planner.setOrigin(_a);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(plannerProvider).status, PlanStatus.idle);
    expect(backend.routeCalls, isEmpty);

    planner.setDestination(_b);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final state = c.read(plannerProvider);
    expect(state.status, PlanStatus.done);
    expect(state.route, isNotNull);
    expect(backend.routeCalls.single.from, _a.point);
    expect(backend.routeCalls.single.to, _b.point);
    expect(backend.routeCalls.single.travel, TravelType.commuter);
  });

  test('changing the travel type re-plans with the new type', () async {
    final backend = FakeBackend();
    final c = await _container(backend);
    c.read(plannerProvider.notifier)
      ..setOrigin(_a)
      ..setDestination(_b);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await c.read(settingsProvider.notifier).setTravel(TravelType.pedestrian);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(backend.routeCalls.map((x) => x.travel), [
      TravelType.commuter,
      TravelType.pedestrian,
    ]);
  });

  test('each of the four modes is its own query, in order, with its own wire name',
      () async {
    final backend = FakeBackend();
    final c = await _container(backend);
    c.read(plannerProvider.notifier)
      ..setOrigin(_a)
      ..setDestination(_b);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    for (final mode in [
      TravelType.cyclist,
      TravelType.pedestrian,
      TravelType.emergency,
    ]) {
      await c.read(settingsProvider.notifier).setTravel(mode);
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(backend.routeCalls.map((x) => x.travel.wire), [
      'commuter',
      'cyclist',
      'pedestrian',
      'emergency',
    ]);
    expect(TravelType.fromWire('cyclist'), TravelType.cyclist);
    expect(TravelType.fromWire('hoverboard'), TravelType.commuter);
  });

  test('a routing failure is kept as a typed reason', () async {
    final backend = FakeBackend()
      ..routeError = const RoutingException(RoutingFailure.destinationOutside);
    final c = await _container(backend);
    c.read(plannerProvider.notifier)
      ..setOrigin(_a)
      ..setDestination(_b);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final state = c.read(plannerProvider);
    expect(state.status, PlanStatus.failed);
    expect(state.failure, RoutingFailure.destinationOutside);
    expect(state.route, isNull);
  });

  test('a slow, superseded answer never overwrites a newer one', () async {
    final backend = FakeBackend()
      ..routeDelay = const Duration(milliseconds: 80);
    final c = await _container(backend);
    final planner = c.read(plannerProvider.notifier);
    planner
      ..setOrigin(_a)
      ..setDestination(_b); // request 1 in flight
    await Future<void>.delayed(const Duration(milliseconds: 20));
    backend.routeResult = sampleRoute(withAlternative: false);
    backend.routeDelay = Duration.zero;
    planner.setDestination(
      const Place(name: 'C Road', point: (lat: 13, lon: 80.2)),
    ); // request 2
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final state = c.read(plannerProvider);
    expect(state.destination?.name, 'C Road');
    expect(
      state.route!.detours,
      isFalse,
      reason: 'the second request\'s answer won',
    );
  });

  test('swap exchanges the ends and re-plans; clear forgets everything and '
      'drops an in-flight answer', () async {
    final backend = FakeBackend();
    final c = await _container(backend);
    final planner = c.read(plannerProvider.notifier)
      ..setOrigin(_a)
      ..setDestination(_b);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    planner.swap();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(c.read(plannerProvider).origin, _b);
    expect(c.read(plannerProvider).destination, _a);
    expect(backend.routeCalls.last.from, _b.point);

    backend.routeDelay = const Duration(milliseconds: 60);
    planner.plan();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    planner.clear();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final state = c.read(plannerProvider);
    expect(state.origin, isNull);
    expect(state.route, isNull);
    expect(state.status, PlanStatus.idle);
  });

  test('Place equality is by name and position', () {
    expect(
      const Place(name: 'x', point: (lat: 1, lon: 2)),
      const Place(name: 'x', point: (lat: 1, lon: 2)),
    );
    expect(
      const Place(name: 'x', point: (lat: 1, lon: 2)) ==
          const Place(name: 'x', point: (lat: 1, lon: 3)),
      isFalse,
    );
    expect(Place.dropped((lat: 1, lon: 2)).name, 'Dropped pin');
  });

  test('RouteView reports free-flow minutes and extra minutes over the '
      'fastest route (never the penalised cost)', () {
    final v = sampleRoute();
    expect(v.travelMinutes, closeTo(1023 / 60, 1e-9));
    expect(v.extraMinutes, closeTo((1023 - 907) / 60, 1e-9));
    expect(sampleRoute(withAlternative: false).extraMinutes, 0);
  });
}
