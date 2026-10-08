// ADR-027 in the app: the flood-event banner also says what the satellite sees over the city, with the image's age, and a tap explains
// it. An unreadable answer shows nothing; an unknown is never shown as "no rain" (ADR-011).
import 'package:citypulse_app/src/domain/rain_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_router/pulse_router.dart';

import '../helpers/harness.dart';

const _desktop = Size(1200, 800);

RainStatus status({
  EventState state = EventState.dry,
  String mode = 'auto',
  String source = 'rain',
  double acc = 0,
  double peak = 0,
  String cls = 'none',
  int age = 320,
  bool stale = false,
  bool withRain = true,
}) => RainStatus(
  state: state,
  mode: mode,
  source: source,
  reason: 'x',
  rain: withRain
      ? RainReading(
          asOf: DateTime.utc(2026, 10, 5, 11, 30),
          dataAgeMinutes: age,
          stale: stale,
          accumulationMm: acc,
          peakRateMmH: peak,
          intensityClass: cls,
        )
      : null,
);

void main() {
  group('RainStatus.tryParse', () {
    Map<String, Object?> good() => {
      'event_state': 'dry',
      'mode': 'auto',
      'source': 'rain',
      'reason': 'because',
      'rain': {
        'as_of': '2026-10-05T11:30:00.000Z',
        'data_age_minutes': 320,
        'stale': false,
        'accumulation_3h_mm': 0.0,
        'peak_rate_mm_h': 0.0,
        'intensity_class_now': 'none',
      },
    };

    test('reads the router service answer', () {
      final s = RainStatus.tryParse(good())!;
      expect((s.state, s.mode, s.source), (EventState.dry, 'auto', 'rain'));
      expect(s.rain!.dataAgeMinutes, 320);
      expect(s.rain!.isWet, isFalse);
    });

    test(
      'an old service without rain fields still gives the state, with no rain',
      () {
        final s = RainStatus.tryParse({'event_state': 'active'})!;
        expect(s.state, EventState.active);
        expect(s.rain, isNull);
      },
    );

    test('anything unusable gives null, never a made-up reading', () {
      expect(RainStatus.tryParse(null), isNull);
      expect(RainStatus.tryParse('x'), isNull);
      expect(RainStatus.tryParse({'event_state': 'storm'}), isNull);
      final broken = good()
        ..['rain'] = {'as_of': 'nope', 'data_age_minutes': 1};
      expect(
        RainStatus.tryParse(broken)!.rain,
        isNull,
        reason: 'the state survives, the bad rain part is dropped',
      );
      final negative = good()
        ..['rain'] = {
          ...(good()['rain']! as Map<String, Object?>),
          'accumulation_3h_mm': -4,
        };
      expect(RainStatus.tryParse(negative)!.rain, isNull);
    });
  });

  group('the rain line on the banner', () {
    testWidgets('no rain in the last three hours says so, with the image age', (
      tester,
    ) async {
      await AppHarness(rainStatus: status()).pump(tester, size: _desktop);
      expect(find.byKey(const Key('rain-line')), findsOneWidget);
      expect(find.textContaining('none in the last 3 h'), findsOneWidget);
      expect(find.textContaining('image 5 h 20 min old'), findsOneWidget);
      expect(find.textContaining('Chennai'), findsWidgets);
    });

    testWidgets('heavy rain now says the class and the three-hour amount', (
      tester,
    ) async {
      await AppHarness(
        rainStatus: status(
          state: EventState.active,
          acc: 24.4,
          peak: 12.2,
          cls: 'heavy',
          age: 45,
        ),
      ).pump(tester, size: _desktop);
      expect(find.textContaining('heavy now'), findsOneWidget);
      expect(find.textContaining('24 mm in the last 3 h'), findsOneWidget);
      expect(find.textContaining('image 45 min old'), findsOneWidget);
    });

    testWidgets('rain earlier in the window but none now says exactly that', (
      tester,
    ) async {
      await AppHarness(rainStatus: status(acc: 3.2, peak: 4.0))
          .pump(tester, size: _desktop);
      expect(
        find.textContaining('none now · 3.2 mm earlier in the last 3 h'),
        findsOneWidget,
      );
    });

    testWidgets('stale data says it is out of date and shows no amount', (
      tester,
    ) async {
      await AppHarness(rainStatus: status(stale: true, age: 900))
          .pump(tester, size: _desktop);
      expect(find.textContaining('the data is out of date'), findsOneWidget);
      expect(find.textContaining('mm in the last 3 h'), findsNothing);
    });

    testWidgets(
      'an unreadable answer shows no rain line at all, not "no rain"',
      (tester) async {
        await AppHarness().pump(tester, size: _desktop);
        expect(find.byKey(const Key('rain-line')), findsNothing);
        expect(find.textContaining('none in the last 3 h'), findsNothing);
        expect(
          find.byKey(const Key('event-banner-active')),
          findsOneWidget,
          reason: 'the flood banner itself is unchanged',
        );
      },
    );

    testWidgets(
      'a service with a state but no rain reading shows no rain line',
      (tester) async {
        await AppHarness(
          rainStatus: status(withRain: false, source: 'fallback'),
        ).pump(tester, size: _desktop);
        expect(find.byKey(const Key('rain-line')), findsNothing);
      },
    );

    testWidgets('the Tamil interface shows the line in Tamil', (tester) async {
      final h = AppHarness(rainStatus: status());
      await h.pump(
        tester,
        size: _desktop,
        prefsValues: {'settings.language': 'ta'},
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('செயற்கைக்கோள் மழை'), findsOneWidget);
      expect(find.textContaining('none in the last'), findsNothing);
    });
  });

  group('tapping the banner', () {
    testWidgets(
      'opens a sheet with the numbers, where the state comes from, and the limits',
      (tester) async {
        await AppHarness(rainStatus: status(acc: 3.2, peak: 4.0))
            .pump(tester, size: _desktop);
        await tester.tap(find.byKey(const Key('event-banner-tap')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('rain-sheet')), findsOneWidget);
        expect(find.text('3.2 mm'), findsOneWidget);
        expect(find.text('4.0 mm/h'), findsOneWidget);
        expect(find.text('5 h 20 min'), findsOneWidget);
        expect(
          find.text('Set automatically from satellite rain.'),
          findsOneWidget,
        );
        expect(find.textContaining('Rain is not flooding'), findsOneWidget);
      },
    );

    for (final (source, words) in [
      ('manual', 'Set by an operator.'),
      ('fallback', 'default setting is used'),
      ('configured', 'Fixed by the service setting.'),
    ]) {
      testWidgets('says where the state comes from: $source', (tester) async {
        await AppHarness(
          rainStatus: status(source: source, withRain: source == 'manual'),
        ).pump(tester, size: _desktop);
        await tester.tap(find.byKey(const Key('event-banner-tap')));
        await tester.pumpAndSettle();
        expect(find.textContaining(words), findsOneWidget);
      });
    }

    testWidgets(
      'a state raised by the forecast says so, with the expected amount and its limits (ADR-029)',
      (tester) async {
        final s = RainStatus.tryParse({
          'event_state': 'watch',
          'mode': 'auto',
          'source': 'forecast',
          'reason': 'x',
          'forecast': {
            'trusted': true,
            'max_3h_area_mean_mm_next_12h': 9.25,
            'window_end': '2026-10-08T17:00:00.000Z',
            'level': 'watch',
          },
        })!;
        expect(s.forecast!.maxMm, 9.25);
        expect(s.forecast!.windowEnd, DateTime.utc(2026, 10, 8, 17));
        await AppHarness(rainStatus: s).pump(tester, size: _desktop);
        await tester.tap(find.byKey(const Key('event-banner-tap')));
        await tester.pumpAndSettle();
        expect(
          find.text(
            'Raised to flood watch by a rain forecast for the next 12 hours.',
          ),
          findsOneWidget,
        );
        expect(find.text('9.3 mm'), findsOneWidget);
        expect(find.byKey(const Key('forecast-caveat')), findsOneWidget);
        expect(find.textContaining('wrong either way'), findsOneWidget);
      },
    );

    testWidgets('a forecast the service does not trust shows no amount', (
      tester,
    ) async {
      final s = RainStatus.tryParse({
        'event_state': 'dry',
        'source': 'rain',
        'forecast': {'trusted': false, 'max_3h_area_mean_mm_next_12h': 12.0},
      })!;
      await AppHarness(rainStatus: s).pump(tester, size: _desktop);
      await tester.tap(find.byKey(const Key('event-banner-tap')));
      await tester.pumpAndSettle();
      expect(find.text('12.0 mm'), findsNothing);
      expect(find.byKey(const Key('forecast-caveat')), findsNothing);
    });

    test('a broken forecast part is dropped, not guessed', () {
      final s = RainStatus.tryParse({
        'event_state': 'dry',
        'forecast': {'trusted': 'yes', 'max_3h_area_mean_mm_next_12h': 3},
      })!;
      expect(s.forecast, isNull);
      final t = RainStatus.tryParse({
        'event_state': 'dry',
        'forecast': {'trusted': true, 'max_3h_area_mean_mm_next_12h': -1},
      })!;
      expect((t.forecast!.trusted, t.forecast!.maxMm), (true, null));
    });

    testWidgets('with no readable answer there is nothing to open', (
      tester,
    ) async {
      await AppHarness().pump(tester, size: _desktop);
      await tester.tap(find.byKey(const Key('event-banner-tap')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('rain-sheet')), findsNothing);
    });
  });
}
