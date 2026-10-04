// ADR-011: "A shorter form of the same sentence repeats on any card whose
// `confidence_band` is `low` or `stale`." This asserts the repeat
// disclaimer renders for exactly those two bands and not the other two.

import 'package:citypulse_app/src/disclaimer/disclaimer_text.dart';
import 'package:citypulse_app/src/ui/widgets/explanation_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_router/pulse_router.dart';

import 'fixtures/trace_fixtures.dart';

void main() {
  for (final band in ConfidenceBand.values) {
    final shouldShow =
        band == ConfidenceBand.low || band == ConfidenceBand.stale;

    testWidgets('ExplanationCard for ${band.wireValue} confidence '
        '${shouldShow ? "shows" : "does not show"} the repeat disclaimer', (
      tester,
    ) async {
      final fixture = fixturesByBand[band]!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExplanationCard(
              explanation: fixture.explanation,
              confidenceBand: band,
            ),
          ),
        ),
      );

      expect(find.text(fixture.explanation.text), findsOneWidget);
      expect(
        find.byKey(const Key('repeat-disclaimer')),
        shouldShow ? findsOneWidget : findsNothing,
      );
      if (shouldShow) {
        expect(find.text(kRepeatDisclaimer), findsOneWidget);
      }
    });
  }
}
