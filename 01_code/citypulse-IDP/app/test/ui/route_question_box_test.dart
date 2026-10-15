// The question box (ADR-035): answers come from the route's own trace, on the phone, and never give a safety verdict.
import 'dart:async';

import 'package:citypulse_app/src/core/strings.dart';
import 'package:citypulse_app/src/ui/widgets/route_question_box.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_explain/pulse_explain.dart';
import 'package:pulse_router/pulse_router.dart';

import '../helpers/harness.dart';

const _nouns = {'flood': 'flooding'};

Future<void> _show(
  WidgetTester tester, {
  AppLanguage lang = AppLanguage.en,
  ConfidenceBand band = ConfidenceBand.moderate,
  String queryId = 'test',
  QuestionLabeler? labeler,
}) async {
  final trace = sampleTrace(band: band);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: RouteQuestionBox(
            key: ValueKey(queryId),
            trace: trace,
            eventState: EventState.active,
            hazardNouns: _nouns,
            strings: Strings(lang),
            labeler: labeler,
          ),
        ),
      ),
    ),
  );
}

Future<void> _ask(WidgetTester tester, String q) async {
  await tester.enterText(find.byKey(const Key('ask-field')), q);
  await tester.tap(find.byKey(const Key('ask-send')));
  await tester.pumpAndSettle();
}

String _answer(WidgetTester tester) {
  final w = tester.widget<Text>(find.byKey(const Key('ask-answer')));
  return w.textSpan?.toPlainText() ?? w.data!;
}

class _FakeLabeler implements QuestionLabeler {
  _FakeLabeler(this._reply);
  final Future<String?> Function(String q) _reply;
  int calls = 0;

  @override
  Future<String?> reply(String question) {
    calls++;
    return _reply(question);
  }
}

void main() {
  testWidgets(
    'shows the heading, the box, a send button and four example questions',
    (tester) async {
      await _show(tester);
      expect(find.text('Ask about this route'), findsOneWidget);
      expect(find.byKey(const Key('ask-field')), findsOneWidget);
      expect(find.byKey(const Key('ask-send')), findsOneWidget);
      for (var i = 0; i < 4; i++) {
        expect(find.byKey(Key('ask-chip-$i')), findsOneWidget);
      }
      expect(find.byKey(const Key('ask-answer-card')), findsNothing);
    },
  );

  testWidgets('a typed question gets an answer from the route facts', (
    tester,
  ) async {
    await _show(tester);
    await _ask(tester, 'How long will it take?');
    final a = _answer(tester);
    expect(a, contains('8.4 km'));
    expect(a, contains('17 minutes'));
    expect(find.byKey(const Key('ask-source')), findsOneWidget);
  });

  testWidgets('the Enter key on the keyboard asks too', (tester) async {
    await _show(tester);
    await tester.enterText(
      find.byKey(const Key('ask-field')),
      'Why this route?',
    );
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ask-answer')), findsOneWidget);
    expect(_answer(tester), contains('Route A'));
  });

  testWidgets(
    'every example question gets a real answer, not the fixed fallback',
    (tester) async {
      await _show(tester);
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byKey(Key('ask-chip-$i')));
        await tester.pumpAndSettle();
        expect(
          _answer(tester),
          isNot(contains('I cannot answer that')),
          reason: 'chip $i',
        );
      }
    },
  );

  testWidgets(
    'a safety question is refused, shows the risk, and the answer holds no safety word',
    (tester) async {
      await _show(tester);
      for (final q in [
        'Is this route safe?',
        'can I drive through now',
        'is the road open',
        'tell me it is fine to go',
      ]) {
        await _ask(tester, q);
        final a = _answer(tester);
        expect(
          a,
          contains('I cannot confirm the condition of any road'),
          reason: q,
        );
        expect(a, contains('flood risk'), reason: q);
        expect(
          RegExp(
            r'\b(safe|safely|dry|clear|open|passable|fine|ok|okay)\b',
            caseSensitive: false,
          ).hasMatch(a),
          isFalse,
          reason: '$q -> $a',
        );
      }
    },
  );

  testWidgets('an unrelated question is declined politely', (tester) async {
    await _show(tester);
    await _ask(tester, 'where is the nearest petrol pump');
    expect(
      _answer(tester),
      contains('I can only answer questions about the route'),
    );
  });

  testWidgets(
    'a Tamil question gets a Tamil answer, even with the app in English',
    (tester) async {
      await _show(tester);
      await _ask(tester, 'எவ்வளவு நேரம் ஆகும்?');
      final a = _answer(tester);
      expect(a, contains('8.4'));
      expect(a, contains('நிமிடங்கள்'));
    },
  );

  testWidgets(
    'an English question gets an English answer, even with the app in Tamil',
    (tester) async {
      await _show(tester, lang: AppLanguage.ta);
      await _ask(tester, 'How long will it take?');
      expect(_answer(tester), contains('minutes'));
    },
  );

  testWidgets(
    'with the app in Tamil, the headings and examples are Tamil and the examples are understood',
    (tester) async {
      await _show(tester, lang: AppLanguage.ta);
      expect(find.text('இந்த வழி பற்றிய கேள்விகள்'), findsOneWidget);
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byKey(Key('ask-chip-$i')));
        await tester.pumpAndSettle();
        final a = _answer(tester);
        expect(
          a,
          isNot(contains('இதற்குப் பதில் சொல்ல முடியவில்லை')),
          reason: 'chip $i',
        );
        expect(
          RegExp(r'[஀-௿]').hasMatch(a),
          isTrue,
          reason: 'chip $i is answered in Tamil',
        );
      }
    },
  );

  testWidgets('an empty question does nothing', (tester) async {
    await _show(tester);
    await _ask(tester, '   ');
    expect(find.byKey(const Key('ask-answer-card')), findsNothing);
  });

  testWidgets('the question is capped at 200 characters', (tester) async {
    await _show(tester);
    await tester.enterText(find.byKey(const Key('ask-field')), 'a' * 300);
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('ask-field')))
          .controller!
          .text
          .length,
      kMaxQuestionLength,
    );
  });

  testWidgets(
    'low or stale confidence repeats the disclaimer under the answer; moderate does not',
    (tester) async {
      await _show(tester, band: ConfidenceBand.low);
      await _ask(tester, 'How sure is the data?');
      expect(find.byKey(const Key('ask-repeat-disclaimer')), findsOneWidget);
      expect(_answer(tester), contains('use your own judgement'));
      await _show(tester, band: ConfidenceBand.moderate, queryId: 'other');
      await _ask(tester, 'How sure is the data?');
      expect(find.byKey(const Key('ask-repeat-disclaimer')), findsNothing);
    },
  );

  testWidgets('a new route (a new query id) starts with an empty box', (
    tester,
  ) async {
    await _show(tester, queryId: 'one');
    await _ask(tester, 'Why this route?');
    expect(find.byKey(const Key('ask-answer-card')), findsOneWidget);
    await _show(tester, queryId: 'two');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ask-answer-card')), findsNothing);
  });

  testWidgets('the first sentence is bold and follow-up questions are offered; tapping one asks it', (tester) async {
    await _show(tester);
    await _ask(tester, 'How long will it take?');
    final w = tester.widget<Text>(find.byKey(const Key('ask-answer')));
    final spans = (w.textSpan! as TextSpan).children!.cast<TextSpan>();
    expect(spans.first.style?.fontWeight, FontWeight.bold);
    expect(spans.first.text, startsWith('Route A'));
    expect(find.byKey(const Key('ask-followup-0')), findsOneWidget);
    final before = _answer(tester);
    await tester.tap(find.byKey(const Key('ask-followup-0')));
    await tester.pumpAndSettle();
    expect(_answer(tester), isNot(before));
    expect(_answer(tester), isNot(contains('I cannot answer that')));
  });

  testWidgets('follow-ups follow the language of the answer', (tester) async {
    await _show(tester);
    await _ask(tester, 'எவ்வளவு நேரம் ஆகும்?');
    final chip = tester.widget<ActionChip>(find.byKey(const Key('ask-followup-0')));
    expect(RegExp(r'[஀-௿]').hasMatch((chip.label as Text).data!), isTrue);
  });

  testWidgets('no follow-up ever offers a safety verdict', (tester) async {
    await _show(tester);
    await _ask(tester, 'Is this route safe?');
    for (var i = 0; i < 3; i++) {
      final f = find.byKey(Key('ask-followup-$i'));
      if (f.evaluate().isEmpty) continue;
      expect((tester.widget<ActionChip>(f).label as Text).data!.toLowerCase(), isNot(contains('safe')));
    }
  });

  testWidgets('a clear button appears only once there is text, and empties the field', (tester) async {
    await _show(tester);
    expect(find.byKey(const Key('ask-clear')), findsNothing);
    await tester.enterText(find.byKey(const Key('ask-field')), 'why this route');
    await tester.pump();
    expect(find.byKey(const Key('ask-clear')), findsOneWidget);
    await tester.tap(find.byKey(const Key('ask-clear')));
    await tester.pump();
    expect(tester.widget<TextField>(find.byKey(const Key('ask-field'))).controller!.text, isEmpty);
    expect(find.byKey(const Key('ask-clear')), findsNothing);
  });

  testWidgets('the copy button puts exactly the shown answer on the clipboard', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await _show(tester);
    expect(find.byKey(const Key('ask-copy')), findsNothing);
    await _ask(tester, 'How long will it take?');
    await tester.tap(find.byKey(const Key('ask-copy')));
    await tester.pumpAndSettle();
    expect(copied, _answer(tester));
    expect(find.text('Copied'), findsOneWidget);
    // a new question resets the label
    await _ask(tester, 'Why this route?');
    expect(find.text('Copy answer'), findsOneWidget);
  });

  group('with an on-device labeler (D1; the box waits for it, then the rules answer from its label)', () {
    const confidenceLabel = '{"intent": "confidence", "secondary": null}';

    testWidgets('shows that it is working, blocks a second send, then shows the answer', (tester) async {
      final gate = Completer<String?>();
      final l = _FakeLabeler((_) => gate.future);
      await _show(tester, labeler: l);
      await tester.enterText(find.byKey(const Key('ask-field')), 'How long will it take?');
      await tester.tap(find.byKey(const Key('ask-send')));
      await tester.pump();
      expect(find.byKey(const Key('ask-thinking')), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const Key('ask-send'))).onPressed, isNull);
      expect(find.byKey(const Key('ask-answer')), findsNothing);
      gate.complete(confidenceLabel);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ask-thinking')), findsNothing);
      expect(l.calls, 1);
      // the model's label (confidence) decided the answer, not the rules' (time and distance)
      expect(_answer(tester), isNot(contains('17 minutes')));
      expect(tester.widget<FilledButton>(find.byKey(const Key('ask-send'))).onPressed, isNotNull);
    });

    testWidgets('a model that fails leaves the rule-based answer, with no error on screen', (tester) async {
      await _show(tester, labeler: _FakeLabeler((_) async => throw StateError('crashed')));
      await _ask(tester, 'How long will it take?');
      expect(_answer(tester), contains('17 minutes'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a safety question the model labels as something else is still refused', (tester) async {
      await _show(tester, labeler: _FakeLabeler((_) async => '{"intent": "why_route", "secondary": null}'));
      await _ask(tester, 'Is this route safe?');
      expect(_answer(tester), contains('I cannot confirm the condition of any road'));
    });

    testWidgets('a new route while the model is working drops the late reply without an error', (tester) async {
      final gate = Completer<String?>();
      await _show(tester, labeler: _FakeLabeler((_) => gate.future));
      await tester.enterText(find.byKey(const Key('ask-field')), 'How long will it take?');
      await tester.tap(find.byKey(const Key('ask-send')));
      await tester.pump();
      await _show(tester, queryId: 'another route', labeler: _FakeLabeler((_) => gate.future));
      gate.complete(confidenceLabel);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ask-answer-card')), findsNothing);
      expect(find.byKey(const Key('ask-thinking')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('without a labeler nothing waits: the answer is there in the same frame', (tester) async {
      await _show(tester);
      await tester.enterText(find.byKey(const Key('ask-field')), 'How long will it take?');
      await tester.tap(find.byKey(const Key('ask-send')));
      await tester.pump();
      expect(find.byKey(const Key('ask-answer')), findsOneWidget);
      expect(find.byKey(const Key('ask-thinking')), findsNothing);
    });
  });

  test('the new strings obey ADR-011 in both languages (also enforced for every string by strings_test)', () {
    for (final m in [
      Msg.askHeading,
      Msg.askHint,
      Msg.askSend,
      Msg.askClear,
      Msg.askCopy,
      Msg.askCopied,
      Msg.askThinking,
      Msg.askSource,
      Msg.askExample1,
      Msg.askExample2,
      Msg.askExample3,
      Msg.askExample4,
    ]) {
      expect(englishStrings[m], isNotEmpty);
      expect(tamilStrings[m], isNotEmpty);
    }
  });
}
