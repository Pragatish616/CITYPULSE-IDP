// Runs the route-question model through the app's own labeler class (app/lib/src/explain/llama_question_labeler.dart, on llamadart)
// over the 300 validation questions run1 was evaluated on, and writes the result. PREREGISTRATION_QA.md addendum 5: intent accuracy must
// be at least 0.977 (within 2 points of the adapter's 0.9967). Whatever it is, it is reported.
//
//   dart run bin/check.dart <model.gguf> <eval_rows_u.json> <result.json>
import 'dart:convert';
import 'dart:io';

import '../../../app/lib/src/explain/llama_question_labeler.dart';
import 'package:pulse_explain/pulse_explain.dart';

Future<void> main(List<String> args) async {
  if (args.length != 3 && args.length != 4) {
    stderr.writeln('usage: dart run bin/check.dart <model.gguf> <eval_rows_u.json> <result.json> [free]');
    exit(64);
  }
  final gguf = args[0];
  final rows = (jsonDecode(File(args[1]).readAsStringSync()) as List).cast<Map<String, dynamic>>();
  // 'free' as a fourth argument turns the label grammar off (C7 comparison).
  final constrained = !(args.length == 4 && args[3] == 'free');
  final labeler = LlamaQuestionLabeler(locate: () async => gguf, constrained: constrained);
  var ok = 0, secOk = 0, bad = 0;
  final byLocale = <String, List<int>>{'en': [0, 0], 'ta': [0, 0]};
  final ms = <int>[];
  final wrong = <Map<String, Object?>>[];
  for (final r in rows) {
    final clock = Stopwatch()..start();
    final reply = await labeler.reply(r['question'] as String);
    clock.stop();
    ms.add(clock.elapsedMilliseconds);
    final label = reply == null ? null : parseModelLabel(reply);
    final hit = label != null && label.intent.wireName == r['intent'];
    if (hit) ok++;
    if (label == null) bad++;
    if (label?.secondary?.wireName == r['secondary']) secOk++;
    final loc = byLocale[r['locale'] as String]!;
    loc[1]++;
    if (hit) loc[0]++;
    if (!hit && wrong.length < 12) {
      wrong.add({'q': r['question'], 'gold': r['intent'], 'model': label?.intent.wireName, 'reply': reply});
    }
  }
  final status = labeler.status;
  await labeler.dispose();
  ms.sort();
  final n = rows.length;
  const bar = 0.9766666666666667;
  final result = {
    'gguf': File(gguf).uri.pathSegments.last,
    'runtime': 'llamadart 0.12.2 via the app labeler class, CPU, Windows (dart run)',
    'grammar_constrained': constrained,
    'labeler_status': status,
    'n': n,
    'intent_accuracy': ok / n,
    'secondary_exact': secOk / n,
    'unparseable': bad / n,
    'by_locale': {for (final e in byLocale.entries) e.key: e.value[0] / (e.value[1] == 0 ? 1 : e.value[1])},
    'bar': bar,
    'meets_bar': ok / n >= bar,
    'ms_p50': ms[n ~/ 2],
    'ms_p95': ms[(n * 0.95).floor()],
    'examples_wrong': wrong,
  };
  File(args[2]).writeAsStringSync(const JsonEncoder.withIndent(' ').convert(result));
  stdout.writeln(const JsonEncoder.withIndent(' ').convert(Map.of(result)..remove('examples_wrong')));
  exit(result['meets_bar'] == true ? 0 : 1);
}
