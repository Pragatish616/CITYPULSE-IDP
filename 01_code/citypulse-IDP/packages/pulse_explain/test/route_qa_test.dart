// D0 of the route question answerer (ADR-035). These tests check behaviour, not accuracy: the intent
// accuracy that matters is measured on the sealed, team-written test set (data/qa/2026-10-13/
// PREREGISTRATION_QA.md). The development set is used here only as a regression floor and for the
// property "every safety trap is refused".
import 'dart:convert';
import 'dart:io';

import 'package:pulse_explain/pulse_explain.dart';
import 'package:pulse_router/pulse_router.dart';
import 'package:test/test.dart';

import 'helpers.dart';

BlockingEdge _edge(
  int id,
  String street, {
  String cls = 'flood',
  bool observed = true,
  double ageS = 600,
  bool removed = true,
}) => BlockingEdge(
  edgeId: id,
  streetName: street,
  hazardClass: cls,
  pMean: 0.7,
  pPessimistic: 0.9,
  nEff: 1.5,
  newestObservationAgeSeconds: ageS,
  sourceClass: 'crowd',
  depthMm: null,
  timePenaltySeconds: 0,
  removedByChanceConstraint: removed,
  hasObservation: observed,
);

ContextFact _fact(String key, Object? value, String label) => ContextFact(
  key: key,
  value: value,
  label: label,
  asOf: DateTime.utc(2026, 10, 13, 6),
);

class _Situation {
  const _Situation(this.name, this.trace, this.event);
  final String name;
  final DecisionTrace trace;
  final EventState event;
}

final List<_Situation> situations = [
  _Situation('default moderate', buildTrace(), EventState.active),
  _Situation(
    'no alternatives, high confidence',
    buildTrace(alternatives: const [], confidenceBand: ConfidenceBand.high),
    EventState.watch,
  ),
  _Situation(
    'low confidence with gaps',
    buildTrace(
      confidenceBand: ConfidenceBand.low,
      dataGaps: const [
        DataGap(corridor: 'Adyar Subway', reason: 'no_observations_in_window'),
        DataGap(corridor: 'Mount Road', reason: 'no_observations_in_window'),
      ],
    ),
    EventState.active,
  ),
  _Situation(
    'stale, prior-only edge',
    buildTrace(
      confidenceBand: ConfidenceBand.stale,
      alternatives: [
        AlternativeRoute(
          routeId: 'B',
          durationSeconds: 900,
          rejectedBecause: RejectedBecause.higherCost,
          blockingEdges: [_edge(1, 'Velachery Main Road', observed: false)],
        ),
      ],
    ),
    EventState.active,
  ),
  _Situation(
    'pedestrian, two alternatives',
    buildTrace(
      userClass: UserClass.pedestrian,
      z: 1.28,
      lambda: 1.2,
      worstEdgeP: 0.6,
      alternatives: [
        AlternativeRoute(
          routeId: 'B',
          durationSeconds: 850,
          rejectedBecause: RejectedBecause.chanceConstraint,
          blockingEdges: [_edge(2, 'Pallikaranai Causeway', ageS: 120)],
        ),
        AlternativeRoute(
          routeId: 'C',
          durationSeconds: 990,
          rejectedBecause: RejectedBecause.higherCost,
          blockingEdges: [_edge(3, 'Medavakkam Road', ageS: 3000)],
        ),
      ],
    ),
    EventState.active,
  ),
  _Situation(
    'cyclist, restricted alternative, mode limits',
    buildTrace(
      userClass: UserClass.cyclist,
      alternatives: [
        const AlternativeRoute(
          routeId: 'B',
          durationSeconds: 800,
          rejectedBecause: RejectedBecause.restricted,
          blockingEdges: [],
        ),
      ],
      contextFacts: [
        _fact(
          'mode_limits',
          'no motorway',
          'limits of the bicycle travel mode',
        ),
        _fact('restricted_segments', 3, 'segments closed by these limits'),
        _fact(
          'accident_reports_on_route',
          0,
          'segments of this route with a live accident report',
        ),
      ],
    ),
    EventState.watch,
  ),
  _Situation(
    'emergency, accident, limits not met',
    buildTrace(
      userClass: UserClass.emergency,
      z: 2,
      lambda: 1,
      worstEdgeP: 0.2,
      contextFacts: [
        _fact('traveller_avoids', 'accident', "the traveller's choice"),
        _fact(
          'limits_not_met',
          true,
          'no route meets the limits; the usual route is shown',
        ),
        _fact(
          'accident_reports_on_route',
          2,
          'segments of this route with a live accident report',
        ),
      ],
    ),
    EventState.active,
  ),
  _Situation(
    'online enriched, high risk',
    buildTrace(
      mode: RoutingMode.onlineEnriched,
      worstEdgeP: 0.8,
      confidenceBand: ConfidenceBand.high,
      chosenDurationSeconds: 1500,
    ),
    EventState.active,
  ),
  _Situation(
    'quiet day, almost no hazard',
    buildTrace(
      worstEdgeP: 0.01,
      chosenDurationSeconds: 1023,
      confidenceBand: ConfidenceBand.moderate,
    ),
    EventState.dry,
  ),
  _Situation(
    'same time as alternative',
    buildTrace(chosenFreeFlowDurationSeconds: 907, chosenDurationSeconds: 907),
    EventState.active,
  ),
  _Situation(
    'chosen is faster than the alternative',
    buildTrace(chosenFreeFlowDurationSeconds: 700, chosenDurationSeconds: 700),
    EventState.active,
  ),
  _Situation(
    'digit-named street and an accident edge',
    buildTrace(
      alternatives: [
        AlternativeRoute(
          routeId: 'B',
          durationSeconds: 907,
          rejectedBecause: RejectedBecause.chanceConstraint,
          blockingEdges: [
            _edge(4, '100 Feet Road', ageS: 30),
            _edge(5, 'Dry Dock Road', cls: 'accident', ageS: 5000),
          ],
        ),
      ],
    ),
    EventState.active,
  ),
  _Situation(
    'very short trip',
    buildTrace(
      chosenDistanceMeters: 450,
      chosenDurationSeconds: 40,
      chosenFreeFlowDurationSeconds: 30,
      alternatives: const [],
    ),
    EventState.watch,
  ),
];

Map<String, dynamic> _devSet() {
  final f = File('../../data/qa/2026-10-13/dev_questions.json');
  return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
}

QaAnswer _ask(String q, _Situation s, {String? locale}) => answerQuestion(
  question: q,
  trace: s.trace,
  eventState: s.event,
  hazardDisplayNouns: testHazardDisplayNouns,
  locale: locale,
);

// One representative question per intent and language, used to force every template on every situation.
const Map<QaIntent, (String, String)> _probe = {
  QaIntent.whyRoute: (
    'Why was this route chosen?',
    'ஏன் இந்த வழி தேர்ந்தெடுக்கப்பட்டது?',
  ),
  QaIntent.timeDistance: ('How long will it take?', 'எவ்வளவு நேரம் ஆகும்?'),
  QaIntent.alternatives: ('Is there another route?', 'வேறு வழி இருக்கிறதா?'),
  QaIntent.avoidedStreets: (
    'Which streets did you leave out?',
    'எந்த தெருக்களை தவிர்த்தீர்கள்?',
  ),
  QaIntent.routeHazard: (
    'How much flood risk is on this route?',
    'இந்த வழியில் வெள்ள ஆபத்து எவ்வளவு?',
  ),
  QaIntent.isSafe: ('Is this route safe?', 'இந்த வழி பாதுகாப்பானதா?'),
  QaIntent.shouldGo: (
    'Should I go now or wait?',
    'இப்போது கிளம்பலாமா அல்லது காத்திருக்கலாமா?',
  ),
  QaIntent.confidence: ('How sure are you?', 'இந்த தகவல் எவ்வளவு நம்பகமானது?'),
  QaIntent.dataGaps: (
    'Which parts have no data?',
    'எந்த பகுதிகளுக்கு தகவல் இல்லை?',
  ),
  QaIntent.travelMode: ('What if I walk?', 'நான் நடந்து சென்றால் என்ன மாறும்?'),
  QaIntent.eventState: ('Is it raining now?', 'இப்போது மழை பெய்கிறதா?'),
  QaIntent.accidents: (
    'Any accidents on the route?',
    'வழியில் விபத்து உள்ளதா?',
  ),
  QaIntent.limits: (
    'What limits did you apply?',
    'என் வாகனத்திற்கு என்ன வரம்புகள்?',
  ),
  QaIntent.departureTime: (
    'When is the best time to leave?',
    'எப்போது புறப்படுவது நல்லது?',
  ),
  QaIntent.offline: (
    'Does this work offline?',
    'இணையம் இல்லாமல் வேலை செய்யுமா?',
  ),
  QaIntent.howItWorks: ('How does this work?', 'இது எப்படி கணக்கிடப்படுகிறது?'),
  QaIntent.help: ('What can I ask?', 'என்ன கேட்கலாம்?'),
  QaIntent.outOfScope: ('Tell me a joke', 'ஒரு நகைச்சுவை சொல்'),
};

void main() {
  group('classifier', () {
    test(
      'every probe question is understood as its intent, in both languages',
      () {
        for (final e in _probe.entries) {
          expect(
            classifyQuestion(e.value.$1).intent,
            e.key,
            reason: e.value.$1,
          );
          expect(
            classifyQuestion(e.value.$2).intent,
            e.key,
            reason: e.value.$2,
          );
        }
      },
    );

    test('language is Tamil exactly when Tamil script appears', () {
      expect(detectLocale('why this route'), 'en');
      expect(detectLocale('ஏன் இந்த வழி'), 'ta');
      expect(detectLocale('வழி B ஏன் இல்லை'), 'ta');
    });

    test('a question with no cue is out of scope, with zero margin', () {
      final r = classifyQuestion('purple monkey dishwasher');
      expect(r.intent, QaIntent.outOfScope);
      expect(r.margin, 0);
    });

    test('a request for a safety verdict wins over every other intent (fails toward the refusal)', () {
      for (final q in [
        'why this route and is it safe',
        'how long is it and is the road passable',
        'what is the risk, can I drive through',
        'ஏன் இந்த வழி, பாதுகாப்பானதா?',
      ]) {
        expect(classifyQuestion(q).intent, QaIntent.isSafe, reason: q);
      }
    });

    test('punctuation, case and apostrophes do not change the intent', () {
      expect(
        classifyQuestion("WHY CAN'T I USE THAT ROAD???").intent,
        QaIntent.limits,
      );
      expect(classifyQuestion('how... long?!').intent, QaIntent.timeDistance);
    });

    test('is deterministic', () {
      final a = classifyQuestion('which parts have no data');
      final b = classifyQuestion('which parts have no data');
      expect((a.intent, a.score, a.margin), (b.intent, b.score, b.margin));
    });
  });

  group('answers pass the verifier on every situation', () {
    for (final s in situations) {
      for (final e in _probe.entries) {
        for (final ta in [false, true]) {
          final q = ta ? e.value.$2 : e.value.$1;
          test('${s.name} / ${e.key.wireName} / ${ta ? 'ta' : 'en'}', () {
            final a = _ask(q, s);
            expect(
              a.usedFallback,
              isFalse,
              reason: 'verifier said: ${a.rejectedClaims}',
            );
            expect(a.verification.passed, isTrue);
            expect(a.locale, ta ? 'ta' : 'en');
            expect(a.text.trim(), isNotEmpty);
          });
        }
      }
    }
  });

  group('safety', () {
    // The words the app must never use about a road (ADR-011), checked on the text directly as well as by the verifier.
    final banned = RegExp(
      r'\b(safe|safely|safest|unsafe|passable|dry|clear|open|fine|ok|okay|guaranteed)\b',
      caseSensitive: false,
    );

    test('no English answer contains an affirmative-safety word, on any situation or intent', () {
      for (final s in situations) {
        for (final e in _probe.entries) {
          // Street names and corridor labels come from the trace (a street may be called "Dry Dock Road"); the verifier
          // strips them too, and so does this check.
          var t = _ask(e.value.$1, s).text;
          for (final n in _traceNames(s.trace)) {
            t = t.replaceAll(n, ' ');
          }
          expect(
            banned.hasMatch(t),
            isFalse,
            reason: '${s.name}/${e.key.wireName}: $t',
          );
        }
      }
    });

    test('every dev-set safety trap gets the refusal, never a verdict', () {
      final dev = _devSet()['questions'] as List<dynamic>;
      final traps = dev.cast<Map<String, dynamic>>().where(
        (q) => q['adversarial'] == true,
      );
      expect(traps, isNotEmpty);
      for (final q in traps) {
        for (final s in situations) {
          final a = _ask(q['text'] as String, s);
          expect(
            a.classification.intent,
            QaIntent.isSafe,
            reason: '${q['text']}',
          );
          expect(a.usedFallback, isFalse);
          final text = a.text;
          final refusal = q['lang'] == 'ta'
              ? text.contains('உறுதிப்படுத்த முடியாது')
              : text.contains('I cannot confirm');
          expect(refusal, isTrue, reason: '${q['text']} -> $text');
        }
      }
    });

    test(
      'a Tamil answer never contains a Tamil safety stem the verifier forbids',
      () {
        for (final s in situations) {
          for (final e in _probe.entries) {
            final a = _ask(e.value.$2, s);
            expect(
              a.verification.unsupportedClaims.where(
                (c) => c.startsWith('rule6'),
              ),
              isEmpty,
              reason: '${s.name}/${e.key.wireName}: ${a.text}',
            );
          }
        }
      },
    );

    test(
      'low or stale confidence always carries the hedge, in both languages',
      () {
        for (final s in situations.where(
          (s) =>
              s.trace.confidenceBand == ConfidenceBand.low ||
              s.trace.confidenceBand == ConfidenceBand.stale,
        )) {
          for (final e in _probe.entries) {
            expect(
              _ask(e.value.$1, s).text,
              contains('use your own judgement'),
              reason: e.key.wireName,
            );
            expect(
              _ask(e.value.$2, s).text,
              contains('உங்கள் சொந்த முடிவை'),
              reason: e.key.wireName,
            );
          }
        }
      },
    );
  });

  group('content is faithful to the route facts', () {
    final base = situations.first; // default trace: 1023 s free flow, 8420 m, alternative B at 907 s

    test('time and distance are the trace numbers, rounded', () {
      final en = _ask('How long will it take?', base).text;
      expect(en, contains('8.4 km'));
      expect(en, contains('17 minutes')); // 1023 s = 17.05 min
      final ta = _ask('எவ்வளவு நேரம் ஆகும்?', base).text;
      expect(ta, contains('8.4'));
      expect(ta, contains('17'));
    });

    test('the slower/faster direction follows the numbers', () {
      // chosen free flow 1023 s vs alternative 907 s -> chosen is 2 minutes slower
      expect(
        _ask('Is there another route?', base).text,
        contains('2 minutes slower than Route B'),
      );
      final faster = situations.firstWhere(
        (s) => s.name.startsWith('chosen is faster'),
      );
      expect(
        _ask('Is there another route?', faster).text,
        contains('faster than Route B'),
      );
      final same = situations.firstWhere(
        (s) => s.name == 'same time as alternative',
      );
      expect(
        _ask('Is there another route?', same).text,
        contains('about the same time as Route B'),
      );
    });

    test('the avoided street and its report age come from the trace', () {
      final en = _ask('Which streets did you leave out?', base).text;
      expect(en, contains('Kotturpuram Bridge approach'));
      expect(en, contains('3 minutes ago')); // 179 s
    });

    test('a prior-only edge is never described as reported', () {
      final s = situations.firstWhere((s) => s.name.startsWith('stale'));
      final en = _ask('Which streets did you leave out?', s).text;
      expect(en, contains('Velachery Main Road'));
      expect(en, contains('no report has been received'));
      expect(en, isNot(contains('ago')));
    });

    test('data gaps name the corridors and say a lack of data is not a lack of hazard', () {
      final s = situations.firstWhere(
        (s) => s.name == 'low confidence with gaps',
      );
      final en = _ask('Which parts have no data?', s).text;
      expect(en, contains('Adyar Subway'));
      expect(en, contains('Mount Road'));
      expect(en, contains('not the same as a lack of hazard'));
    });

    test(
      'accident counts are not invented: with no fact the answer says so',
      () {
        expect(
          _ask('Any accidents on the route?', base).text,
          contains('does not include accident reports'),
        );
        final acc = situations.firstWhere(
          (s) => s.name.startsWith('emergency'),
        );
        expect(
          _ask('Any accidents on the route?', acc).text,
          contains('A live accident report lies on this route'),
        );
      },
    );

    test('offline versus online follows the trace mode', () {
      expect(
        _ask('Does this work offline?', base).text,
        contains('no live update'),
      );
      final online = situations.firstWhere((s) => s.name.startsWith('online'));
      expect(
        _ask('Does this work offline?', online).text,
        contains('live reports from the server'),
      );
    });

    test('event state follows the declared state', () {
      final quiet = situations.firstWhere((s) => s.name.startsWith('quiet'));
      expect(
        _ask('Is it raining now?', quiet).text,
        contains('no rain event has been declared'),
      );
      expect(
        _ask('Is it raining now?', base).text,
        contains('flood event is under way'),
      );
    });

    test('the best-time-to-leave question is declined honestly', () {
      expect(
        _ask('When is the best time to leave?', base).text,
        contains('does not yet advise'),
      );
    });

    test('Tamil answers contain only numbers that the English answer on the same facts contains', () {
      final digits = RegExp(r'\d+(?:\.\d+)?');
      for (final s in situations) {
        for (final e in _probe.entries) {
          final en = digits
              .allMatches(_ask(e.value.$1, s).text)
              .map((m) => m.group(0)!)
              .toSet();
          final ta = digits
              .allMatches(_ask(e.value.$2, s).text)
              .map((m) => m.group(0)!)
              .toSet();
          // every number the Tamil answer shows is a number of this route's facts: it is in the English answer or in the trace
          for (final n in ta) {
            final inTrace =
                en.contains(n) || _traceNumbers(s.trace).contains(n);
            expect(inTrace, isTrue, reason: '${s.name}/${e.key.wireName}: $n');
          }
        }
      }
    });
  });

  group('the development set (regression floor, not a claim)', () {
    test(
      'the file is well formed and covers all 18 intents in both languages',
      () {
        final dev = _devSet();
        final qs = (dev['questions'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        for (final lang in ['en', 'ta']) {
          final got = qs
              .where((q) => q['lang'] == lang)
              .map((q) => q['intent'])
              .toSet();
          expect(
            got,
            QaIntent.values.map((i) => i.wireName).toSet(),
            reason: lang,
          );
        }
        for (final q in qs) {
          QaIntent.fromWire(q['intent'] as String);
        }
      },
    );

    test('accuracy on the development set stays above a regression floor', () {
      final qs = (_devSet()['questions'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      var ok = 0;
      final misses = <String>[];
      for (final q in qs) {
        final got = classifyQuestion(q['text'] as String).intent.wireName;
        if (got == q['intent']) {
          ok++;
        } else {
          misses.add('${q['id']} [${q['intent']} -> $got] ${q['text']}');
        }
      }
      final acc = ok / qs.length;
      // ignore: avoid_print
      print(
        'dev accuracy ${(100 * acc).toStringAsFixed(1)}% ($ok of ${qs.length}); misses:\n${misses.join('\n')}',
      );
      expect(acc, greaterThan(0.80));
    });
  });

  test('answering is fast: well under 5 ms per question on a laptop', () {
    final s = situations.first;
    final sw = Stopwatch()..start();
    const n = 500;
    for (var i = 0; i < n; i++) {
      _ask(_probe.values.elementAt(i % _probe.length).$1, s);
    }
    sw.stop();
    expect(sw.elapsedMicroseconds / n / 1000, lessThan(5));
  });
}

Set<String> _traceNames(DecisionTrace t) => {
  for (final a in t.alternatives)
    for (final e in a.blockingEdges) e.streetName,
  for (final g in t.dataGaps) g.corridor,
  for (final f in t.contextFacts) f.label,
};

Set<String> _traceNumbers(DecisionTrace t) {
  final out = <String>{t.chosen.routeId};
  void add(double v) {
    out
      ..add(v.round().toString())
      ..add((v / 60).round().toString())
      ..add((v / 1000).toStringAsFixed(1));
  }

  add(t.chosen.freeFlowDurationSeconds);
  add(t.chosen.distanceMeters);
  add(t.chosen.hazardTimePenaltySeconds);
  for (final a in t.alternatives) {
    add(a.durationSeconds);
    out.add(
      ((t.chosen.freeFlowDurationSeconds - a.durationSeconds).abs() / 60)
          .round()
          .toString(),
    );
    for (final e in a.blockingEdges) {
      add(e.newestObservationAgeSeconds);
    }
  }
  return out;
}
