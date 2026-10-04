import 'package:citypulse_app/src/core/strings.dart';
import 'package:citypulse_app/src/ui/widgets/advice_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_router/pulse_router.dart';

RouteFacts _facts(double p, {ConfidenceBand band = ConfidenceBand.high}) =>
    RouteFacts(
      worstEdgeP: p,
      hazardPenaltyRatio: p / 2,
      confidence: band,
      dataGapCount: 0,
      userClass: UserClass.commuter,
      eventState: EventState.active,
    );

Future<void> _show(WidgetTester tester, Advice a, AppLanguage lang) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AdviceCard(advice: a, strings: Strings(lang))),
      ),
    );

void main() {
  testWidgets('shows a verdict, a risk bar, the evidence and a hedge', (
    tester,
  ) async {
    await _show(tester, advise(_facts(0.9)), AppLanguage.en);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('advice-avoid')), findsOneWidget);
    expect(find.text('Avoid this route'), findsOneWidget);
    expect(find.text('High risk'), findsOneWidget);
    expect(find.text('Strong evidence'), findsOneWidget);
    expect(find.byKey(const Key('advice-risk-bar')), findsOneWidget);
    expect(find.byKey(const Key('advice-hedge')), findsOneWidget);
  });

  testWidgets(
    'the mildest verdict never says a road is safe, and shows no percentages',
    (tester) async {
      await _show(tester, advise(_facts(0)), AppLanguage.en);
      await tester.pumpAndSettle();
      expect(find.text('Proceed with care'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
      expect(
        find.textContaining(
          RegExp(r'safe|clear|go ahead', caseSensitive: false),
        ),
        findsNothing,
      );
      expect(find.textContaining('not a guarantee'), findsOneWidget);
    },
  );

  testWidgets('at most two reasons are listed', (tester) async {
    final facts = RouteFacts(
      worstEdgeP: 0.7,
      hazardPenaltyRatio: 0.3,
      confidence: ConfidenceBand.low,
      dataGapCount: 2,
      userClass: UserClass.commuter,
      eventState: EventState.dry,
      blockedAlternatives: 1,
    );
    await _show(tester, advise(facts), AppLanguage.en);
    await tester.pumpAndSettle();
    expect(find.textContaining('has high flood risk'), findsOneWidget);
    expect(
      find.textContaining('Faster routes through flooded streets'),
      findsOneWidget,
    );
    expect(find.textContaining('Little recent data'), findsNothing);
  });

  testWidgets('it speaks Tamil', (tester) async {
    await _show(tester, advise(_facts(0.4)), AppLanguage.ta);
    await tester.pumpAndSettle();
    expect(find.text('முடிந்தால் காத்திருக்கவும்'), findsOneWidget);
    expect(find.text('மிதமான ஆபத்து'), findsOneWidget);
  });

  testWidgets('the accessibility label carries verdict, risk and evidence', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _show(tester, advise(_facts(0.9)), AppLanguage.en);
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(
        RegExp(r'^Avoid this route\. High risk\. Strong evidence\. .*guarantee'),
      ),
      findsOneWidget,
    );
    handle.dispose();
  });
}
