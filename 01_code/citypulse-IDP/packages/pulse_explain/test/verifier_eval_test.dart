/// Measures the verifier against `fixtures/verifier_cases.json` (PLAN.md task
/// M1.4, KNOWN_FLAWS F-05).
///
/// Two jobs:
///  1. **Gate.** Every `reject` case must fail `verify()` and every `accept`
///     case must pass it. A single false accept of an unsafe sentence fails
///     the suite.
///  2. **Measurement.** When the environment variable `VERIFIER_EVAL_OUT` names
///     a file, the per-category false-accept / false-reject counts are written
///     there as JSON (the `data/results/<date>-verifier*/result.json` files).
///
/// Honest limits, repeated in the result file: the cases were written by the
/// same people who wrote the checker (the set was written *before* the
/// hardening so the baseline is genuine), they are English and Tamil only, they
/// are not model output, and the Tamil lexicon needs a native-speaker review.
/// A clean result here is necessary, not sufficient.
library;

import 'dart:convert';
import 'dart:io';

import 'package:pulse_explain/pulse_explain.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final cases = (jsonDecode(
    File('test/fixtures/verifier_cases.json').readAsStringSync(),
  ) as List<Object?>).cast<Map<String, Object?>>();
  final trace = buildTrace();

  final byCategory = <String, Map<String, int>>{};
  final falseAccepts = <String>[];
  final falseRejects = <String>[];

  for (final c in cases) {
    final text = c['text']! as String;
    final expectReject = c['expect'] == 'reject';
    final category = c['category']! as String;
    final result = verify(
      text,
      trace,
      hazardDisplayNouns: testHazardDisplayNouns,
    );
    final stats = byCategory.putIfAbsent(
      category,
      () => {'n': 0, 'false_accept': 0, 'false_reject': 0},
    );
    stats['n'] = stats['n']! + 1;
    if (expectReject && result.passed) {
      stats['false_accept'] = stats['false_accept']! + 1;
      falseAccepts.add('${c['id']} [$category] $text');
    }
    if (!expectReject && !result.passed) {
      stats['false_reject'] = stats['false_reject']! + 1;
      falseRejects.add(
        '${c['id']} [$category] $text -> ${result.unsupportedClaims}',
      );
    }
  }

  final nReject = cases.where((c) => c['expect'] == 'reject').length;
  final nAccept = cases.length - nReject;

  final outPath = Platform.environment['VERIFIER_EVAL_OUT'];
  if (outPath != null && outPath.isNotEmpty) {
    File(outPath)
      ..createSync(recursive: true)
      ..writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'task': 'M1.4 verifier adversarial evaluation',
          'fixture': 'packages/pulse_explain/test/fixtures/verifier_cases.json',
          'trace': 'test/helpers.dart buildTrace() default',
          'n_cases': cases.length,
          'n_must_reject': nReject,
          'n_must_accept': nAccept,
          'false_accepts': falseAccepts.length,
          'false_accept_rate': nReject == 0 ? 0 : falseAccepts.length / nReject,
          'false_rejects': falseRejects.length,
          'false_reject_rate': nAccept == 0 ? 0 : falseRejects.length / nAccept,
          'by_category': byCategory,
          'false_accept_examples': falseAccepts,
          'false_reject_examples': falseRejects,
          'limits': [
            'Cases are authored by the checker authors. The set was written '
                'before the hardening, so the baseline is genuine '
                '(2026-10-02-verifier-baseline: 150 of 209 false accepts).',
            'The hardened lexicon was then extended once more after three '
                'residual false accepts ("no longer flooded", "the flood is '
                'over", "will not face any water") were seen on this same set. '
                'The post-fix result is therefore partly fitted to it; the '
                'honest generalisation test is third-party and model-generated '
                'text (Study 3).',
            'Not model output: Tier 1/2 rewriters have never run (F-06). The real '
                'false-accept rate on SLM text is unmeasured.',
            'Tamil coverage is a 25-sentence hand-written lexicon check; it needs '
                'a native-speaker review before any Tamil explanation ships.',
            '50 of the must-reject cases are templated cross-products and add '
                'volume, not diversity.',
          ],
        }),
      );
  }

  test('no unsafe or false sentence is accepted (zero false accepts)', () {
    expect(
      falseAccepts,
      isEmpty,
      reason:
          'verify() accepted ${falseAccepts.length} of $nReject sentences '
          'it must reject:\n${falseAccepts.join('\n')}',
    );
  });

  test('no honest sentence is rejected (zero false rejects)', () {
    expect(
      falseRejects,
      isEmpty,
      reason:
          'verify() rejected ${falseRejects.length} of $nAccept honest '
          'sentences:\n${falseRejects.join('\n')}',
    );
  });
}
