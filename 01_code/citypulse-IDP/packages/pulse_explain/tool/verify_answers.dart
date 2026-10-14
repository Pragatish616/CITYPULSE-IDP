// Runs the verifier over text written by something else (a fine-tuned model), so that its answers are judged by
// the same rules as every other tier (ADR-004, PREREGISTRATION_QA.md addendum 1).
//
//   dart run tool/verify_answers.dart INPUT.jsonl OUTPUT.jsonl
//
// Each input line: {"id": ..., "trace": <DecisionTrace JSON>, "text": "..."}. Each output line adds
// {"passed": bool, "claims": [...]} . Nothing is repaired or filtered here.
import 'dart:convert';
import 'dart:io';

import 'package:pulse_explain/pulse_explain.dart';
import 'package:pulse_router/pulse_router.dart';

const _nouns = {
  'flood': 'flooding',
  'waterlogging': 'waterlogging',
  'debris': 'debris on the road',
  'accident': 'an accident',
  'closure': 'a road closure',
  'heat': 'extreme heat',
  'aqi': 'poor air quality',
};

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln('usage: dart run tool/verify_answers.dart INPUT.jsonl OUTPUT.jsonl');
    exit(2);
  }
  final out = File(args[1]).openWrite();
  var n = 0, ok = 0;
  for (final line in File(args[0]).readAsLinesSync()) {
    if (line.trim().isEmpty) continue;
    final rec = jsonDecode(line) as Map<String, dynamic>;
    final trace = DecisionTrace.fromJson((rec['trace'] as Map).cast<String, Object?>());
    final v = verify(rec['text'] as String, trace, hazardDisplayNouns: _nouns);
    n++;
    if (v.passed) ok++;
    out.writeln(jsonEncode({'id': rec['id'], 'passed': v.passed, 'claims': v.unsupportedClaims}));
  }
  out.close();
  stdout.writeln(jsonEncode({'checked': n, 'passed': ok}));
}
