// Writes golden vectors for the Python replica of the Beta belief
// (scripts/study_common.py: fuse_beta_py / pessimistic_beta_py), computed by the
// real Dart code, so the replica is checked against the implementation and not
// against its own description. Run from packages/pulse_belief:
//   dart run tool/golden_vectors.dart ../../scripts/tests/fixtures/beta_golden.json
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:pulse_belief/pulse_belief.dart';

void main(List<String> args) {
  final out = args.isEmpty ? 'beta_golden.json' : args.first;
  final t = DateTime.utc(2015, 12, 2, 12);
  final rng = math.Random(20261002);
  final cases = <Map<String, Object?>>[];

  for (final p0 in [0.02, 0.05, 0.12, 0.25, 0.45]) {
    for (final tau in [900.0, 7200.0, 14400.0]) {
      for (var trial = 0; trial < 6; trial++) {
        final n = trial == 0 ? 0 : 1 + rng.nextInt(5);
        final reports = <Map<String, Object?>>[];
        for (var i = 0; i < n; i++) {
          reports.add({
            'polarity': rng.nextInt(4) == 0 ? -1 : 1,
            'alpha': [0.6, 0.7, 0.9, 0.92, 0.97][rng.nextInt(5)],
            'distance_m': rng.nextInt(4) == 0 ? 280.0 : rng.nextDouble() * 90,
            'age_s': rng.nextInt(30 * 3600).toDouble(),
          });
        }
        final belief = fuseBeta(
          observations: [
            for (var i = 0; i < reports.length; i++)
              WeightedObservation(
                id: 'o$i',
                polarity: reports[i]['polarity']! as int,
                distanceM: reports[i]['distance_m']! as double,
                observedAt: t.subtract(
                  Duration(
                    microseconds: ((reports[i]['age_s']! as double) * 1e6)
                        .round(),
                  ),
                ),
                sourceReliability: reports[i]['alpha']! as double,
              ),
          ],
          priorLogOdds: math.log(p0 / (1 - p0)),
          t: t,
          decayTauSeconds: tau,
        );
        cases.add({
          'p0': p0,
          'tau_s': tau,
          'reports': reports,
          'alpha': belief.alpha,
          'beta': belief.beta,
          'p_mean': belief.pMean,
          'n_eff': belief.nEff,
          'net_evidence': belief.netEvidence,
          'p_tilde': {
            '0': pessimisticBeta(belief: belief, z: 0),
            '1.28': pessimisticBeta(belief: belief, z: 1.28),
            '2': pessimisticBeta(belief: belief, z: 2),
          },
        });
      }
    }
  }
  File(out)
    ..createSync(recursive: true)
    ..writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert({
        'generator': 'packages/pulse_belief/tool/golden_vectors.dart',
        'params': {'prior_strength': 2.0, 'evidence_scale': 2.0, 'reference_reliability': 0.97},
        'kernel': {'bandwidth_m': 75, 'cutoff_m': 300},
        'cases': cases,
      }),
    );
  stdout.writeln('wrote ${cases.length} cases to $out');
}
