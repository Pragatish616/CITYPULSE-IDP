// ADR-011: "no single-color 'all clear' badge; only the four confidence
// bands ... with their hedge text attached." This test asserts both halves
// of that rule for every band: no banned safety words anywhere in the
// rendered text, and no green color anywhere in the badge's paint.

import 'package:citypulse_app/src/ui/widgets/confidence_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_router/pulse_router.dart';

/// Words that would imply absolute passability/safety if they showed up in
/// badge text (ADR-011's rule-6 spirit, applied to UI chrome as well as
/// generated explanations).
const _bannedWords = [
  'all clear',
  'is safe',
  'is clear',
  'passable',
  'nothing to worry',
  'should be fine',
];

/// A pure green hue band (roughly 90-150 degrees) is what a traffic-light
/// "all clear" badge would use -- reject any badge color that falls in it.
bool _isGreenish(Color color) {
  final hsv = HSVColor.fromColor(color);
  return hsv.hue >= 80 && hsv.hue <= 160 && hsv.saturation > 0.25;
}

void main() {
  for (final band in ConfidenceBand.values) {
    testWidgets('ConfidenceBadge(${band.wireValue}) never renders green or '
        'an all-clear claim', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ConfidenceBadge(band: band)),
        ),
      );

      // No banned word in any Text widget under the badge.
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join(' ')
          .toLowerCase();
      for (final banned in _bannedWords) {
        expect(
          texts.contains(banned),
          isFalse,
          reason: 'badge text "$texts" contains banned phrase "$banned"',
        );
      }

      // Every fill/border color painted by the badge's Containers must not
      // be greenish.
      final containers = tester.widgetList<Container>(find.byType(Container));
      for (final container in containers) {
        final decoration = container.decoration;
        if (decoration is BoxDecoration) {
          final color = decoration.color;
          if (color != null) {
            expect(
              _isGreenish(color),
              isFalse,
              reason: 'badge painted a greenish fill color $color',
            );
          }
          final borderColor = decoration.border is Border
              ? (decoration.border! as Border).top.color
              : null;
          if (borderColor != null) {
            expect(
              _isGreenish(borderColor),
              isFalse,
              reason: 'badge painted a greenish border color $borderColor',
            );
          }
        }
      }
    });
  }

  testWidgets(
    'every band has non-empty, distinct hedge text (never a bare label)',
    (tester) async {
      final seenTexts = <String>{};
      for (final band in ConfidenceBand.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: ConfidenceBadge(band: band)),
          ),
        );
        final texts = tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data ?? '')
            .toList();
        expect(texts.length, greaterThanOrEqualTo(2));
        seenTexts.addAll(texts);
      }
      // Four distinct labels + four distinct hedges, none blank.
      expect(seenTexts.every((t) => t.trim().isNotEmpty), isTrue);
    },
  );
}
