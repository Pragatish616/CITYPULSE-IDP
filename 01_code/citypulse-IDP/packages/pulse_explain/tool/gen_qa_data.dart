// Builds training data for the route question model (ADR-035, PREREGISTRATION_QA.md addendum 1).
//
//   dart run tool/gen_qa_data.dart [--out DIR] [--seed N] [--situations N] [--styles N] [--include-tamil-answers]
//
// For many random route situations it writes labelled questions and, for English, several verified phrasings
// of the answer. Rules it keeps (all from the pre-registration):
//  * every answer written here passed `verify` (an answer that fell back is dropped and counted);
//  * labels come from the question bank's gold labels, never from the classifier (the classifier's agreement is
//    recorded, not used);
//  * train and validation are split by situation, not by row;
//  * no sealed test text: if data/qa/2026-10-13/test_questions.json exists, any question that matches one of
//    its questions (after normalising) is refused;
//  * Tamil questions teach understanding only; Tamil answers are not written unless --include-tamil-answers,
//    because no native speaker has approved a Tamil answer set.
// Same seed, same files.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:pulse_explain/pulse_explain.dart';
import 'package:pulse_router/pulse_router.dart';

const _nouns = {
  'flood': 'flooding',
  'waterlogging': 'waterlogging',
  'accident': 'an accident',
};

const _streets = [
  'Velachery Main Road',
  'Pallikaranai Causeway',
  'Medavakkam Road',
  'Adyar Bridge approach',
  'Mount Road',
  'Anna Salai',
  'Kotturpuram Bridge approach',
  'Guindy Subway',
  'Mambalam Subway',
  'Perungudi Junction',
  'Saidapet Bridge',
  'Taramani Link Road',
  'OMR Service Road',
  'ECR Junction',
  'Porur Junction',
  'Koyambedu Flyover',
  'Ambattur Underpass',
  'Tambaram Road',
  '100 Feet Road',
  'Dry Dock Road',
  'Poonamallee High Road',
  'Sholinganallur Junction',
  'Besant Nagar Road',
  'Kilpauk Garden Road',
];

String _norm(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}\p{M}\s]', unicode: true), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

T _pick<T>(Random r, List<T> xs) => xs[r.nextInt(xs.length)];

DecisionTrace _randomTrace(Random r, int idx) {
  final cls = _pick(r, UserClass.values);
  final ff = 120 + r.nextInt(5200);
  final penalty = r.nextBool() ? 0.0 : ff * r.nextDouble() * 0.25;
  final dist = 500 + r.nextInt(32000);
  final band = _pick(r, ConfidenceBand.values);
  final worst = _pick(r, const [0.0, 0.01, 0.05, 0.2, 0.45, 0.7, 0.95]);
  final nAlt = r.nextInt(4);
  final alts = <AlternativeRoute>[];
  for (var i = 0; i < nAlt; i++) {
    final id = 'BCD'[i];
    final sameTime = r.nextInt(8) == 0;
    final dur = sameTime ? ff.toDouble() : ff * (0.6 + r.nextDouble() * 0.9);
    final why = _pick(r, RejectedBecause.values);
    final nEdge = why == RejectedBecause.restricted ? r.nextInt(2) : 1 + r.nextInt(2);
    alts.add(
      AlternativeRoute(
        routeId: id,
        durationSeconds: dur,
        rejectedBecause: why,
        blockingEdges: [
          for (var e = 0; e < nEdge; e++)
            BlockingEdge(
              edgeId: idx * 10 + i * 3 + e,
              streetName: _pick(r, _streets),
              hazardClass: _pick(r, const ['flood', 'flood', 'flood', 'waterlogging', 'accident']),
              pMean: 0.5 + r.nextDouble() * 0.45,
              pPessimistic: 0.7 + r.nextDouble() * 0.3,
              nEff: 0.5 + r.nextDouble() * 3,
              newestObservationAgeSeconds: _pick(r, const [20.0, 90.0, 300.0, 900.0, 3600.0, 7200.0]),
              sourceClass: 'crowd',
              depthMm: null,
              timePenaltySeconds: 0,
              removedByChanceConstraint: why == RejectedBecause.chanceConstraint,
              hasObservation: r.nextInt(4) != 0,
            ),
        ],
      ),
    );
  }
  final asOf = DateTime.utc(2026, 10, 13, 6);
  final facts = <ContextFact>[
    if (r.nextInt(3) == 0)
      ContextFact(key: 'mode_limits', value: 'x', label: 'limits of the ${cls == UserClass.cyclist ? 'bicycle' : 'car'} travel mode', asOf: asOf),
    if (r.nextInt(6) == 0) ContextFact(key: 'restricted_segments', value: 1 + r.nextInt(4), label: 'segments closed by these limits', asOf: asOf),
    if (r.nextInt(8) == 0) ContextFact(key: 'limits_not_met', value: true, label: 'no route meets the limits; the usual route is shown', asOf: asOf),
    if (r.nextInt(5) == 0) ContextFact(key: 'traveller_avoids', value: 'accident', label: "the traveller's choice", asOf: asOf),
    if (r.nextInt(2) == 0)
      ContextFact(key: 'accident_reports_on_route', value: r.nextInt(3), label: 'segments of this route with a live accident report', asOf: asOf),
  ];
  // A corridor with no data is not one that also has a reported hazard, so gaps avoid the streets named above.
  final named = {for (final a in alts) for (final e in a.blockingEdges) e.streetName};
  final free = [for (final s in _streets) if (!named.contains(s)) s];
  final nGap = r.nextInt(4);
  final gaps = <DataGap>[
    for (var g = 0; g < nGap; g++) DataGap(corridor: _pick(r, free), reason: 'no_observations_in_window'),
  ];
  final (z, lambda) = switch (cls) {
    UserClass.commuter => (0.0, 0.3),
    UserClass.pedestrian => (1.28, 1.2),
    UserClass.cyclist => (0.8, 0.6),
    UserClass.emergency => (2.0, 1.0),
  };
  return DecisionTrace(
    queryId: 'gen-$idx',
    computedAt: asOf,
    mode: r.nextInt(3) == 0 ? RoutingMode.onlineEnriched : RoutingMode.offline,
    userClass: cls,
    z: z,
    lambda: lambda,
    chosen: ChosenRoute(
      routeId: 'A',
      durationSeconds: ff + penalty,
      distanceMeters: dist.toDouble(),
      freeFlowDurationSeconds: ff.toDouble(),
      worstEdgeP: worst,
      geometryRef: 'nodes:1,2,3',
    ),
    alternatives: alts,
    contextFacts: facts,
    dataGaps: gaps,
    confidenceBand: band,
  );
}

class _Q {
  _Q(this.text, this.intent, this.secondary, this.source, this.lang);
  final String text;
  final QaIntent intent;
  final QaIntent? secondary;
  final String source;
  final String lang;
}

String _typo(Random r, String s) {
  final words = s.split(' ');
  final idx = [for (var i = 0; i < words.length; i++) if (words[i].length >= 5 && RegExp(r'^[a-zA-Z]+$').hasMatch(words[i])) i];
  if (idx.isEmpty) return s;
  final i = _pick(r, idx);
  final w = words[i];
  final k = 1 + r.nextInt(w.length - 2);
  words[i] = w.substring(0, k) + w[k + 1] + w[k] + w.substring(k + 2);
  return words.join(' ');
}

String _augment(Random r, String q, String lang) {
  var s = q;
  switch (r.nextInt(6)) {
    case 0:
      s = s.toLowerCase().replaceAll('?', '');
    case 1:
      s = lang == 'en' ? _typo(r, s) : s.replaceAll('?', '');
    case 2:
      s = lang == 'en' ? 'hey ${s[0].toLowerCase()}${s.substring(1)}' : s;
    case 3:
      s = lang == 'en' ? '${s.replaceAll('?', '')} pls' : s;
    case 4:
      s = lang == 'en' ? 'please ${s[0].toLowerCase()}${s.substring(1)}' : s;
    default:
      break;
  }
  return s;
}

void main(List<String> args) {
  String opt(String name, String dflt) {
    final i = args.indexOf('--$name');
    return i >= 0 && i + 1 < args.length ? args[i + 1] : dflt;
  }

  final out = Directory(opt('out', '../../data/qa/2026-10-13/generated'))..createSync(recursive: true);
  final seed = int.parse(opt('seed', '20261013'));
  final nSit = int.parse(opt('situations', '1500'));
  final nStyles = int.parse(opt('styles', '3'));
  final perSit = int.parse(opt('questions-per-situation', '8'));
  final tamilAnswers = args.contains('--include-tamil-answers');
  final r = Random(seed);

  // The question bank: gold-labelled development questions.
  final dev = jsonDecode(File('../../data/qa/2026-10-13/dev_questions.json').readAsStringSync()) as Map<String, dynamic>;
  final bank = <_Q>[
    for (final q in (dev['questions'] as List<dynamic>).cast<Map<String, dynamic>>())
      _Q(q['text'] as String, QaIntent.fromWire(q['intent'] as String), null, 'dev', q['lang'] as String),
  ];
  final pairable = [for (final q in bank) if (!const {QaIntent.help, QaIntent.summary, QaIntent.outOfScope}.contains(q.intent)) q];

  // Sealed test text must never be used.
  final sealedFile = File('../../data/qa/2026-10-13/test_questions.json');
  final sealed = <String>{};
  if (sealedFile.existsSync()) {
    for (final q in (jsonDecode(sealedFile.readAsStringSync()) as List<dynamic>).cast<Map<String, dynamic>>()) {
      sealed.add(_norm(q['text'] as String));
    }
  }

  final train = File('${out.path}/train.jsonl').openWrite();
  final val = File('${out.path}/val.jsonl').openWrite();
  final stats = <String, Object>{};
  final perIntent = <String, int>{};
  final perClass = <String, int>{};
  final perBand = <String, int>{};
  final rejected = <String, int>{};
  var records = 0, fallbacks = 0, answers = 0, agree = 0, sealedRefused = 0, nTrain = 0, nVal = 0;

  for (var s = 0; s < nSit; s++) {
    final trace = _randomTrace(r, s);
    final event = _pick(r, EventState.values);
    final sheet = qaFactSheet(trace: trace, eventState: event, hazardDisplayNouns: _nouns);
    final isVal = s % 10 == 0;
    perClass.update(trace.userClass.name, (v) => v + 1, ifAbsent: () => 1);
    perBand.update(trace.confidenceBand.name, (v) => v + 1, ifAbsent: () => 1);
    for (var k = 0; k < perSit; k++) {
      // a plain bank question, an augmented one, or a two-part pair
      final kind = r.nextInt(10);
      late final _Q q;
      if (kind < 3) {
        q = _pick(r, bank);
      } else if (kind < 8) {
        final b = _pick(r, bank);
        q = _Q(_augment(r, b.text, b.lang), b.intent, null, 'aug', b.lang);
      } else {
        final lang = r.nextBool() ? 'en' : 'ta';
        final a = _pick(r, [for (final x in pairable) if (x.lang == lang) x]);
        var b = _pick(r, [for (final x in pairable) if (x.lang == lang) x]);
        for (var tries = 0; b.intent == a.intent && tries < 10; tries++) {
          b = _pick(r, [for (final x in pairable) if (x.lang == lang) x]);
        }
        if (b.intent == a.intent) {
          q = a;
        } else {
          final joiner = lang == 'en' ? ' and ' : ', ';
          final first = a.text.replaceAll('?', '').trim();
          final text = '$first$joiner${b.text[0].toLowerCase()}${b.text.substring(1)}'.replaceAll('  ', ' ');
          // safety first; otherwise the order asked
          final (p, sec) = a.intent == QaIntent.isSafe
              ? (a.intent, b.intent)
              : b.intent == QaIntent.isSafe
              ? (b.intent, a.intent)
              : (a.intent, b.intent);
          q = _Q(text, p, sec, 'pair', lang);
        }
      }
      if (sealed.contains(_norm(q.text))) {
        sealedRefused++;
        continue;
      }
      final probe = classifyQuestion(q.text);
      if (probe.intent == q.intent) agree++;
      final lang = q.lang;
      final wantAnswers = lang == 'en' || tamilAnswers;
      final answerList = <Map<String, Object>>[];
      List<QaIntent> follow = const [];
      if (wantAnswers) {
        for (var st = 0; st < (lang == 'en' ? nStyles : 1); st++) {
          final a = answerQuestion(
            question: q.text,
            trace: trace,
            eventState: event,
            hazardDisplayNouns: _nouns,
            locale: lang,
            style: st,
            forceIntent: q.intent,
            forceSecondary: q.secondary,
          );
          if (a.usedFallback) {
            fallbacks++;
            for (final c in a.rejectedClaims) {
              final key = '${q.intent.wireName}${q.secondary == null ? '' : '+${q.secondary!.wireName}'} / $c';
              rejected.update(key, (v) => v + 1, ifAbsent: () => 1);
            }
            continue;
          }
          answers++;
          follow = a.followUps;
          answerList.add({'style': st, 'text': a.text, 'headline': a.headline});
        }
      }
      records++;
      perIntent.update(q.intent.wireName, (v) => v + 1, ifAbsent: () => 1);
      final rec = jsonEncode({
        'id': 's${s.toString().padLeft(5, '0')}-q$k',
        'situation_id': 's${s.toString().padLeft(5, '0')}',
        'split': isVal ? 'val' : 'train',
        'locale': lang,
        'question': q.text,
        'intent': q.intent.wireName,
        'secondary': q.secondary?.wireName,
        'source': q.source,
        'classifier_agrees': probe.intent == q.intent,
        'fact_sheet': sheet,
        'event_state': event.name,
        'trace': trace.toJson(),
        'answers': answerList,
        'follow_ups': [for (final f in follow) f.wireName],
        'answer_reviewed': lang == 'en',
      });
      if (isVal) {
        val.writeln(rec);
        nVal++;
      } else {
        train.writeln(rec);
        nTrain++;
      }
    }
  }
  train.close();
  val.close();

  stats
    ..['seed'] = seed
    ..['situations'] = nSit
    ..['records'] = records
    ..['train_records'] = nTrain
    ..['val_records'] = nVal
    ..['answers_written'] = answers
    ..['answers_dropped_because_the_verifier_rejected_them'] = fallbacks
    ..['rejected_claims'] = rejected
    ..['classifier_agrees_with_gold_share'] = records == 0 ? 0.0 : agree / records
    ..['sealed_test_questions_refused'] = sealedRefused
    ..['tamil_answers_written'] = tamilAnswers
    ..['by_intent'] = perIntent
    ..['by_travel_class'] = perClass
    ..['by_confidence_band'] = perBand;
  File('${out.path}/stats.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(stats));
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(stats));
}
