// The question box inside the real screen (ADR-035): it appears under a planned route that has a hazard layer, answers
// from that route's trace, and is absent when the route has no hazard layer.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

const _desktop = Size(1200, 900);

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

Future<void> _plan(WidgetTester tester, AppHarness h) async {
  await h.pump(tester, size: _desktop);
  await _typeAndPick(tester, 'origin', 'usman');
  await _typeAndPick(tester, 'destination', 'velachery');
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'under a planned route: ask a question and read an answer from that route',
    (tester) async {
      final h = AppHarness();
      await _plan(tester, h);
      await tester.ensureVisible(find.byKey(const Key('ask-field')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('ask-field')),
        'Which streets were left out?',
      );
      await tester.tap(find.byKey(const Key('ask-send')));
      await tester.pumpAndSettle();
      final a = tester.widget<Text>(find.byKey(const Key('ask-answer'))).textSpan!.toPlainText();
      expect(a, contains('Kotturpuram Bridge approach'));
      expect(a, contains('3 minutes ago'));
    },
  );

  testWidgets(
    'a safety question in the real screen is refused with the risk shown',
    (tester) async {
      final h = AppHarness();
      await _plan(tester, h);
      await tester.ensureVisible(find.byKey(const Key('ask-field')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('ask-field')),
        'Is the Kotturpuram bridge passable now?',
      );
      await tester.tap(find.byKey(const Key('ask-send')));
      await tester.pumpAndSettle();
      final a = tester.widget<Text>(find.byKey(const Key('ask-answer'))).textSpan!.toPlainText();
      expect(a, contains('I cannot confirm the condition of any road'));
      expect(a, contains('flood risk'));
    },
  );

  testWidgets(
    'a route without a hazard layer has no question box (the answers are about flood data)',
    (tester) async {
      final h = AppHarness(
        backend: FakeBackend(route: sampleRoute(hazardLayer: false)),
      );
      await _plan(tester, h);
      expect(find.byKey(const Key('no-hazard-note')), findsOneWidget);
      expect(find.byKey(const Key('ask-box')), findsNothing);
    },
  );
}
