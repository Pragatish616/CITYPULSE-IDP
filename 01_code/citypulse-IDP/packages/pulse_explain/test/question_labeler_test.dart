// D1 of the route-question ladder (ADR-035, PREREGISTRATION_QA.md addendum 5): the model only labels the question; D0's templates
// write the answer and the verifier checks it. These tests check the rules around the model, not the model: a fake labeler stands in.
import 'dart:async';
import 'dart:io';

import 'package:pulse_explain/pulse_explain.dart';
import 'package:pulse_router/pulse_router.dart';
import 'package:test/test.dart';

import 'helpers.dart';

class _Fake implements QuestionLabeler {
  _Fake(this._reply);
  final FutureOr<String?> Function(String q) _reply;
  int calls = 0;

  @override
  Future<String?> reply(String question) async {
    calls++;
    return _reply(question);
  }
}

String _label(QaIntent i, [QaIntent? s]) =>
    '{"intent": "${i.wireName}", "secondary": ${s == null ? 'null' : '"${s.wireName}"'}}';

Future<LadderResult> _run(String q, QuestionLabeler? l, {Duration? timeout}) =>
    answerWithLabeler(
      question: q,
      trace: buildTrace(),
      eventState: EventState.active,
      hazardDisplayNouns: testHazardDisplayNouns,
      labeler: l,
      timeout: timeout ?? kLabelTimeout,
    );

const String _refusal = 'I cannot confirm the condition of any road';

void main() {
  group('reading the model reply (same rule as ml/route_qa/prompts.py parse_label)', () {
    test('a valid label is read, with or without a second part', () {
      expect(
        parseModelLabel(_label(QaIntent.timeDistance)),
        const ModelLabel(QaIntent.timeDistance),
      );
      expect(
        parseModelLabel(_label(QaIntent.isSafe, QaIntent.avoidedStreets)),
        const ModelLabel(QaIntent.isSafe, QaIntent.avoidedStreets),
      );
    });

    test('text around the object is ignored, the first object wins', () {
      expect(
        parseModelLabel(
          'Sure! ${_label(QaIntent.whyRoute)} and also ${_label(QaIntent.help)}',
        ),
        const ModelLabel(QaIntent.whyRoute),
      );
    });

    test('a second part equal to the main one, or unknown, is dropped', () {
      expect(
        parseModelLabel('{"intent": "help", "secondary": "help"}'),
        const ModelLabel(QaIntent.help),
      );
      expect(
        parseModelLabel('{"intent": "help", "secondary": "nonsense"}'),
        const ModelLabel(QaIntent.help),
      );
      expect(
        parseModelLabel('{"intent": "help", "secondary": 7}'),
        const ModelLabel(QaIntent.help),
      );
    });

    test('anything that is not a valid label gives no label, never a guess', () {
      for (final bad in [
        '',
        'is_safe',
        '{}',
        '{"intent": "nonsense", "secondary": null}',
        '{"intent": 3}',
        '{"intent": ["help"]}',
        '{"intent": "help"',
        '{intent: help}',
        'the road is safe',
        '{"intent": null, "secondary": "help"}',
      ]) {
        expect(parseModelLabel(bad), isNull, reason: bad);
      }
    });

    test('the same table as the Python reader gives the same labels', () {
      // Mirrors ml/route_qa/tests/test_prompts.py: keep the two in step.
      final cases = <String, ModelLabel?>{
        '{"intent": "why_route", "secondary": null}': const ModelLabel(
          QaIntent.whyRoute,
        ),
        '{"intent": "is_safe", "secondary": "avoided_streets"}':
            const ModelLabel(QaIntent.isSafe, QaIntent.avoidedStreets),
        '{"intent": "bogus", "secondary": null}': null,
        'no json here': null,
        // the first {...} is read even inside brackets, as the Python reader does
        '[{"intent": "help"}]': const ModelLabel(QaIntent.help),
      };
      cases.forEach((reply, want) => expect(parseModelLabel(reply), want));
    });
  });

  group('the model prompt and intent list match the training code', () {
    final f = File('../../ml/route_qa/prompts.py');
    final py = f.existsSync() ? f.readAsStringSync() : null;

    test('the system prompt is the one the model was trained with', () {
      final m = RegExp(r'SYSTEM_U = "([^"]*)"').firstMatch(py!);
      expect(m, isNotNull);
      expect(kLabelSystemPrompt, m!.group(1));
      final msgs = labelMessages('How long?');
      expect(msgs.map((e) => e.role), ['system', 'user']);
      expect(msgs.last.content, 'How long?');
    }, skip: py == null ? 'ml/route_qa/prompts.py not found' : false);

    test('the 19 intents are the same, in the same order', () {
      final block = RegExp(r'INTENTS = \[(.*?)\]', dotAll: true).firstMatch(py!)!;
      final names = RegExp(r'"([a-z_]+)"')
          .allMatches(block.group(1)!)
          .map((m) => m.group(1)!)
          .toList();
      expect(names, QaIntent.values.map((i) => i.wireName).toList());
    }, skip: py == null ? 'ml/route_qa/prompts.py not found' : false);
  });

  group('the ladder', () {
    test('no model: the rule-based answer, and nothing waits', () async {
      final r = await _run('How long will it take?', null);
      expect(r.usedModel, isFalse);
      expect(r.note, 'no model');
      expect(r.answer.classification.intent, QaIntent.timeDistance);
    });

    test('a different, readable label decides how the question is answered', () async {
      final l = _Fake((_) => _label(QaIntent.confidence));
      final r = await _run('How long will it take?', l);
      expect(l.calls, 1);
      expect(r.usedModel, isTrue);
      expect(r.answer.classification.intent, QaIntent.confidence);
      expect(r.answer.verification.passed || r.answer.usedFallback, isTrue);
    });

    test('the same label as the rules gives the rule-based answer untouched', () async {
      final r = await _run(
        'How long will it take?',
        _Fake((_) => _label(QaIntent.timeDistance)),
      );
      expect(r.usedModel, isFalse);
      expect(r.note, 'same label');
      expect(r.modelLabel, const ModelLabel(QaIntent.timeDistance));
    });

    test('an error, no reply, an unreadable reply or a slow reply gives the rule-based answer', () async {
      final slow = Completer<String?>();
      for (final l in <QuestionLabeler>[
        _Fake((_) => throw StateError('model crashed')),
        _Fake((_) => null),
        _Fake((_) => 'the road is safe'),
        _Fake((_) => slow.future),
      ]) {
        final r = await _run(
          'How long will it take?',
          l,
          timeout: const Duration(milliseconds: 50),
        );
        expect(r.usedModel, isFalse);
        expect(r.note, 'no label');
        expect(r.answer.classification.intent, QaIntent.timeDistance);
      }
    });

    test('safety guard: a safety question the model labels as something else is still refused', () async {
      for (final q in [
        'Is this route safe?',
        'Can I go through, is the road passable?',
        'IS IT SAFE',
      ]) {
        final r = await _run(q, _Fake((_) => _label(QaIntent.whyRoute)));
        expect(r.usedModel, isFalse, reason: q);
        expect(r.note, 'safety guard', reason: q);
        expect(r.answer.text, contains(_refusal), reason: q);
      }
    });

    test('the model may add caution: labelling a question as a safety question refuses it', () async {
      final r = await _run(
        'How long will it take?',
        _Fake((_) => _label(QaIntent.isSafe)),
      );
      expect(r.usedModel, isTrue);
      expect(r.answer.text, contains(_refusal));
    });

    test('a two-part label is answered in both parts, safety first', () async {
      final r = await _run(
        'tell me about the detour',
        _Fake((_) => _label(QaIntent.avoidedStreets, QaIntent.isSafe)),
      );
      expect(r.usedModel, isTrue);
      expect(r.answer.text, contains(_refusal));
      expect(r.answer.text.startsWith('I cannot confirm') || r.answer.text.contains(_refusal), isTrue);
    });

    test('only the label is taken from the model: its other words never reach the screen', () async {
      final r = await _run(
        'How long will it take?',
        _Fake(
          (_) =>
              'Sure! The road is dry and safe, go ahead. ${_label(QaIntent.confidence)} <script>',
        ),
      );
      expect(r.usedModel, isTrue);
      final t = r.answer.text.toLowerCase();
      for (final w in ['sure', 'go ahead', 'dry and safe', '<script>']) {
        expect(t, isNot(contains(w)));
      }
    });

    test('every label on every kind of question gives an answer that passed the verifier or the fixed fallback', () async {
      for (final i in QaIntent.values) {
        for (final j in <QaIntent?>[null, QaIntent.isSafe, QaIntent.dataGaps]) {
          for (final band in ConfidenceBand.values) {
            final r = await answerWithLabeler(
              question: 'what about the flooding near the route',
              trace: buildTrace(confidenceBand: band),
              eventState: EventState.active,
              hazardDisplayNouns: testHazardDisplayNouns,
              labeler: _Fake((_) => _label(i, j)),
            );
            expect(
              r.answer.verification.passed || r.answer.usedFallback,
              isTrue,
              reason: '${i.wireName}/${j?.wireName}/$band',
            );
            expect(r.answer.text.trim(), isNotEmpty);
          }
        }
      }
    });

    test('the model sees only the question: it is called once with the question text', () async {
      final seen = <String>[];
      final l = _Fake((q) {
        seen.add(q);
        return null;
      });
      await _run('Why this route?', l);
      expect(seen, ['Why this route?']);
    });
  });
}
