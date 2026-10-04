// Widget tests for the main screen, driven through the real router, theme and
// providers with a fake back end and a fake map.
import 'package:citypulse_app/src/core/settings.dart';
import 'package:citypulse_app/src/core/strings.dart';
import 'package:citypulse_app/src/domain/models.dart';
import 'package:citypulse_app/src/features/map/map_surface.dart';
import 'package:citypulse_app/src/features/map/route_controller.dart';
import 'package:citypulse_app/src/platform/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pulse_explain/pulse_explain.dart';
import 'package:pulse_router/pulse_router.dart';

import '../helpers/harness.dart';

const _phone = Size(420, 900);
const _desktop = Size(1200, 800);

Future<void> _typeAndPick(
  WidgetTester tester,
  String field,
  String query,
) async {
  await tester.tap(find.byKey(Key('place-field-$field')));
  await tester.pump();
  await tester.enterText(find.byKey(Key('place-field-$field')), query);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('suggestion-$field-0')));
  await tester.pumpAndSettle();
}

void main() {
  group('layout', () {
    testWidgets('a phone gets a bottom navigation bar and no side rail', (
      tester,
    ) async {
      await AppHarness().pump(tester, size: _phone);
      expect(find.byKey(const Key('nav-bar')), findsOneWidget);
      expect(find.byKey(const Key('nav-rail')), findsNothing);
      expect(find.text('Where to?'), findsOneWidget);
    });

    testWidgets('a desktop browser gets a side rail and a side panel', (
      tester,
    ) async {
      await AppHarness().pump(tester, size: _desktop);
      expect(find.byKey(const Key('nav-rail')), findsOneWidget);
      expect(find.byKey(const Key('nav-bar')), findsNothing);
      expect(find.byKey(const Key('fake-map')), findsOneWidget);
    });
  });

  group('the disclaimer gate (ADR-011)', () {
    testWidgets('blocks the whole app until acknowledged, then lets it '
        'through', (tester) async {
      await AppHarness(disclaimerAccepted: false).pump(tester, size: _phone);
      expect(
        find.byKey(const Key('first-use-disclaimer-text')),
        findsOneWidget,
      );
      expect(find.text('Where to?'), findsNothing);
      await tester.tap(find.byKey(const Key('first-use-disclaimer-accept')));
      await tester.pumpAndSettle();
      expect(find.text('Where to?'), findsOneWidget);
    });
  });

  group('planning a route', () {
    testWidgets('search both ends, get a route: time, distance, honest '
        'explanation, badge, and the map is told to draw it', (tester) async {
      final h = AppHarness();
      await h.pump(tester, size: _desktop);
      await _typeAndPick(tester, 'origin', 'usman');
      await _typeAndPick(tester, 'destination', 'velachery');
      await tester.pumpAndSettle();

      expect(h.backend.routeCalls, hasLength(1));
      expect(find.byKey(const Key('route-minutes')), findsOneWidget);
      expect(
        find.text('17 min'),
        findsOneWidget,
        reason: '1023 s free-flow, not the penalised 1147 s',
      );
      expect(find.text('8.4 km'), findsOneWidget);
      expect(find.text('2 min longer than the fastest route'), findsOneWidget);
      // The advice card (ADR-021) carries the evidence level that the confidence badge used to.
      expect(find.byKey(const Key('advice-evidence')), findsOneWidget);
      expect(find.text('Some evidence'), findsOneWidget);
      expect(find.byKey(const Key('advice-hedge')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('explanation-text'))).data,
        allOf(
          contains('Route A is 2 minutes slower than Route B.'),
          contains(
            'It avoids a stretch of Kotturpuram Bridge approach where flooding',
          ),
        ),
      );
      expect(find.byKey(const Key('route-computed-on')), findsOneWidget);

      // The map was given the route, both markers and the avoided hazard.
      expect(h.map.path, hasLength(2));
      expect(h.map.fastest, isNull, reason: 'fastest route hidden until asked');
      expect(h.map.markers.map((m) => m.kind).toSet(), {
        MarkerKind.origin,
        MarkerKind.destination,
        MarkerKind.avoided,
      });
      expect(h.map.fits, isNotEmpty);
    });

    testWidgets('the fastest route can be shown and hidden', (tester) async {
      final h = AppHarness();
      await h.pump(tester, size: _desktop);
      await _typeAndPick(tester, 'origin', 'usman');
      await _typeAndPick(tester, 'destination', 'velachery');
      await tester.tap(find.byKey(const Key('toggle-fastest')));
      await tester.pumpAndSettle();
      expect(h.map.fastest, isNotNull);
      await tester.tap(find.byKey(const Key('toggle-fastest')));
      await tester.pumpAndSettle();
      expect(h.map.fastest, isNull);
    });

    testWidgets('the explanation comes from the verified template: it never '
        'tells the traveller a road is safe', (tester) async {
      final h = AppHarness(
        backend: FakeBackend(route: sampleRoute(band: ConfidenceBand.low)),
      );
      await h.pump(tester, size: _desktop);
      await _typeAndPick(tester, 'origin', 'usman');
      await _typeAndPick(tester, 'destination', 'velachery');
      final text = tester
          .widget<Text>(find.byKey(const Key('explanation-text')))
          .data!;
      expect(verify(text, h.backend.routeResult.trace).passed, isTrue);
      expect(text.toLowerCase(), isNot(contains('safe to')));
      // Low confidence repeats the disclaimer (ADR-011).
      expect(find.byKey(const Key('repeat-disclaimer')), findsOneWidget);
    });

    testWidgets('data gaps are listed as "no data", never as clear', (
      tester,
    ) async {
      final backend = FakeBackend(
        route: sampleRoute(
          dataGaps: const [
            DataGap(
              corridor: 'Velachery Main Rd',
              reason: 'no_observations_in_window',
            ),
          ],
        ),
      );
      final h = AppHarness(backend: backend);
      await h.pump(tester, size: _desktop);
      await _typeAndPick(tester, 'origin', 'usman');
      await _typeAndPick(tester, 'destination', 'velachery');
      expect(find.byKey(const Key('data-gaps-panel')), findsOneWidget);
      expect(
        find.textContaining('No recent hazard data for 1 corridor'),
        findsOneWidget,
      );
    });

    testWidgets('a failure is explained in plain words with a retry that '
        'works', (tester) async {
      final backend = FakeBackend()
        ..routeError = const RoutingException(RoutingFailure.network);
      final h = AppHarness(backend: backend);
      await h.pump(tester, size: _desktop);
      await _typeAndPick(tester, 'origin', 'usman');
      await _typeAndPick(tester, 'destination', 'velachery');
      expect(find.byKey(const Key('plan-error')), findsOneWidget);
      expect(
        find.textContaining('Could not reach the routing service'),
        findsOneWidget,
      );

      backend.routeError = null;
      await tester.tap(find.byKey(const Key('retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('route-minutes')), findsOneWidget);
    });

    testWidgets('outside-coverage failures say which end is the problem', (
      tester,
    ) async {
      final backend = FakeBackend()
        ..routeError = const RoutingException(RoutingFailure.originOutside);
      final h = AppHarness(backend: backend);
      await h.pump(tester, size: _desktop);
      await _typeAndPick(tester, 'origin', 'usman');
      await _typeAndPick(tester, 'destination', 'velachery');
      expect(find.textContaining('start point is outside'), findsOneWidget);
    });

    testWidgets('swap and clear', (tester) async {
      final h = AppHarness();
      await h.pump(tester, size: _desktop);
      await _typeAndPick(tester, 'origin', 'usman');
      await _typeAndPick(tester, 'destination', 'velachery');
      await tester.tap(find.byKey(const Key('swap')));
      await tester.pumpAndSettle();
      expect(h.backend.routeCalls, hasLength(2));
      expect(h.backend.routeCalls.last.from.lat, closeTo(12.98, 1e-9));

      await tester.tap(find.byKey(const Key('clear')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('route-minutes')), findsNothing);
      expect(h.map.path, isNull);
      expect(h.map.markers, isEmpty);
    });

    testWidgets('"use map centre" drops a pin at the middle of the map', (
      tester,
    ) async {
      final h = AppHarness();
      await h.pump(tester, size: _desktop);
      await tester.tap(find.byKey(const Key('use-centre-origin')));
      await tester.pumpAndSettle();
      expect(h.container.read(plannerProvider).origin?.point, h.map.centre);
      expect(h.map.markers.single.kind, MarkerKind.origin);
    });

    testWidgets('on a phone the result is a sheet over the map', (
      tester,
    ) async {
      final h = AppHarness();
      await h.pump(tester, size: _phone);
      await _typeAndPick(tester, 'origin', 'usman');
      await _typeAndPick(tester, 'destination', 'velachery');
      expect(find.byKey(const Key('result-sheet')), findsOneWidget);
      expect(find.byKey(const Key('route-minutes')), findsOneWidget);
    });

    testWidgets('on a phone the report and layers buttons stay visible above '
        'the result sheet instead of hiding under it', (tester) async {
      final h = AppHarness();
      await h.pump(tester, size: _phone);
      // Before a route: bottom-right.
      final before = tester.getRect(find.byKey(const Key('report-button')));
      await _typeAndPick(tester, 'origin', 'usman');
      await _typeAndPick(tester, 'destination', 'velachery');
      final sheet = tester.getRect(find.byKey(const Key('result-sheet')));
      final after = tester.getRect(find.byKey(const Key('report-button')));
      expect(
        after.bottom,
        lessThanOrEqualTo(sheet.top + 1),
        reason: 'button must not be covered by the sheet',
      );
      expect(after.top, lessThan(before.top), reason: 'it moved up');
      // And it still works.
      await tester.tap(find.byKey(const Key('report-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('report-submit')), findsOneWidget);
    });

    testWidgets('a shared link pre-fills both ends and plans', (tester) async {
      final h = AppHarness();
      await h.pump(tester, size: _desktop);
      h.container.read(plannerProvider.notifier)
        ..setOrigin(Place.dropped((lat: 13.04, lon: 80.23)))
        ..setDestination(Place.dropped((lat: 12.98, lon: 80.22)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('route-minutes')), findsOneWidget);
    });
  });

  group('the flood-event banner (F-09)', () {
    for (final (state, key, words) in [
      (EventState.dry, 'event-banner-dry', 'hazard map is not applied'),
      (EventState.watch, 'event-banner-watch', 'Flood watch'),
      (EventState.active, 'event-banner-active', 'Flood event'),
    ]) {
      testWidgets('${state.name}: says in plain words whether the hazard map '
          'is shaping routes', (tester) async {
        final h = AppHarness(backend: FakeBackend(state: state));
        await h.pump(tester, size: _desktop);
        expect(find.byKey(Key(key)), findsOneWidget);
        expect(find.textContaining(words), findsOneWidget);
      });
    }
  });

  group('a region without a flood-hazard layer (ADR-020)', () {
    testWidgets('shows no flood-event banner, whatever the server says', (tester) async {
      final h = AppHarness(
        city: noHazardCity(),
        backend: FakeBackend(state: EventState.active),
      );
      await h.pump(tester, size: _desktop);
      expect(find.byKey(const Key('event-banner-active')), findsNothing);
      expect(find.textContaining('Flood event'), findsNothing);
    });

    testWidgets('a route there says no flood data was used, instead of a confidence badge',
        (tester) async {
      final h = AppHarness(city: noHazardCity());
      await h.pump(tester, size: _desktop);
      h.container.read(plannerProvider.notifier)
        ..setOrigin(Place.dropped((lat: 13.04, lon: 80.23)))
        ..setDestination(Place.dropped((lat: 12.98, lon: 80.22)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('route-minutes')), findsOneWidget);
      expect(find.byKey(const Key('no-hazard-note')), findsOneWidget);
      expect(find.textContaining('No flood-hazard layer'), findsWidgets);
      expect(find.byKey(const Key('advice-verdict')), findsNothing);
    });
  });

  group('a region with a detailed city inside it (ADR-022)', () {
    Future<AppHarness> planIn(
      WidgetTester tester,
      bool hazardLayer, {
      EventState state = EventState.active,
    }) async {
      final h = AppHarness(
        city: noHazardCity(),
        detailCities: [testCity()],
        backend: FakeBackend(
          state: state,
          route: sampleRoute(hazardLayer: hazardLayer),
        ),
      );
      await h.pump(tester, size: _desktop);
      h.container.read(plannerProvider.notifier)
        ..setOrigin(Place.dropped((lat: 13.04, lon: 80.23)))
        ..setDestination(Place.dropped((lat: 12.98, lon: 80.22)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('route-minutes')), findsOneWidget);
      return h;
    }

    testWidgets('a route inside the detailed city gets the advice card', (tester) async {
      await planIn(tester, true);
      expect(find.byKey(const Key('advice-verdict')), findsOneWidget);
      expect(find.byKey(const Key('no-hazard-note')), findsNothing);
    });

    testWidgets('a route that leaves it shows the best route and no advice', (tester) async {
      await planIn(tester, false);
      expect(find.byKey(const Key('advice-verdict')), findsNothing);
      expect(find.byKey(const Key('no-hazard-note')), findsOneWidget);
      expect(find.byKey(const Key('route-minutes')), findsOneWidget);
    });

    testWidgets('the flood banner names the city it covers', (tester) async {
      await planIn(tester, true);
      expect(find.byKey(const Key('event-banner-active')), findsOneWidget);
      expect(find.textContaining('Chennai · Flood event'), findsOneWidget);
    });
  });

  group('layers', () {
    testWidgets('the hazard overlay is sent to the map and can be turned '
        'off and on', (tester) async {
      final h = AppHarness();
      await h.pump(tester, size: _desktop);
      expect(h.map.risk, contains('FeatureCollection'));

      await tester.tap(find.byKey(const Key('layers-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('switch-hazard')));
      await tester.pumpAndSettle();
      expect(h.map.risk, isNull);
      expect(h.container.read(settingsProvider).showHazard, isFalse);

      await tester.tap(find.byKey(const Key('switch-hazard')));
      await tester.pumpAndSettle();
      expect(h.map.risk, contains('FeatureCollection'));
    });

    testWidgets('watchlist candidates are off by default, labelled '
        'unverified, and drawn when switched on', (tester) async {
      final h = AppHarness();
      await h.pump(tester, size: _desktop);
      expect(h.map.watchlist, isNull);
      await tester.tap(find.byKey(const Key('layers-button')));
      await tester.pumpAndSettle();
      expect(find.textContaining('unverified'), findsWidgets);
      await tester.tap(find.byKey(const Key('switch-watchlist')));
      await tester.pumpAndSettle();
      expect(h.map.watchlist, kWatchlistFixture);
    });

    testWidgets('the legend explains the dashed/solid encoding (colour is '
        'never the only signal)', (tester) async {
      await AppHarness().pump(tester, size: _desktop);
      await tester.tap(find.byKey(const Key('layers-button')));
      await tester.pumpAndSettle();
      expect(find.text('Hazard map only, no report (dashed)'), findsOneWidget);
      expect(find.text('A report exists (solid)'), findsOneWidget);
      expect(find.text('Hazard this route avoids'), findsOneWidget);
    });
  });

  group('the hazard overlay loads by visible area (ADR-020)', () {
    Future<void> settle(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
    }

    GeoBounds box(double lat, double lon, double size) =>
        (minLat: lat, minLon: lon, maxLat: lat + size, maxLon: lon + size);

    testWidgets('the first request is for the area in view plus a margin, never the whole map',
        (tester) async {
      final h = AppHarness();
      await h.pump(tester, size: _desktop);
      await settle(tester);
      expect(h.backend.riskRequests, hasLength(1));
      final asked = h.backend.riskRequests.single!;
      final seen = h.map.currentView.bounds;
      // Covers the view with room to pan, and is not wildly bigger than it.
      expect(asked.minLat, lessThanOrEqualTo(seen.minLat));
      expect(asked.maxLon, greaterThanOrEqualTo(seen.maxLon));
      expect(asked.maxLat - asked.minLat, lessThan((seen.maxLat - seen.minLat) * 2.5));
      expect(h.map.risk, isNotNull);
    });

    testWidgets('panning inside the fetched area asks for nothing; leaving it asks once more',
        (tester) async {
      final h = AppHarness();
      await h.pump(tester, size: _desktop);
      await settle(tester);
      expect(h.backend.riskRequests, hasLength(1));

      // A small pan: still inside the margin.
      h.map.currentView = (bounds: box(13.02, 80.22, 0.10), zoom: 12.0);
      h.mapCallbacks.onCameraIdle?.call();
      await settle(tester);
      expect(h.backend.riskRequests, hasLength(1), reason: 'covered by what is on the map');

      // A long pan: out of it.
      h.map.currentView = (bounds: box(13.40, 80.60, 0.10), zoom: 12.0);
      h.mapCallbacks.onCameraIdle?.call();
      await settle(tester);
      expect(h.backend.riskRequests, hasLength(2));
      expect(h.backend.riskRequests.last!.minLat, greaterThan(13.2));
    });

    testWidgets('a burst of camera events costs one request (debounce)', (tester) async {
      final h = AppHarness();
      await h.pump(tester, size: _desktop);
      await settle(tester);
      for (var i = 0; i < 20; i++) {
        h.map.currentView = (bounds: box(14.0 + i * 0.3, 81.0, 0.10), zoom: 12.0);
        h.mapCallbacks.onCameraIdle?.call();
        await tester.pump(const Duration(milliseconds: 20));
      }
      await settle(tester);
      expect(h.backend.riskRequests, hasLength(2), reason: 'the first, and one for the last stop');
    });

    testWidgets('zoomed out past the limit the overlay is hidden and nothing is fetched',
        (tester) async {
      final h = AppHarness();
      await h.pump(tester, size: _desktop);
      await settle(tester);
      expect(h.map.risk, isNotNull);
      final before = h.backend.riskRequests.length;

      h.map.currentView = (bounds: box(9.0, 77.0, 4.0), zoom: kRiskMinZoom - 1);
      h.mapCallbacks.onCameraIdle?.call();
      await settle(tester);
      expect(h.map.risk, isNull);
      expect(h.backend.riskRequests, hasLength(before));
    });

    testWidgets('going back to an area already fetched is served from memory',
        (tester) async {
      final h = AppHarness();
      await h.pump(tester, size: _desktop);
      await settle(tester);
      final first = h.map.currentView;

      h.map.currentView = (bounds: box(13.40, 80.60, 0.10), zoom: 12.0);
      h.mapCallbacks.onCameraIdle?.call();
      await settle(tester);
      expect(h.backend.riskRequests, hasLength(2));

      h.map.currentView = first;
      h.mapCallbacks.onCameraIdle?.call();
      await settle(tester);
      expect(h.backend.riskRequests, hasLength(2), reason: 'cached');
      expect(h.map.risk, isNotNull);
    });

    testWidgets('a new report makes the area in view be fetched again', (tester) async {
      final h = AppHarness();
      await h.pump(tester, size: _desktop);
      await settle(tester);
      expect(h.backend.riskRequests, hasLength(1));
      h.container.read(riskRevisionProvider.notifier).bump();
      await settle(tester);
      expect(h.backend.riskRequests, hasLength(2));
    });

    testWidgets('turning the layer off hides it without a request', (tester) async {
      final h = AppHarness();
      await h.pump(tester, size: _desktop);
      await settle(tester);
      final before = h.backend.riskRequests.length;
      await h.container.read(settingsProvider.notifier).setShowHazard(value: false);
      await settle(tester);
      expect(h.map.risk, isNull);
      expect(h.backend.riskRequests, hasLength(before));
    });
  });

  group('taps on the map', () {
    testWidgets('a tap offers start, destination and report', (tester) async {
      final h = AppHarness();
      await h.pump(tester, size: _desktop);
      h.mapCallbacks.onTap((lat: 13.03, lon: 80.21));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tap-set-start')), findsOneWidget);
      await tester.tap(find.byKey(const Key('tap-set-destination')));
      await tester.pumpAndSettle();
      expect(h.container.read(plannerProvider).destination?.point, (
        lat: 13.03,
        lon: 80.21,
      ));
    });
  });

  group('reporting', () {
    testWidgets('three taps: kind, depth, send -- the report reaches the '
        'server and counts locally at once', (tester) async {
      late http.Request posted;
      final h = AppHarness(
        ingest: MockClient((req) async {
          posted = req;
          return http.Response('{"inserted":true}', 201);
        }),
      );
      await h.pump(tester, size: _desktop);
      await tester.tap(find.byKey(const Key('report-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('report-privacy')), findsOneWidget);
      expect(find.byKey(const Key('report-location')), findsOneWidget);

      await tester.tap(find.byKey(const Key('kind-flooded')));
      await tester.tap(find.byKey(const Key('depth-knee')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('report-submit')));
      await tester.pumpAndSettle();

      expect(posted.url.path, '/observations');
      expect(posted.body, contains('"depth_mm":450'));
      expect(h.backend.observations, hasLength(1));
      expect(find.text('Report sent. Thank you.'), findsOneWidget);
      expect(
        find.byKey(const Key('report-submit')),
        findsNothing,
        reason: 'sheet closed',
      );
    });

    testWidgets('offline, the report is saved and the traveller is told '
        'plainly', (tester) async {
      final h = AppHarness(
        ingest: MockClient((_) async => throw http.ClientException('offline')),
      );
      await h.pump(tester, size: _desktop);
      await tester.tap(find.byKey(const Key('report-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('report-submit')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Saved on this device'), findsOneWidget);
      expect(h.backend.observations, hasLength(1));
    });

    testWidgets('a rejected report keeps the sheet open and says so', (
      tester,
    ) async {
      final h = AppHarness(
        ingest: MockClient((_) async => http.Response('{"detail":"bad"}', 422)),
      );
      await h.pump(tester, size: _desktop);
      await tester.tap(find.byKey(const Key('report-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('report-submit')));
      await tester.pumpAndSettle();
      expect(find.textContaining('not accepted'), findsOneWidget);
      expect(find.byKey(const Key('report-submit')), findsOneWidget);
      expect(h.backend.observations, isEmpty);
    });

    testWidgets('"water has cleared" hides the depth question', (tester) async {
      await AppHarness().pump(tester, size: _desktop);
      await tester.tap(find.byKey(const Key('report-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('depth-knee')), findsOneWidget);
      await tester.tap(find.byKey(const Key('kind-cleared')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('depth-knee')), findsNothing);
    });
  });

  group('help and settings', () {
    testWidgets('help always carries the verbatim disclaimer and the '
        'emergency number', (tester) async {
      await AppHarness().pump(tester, size: _desktop);
      await tester.tap(find.text('Help'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('help-emergency')), findsOneWidget);
      expect(find.text('In an emergency call 112.'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('help-disclaimer'))).data,
        contains('does not guarantee any road is safe'),
      );
    });

    testWidgets('the local control-room line belongs to Chennai and appears only '
        'for a city that has one; 112 is always there', (tester) async {
      await AppHarness().pump(tester, size: _desktop);
      await tester.tap(find.text('Help'));
      await tester.pumpAndSettle();
      expect(
        find.text('Greater Chennai Corporation control room: 1913'),
        findsOneWidget,
      );

      // A new test-only widget tree for a city with no checked local number.
      await tester.pumpWidget(const SizedBox());
      await AppHarness(city: noHazardCity()).pump(tester, size: _desktop);
      await tester.tap(find.text('Help'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('help-local-contact')), findsNothing);
      expect(find.textContaining('Chennai'), findsNothing);
      expect(find.text('In an emergency call 112.'), findsOneWidget);
      expect(find.textContaining('No flood-hazard layer'), findsOneWidget);
    });

    testWidgets('switching to Tamil re-labels the app and the choice is '
        'remembered', (tester) async {
      final h = AppHarness();
      await h.pump(tester, size: _desktop);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('தமிழ்'));
      await tester.pumpAndSettle();
      expect(find.text(tamilStrings[Msg.navMap]!), findsWidgets);
      expect(find.text(tamilStrings[Msg.settingsTitle]!), findsWidgets);
      expect(h.prefs.getString('settings.language'), 'ta');
    });

    testWidgets('compute location is a setting and states where routes are '
        'calculated', (tester) async {
      final h = AppHarness();
      await h.pump(tester, size: _desktop);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('On the server'));
      await tester.pumpAndSettle();
      expect(h.container.read(settingsProvider).compute, ComputeMode.server);
      expect(find.byKey(const Key('compute-site')), findsOneWidget);
    });

    testWidgets('resetting the anonymous install code makes a new one', (
      tester,
    ) async {
      final h = AppHarness();
      await h.pump(tester, size: _desktop);
      final before = InstallId.read(h.prefs);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reset-install-id')));
      await tester.pumpAndSettle();
      expect(InstallId.read(h.prefs), isNot(before));
      expect(find.text('A new anonymous code was created.'), findsOneWidget);
    });

    testWidgets('data sources and software licences are one tap away, and the '
        'data notice names the ODbL and the OpenStreetMap link', (tester) async {
      final h = AppHarness();
      await h.pump(tester, size: _desktop);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('software-licences')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('data-sources')));
      await tester.tap(find.byKey(const Key('data-sources')));
      await tester.pumpAndSettle();
      expect(find.textContaining('ODbL'), findsWidgets);
      expect(
        find.textContaining('https://www.openstreetmap.org/copyright'),
        findsOneWidget,
      );
      expect(find.textContaining('OpenCity'), findsOneWidget);
    });
  });
}
