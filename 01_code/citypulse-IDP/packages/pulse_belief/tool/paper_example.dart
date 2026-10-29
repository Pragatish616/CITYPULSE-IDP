// The worked example in the paper (v3, Section III-B): the routing index on an edge with prior 0.05 as fresh crowd reports
// (reliability 0.6) arrive, under the legacy Wald index and the Beta index the router uses (ADR-015). Run:
//   dart run tool/paper_example.dart
import 'dart:math' as math;

import 'package:pulse_belief/pulse_belief.dart';

void main() {
  const p0 = 0.05;
  final prior = math.log(p0 / (1 - p0));
  final t = DateTime.utc(2015, 12, 2);
  for (final z in [1.28, 2.0]) {
    final wald = <String>[];
    final beta = <String>[];
    for (var k = 0; k <= 3; k++) {
      final obs = [
        for (var i = 0; i < k; i++)
          WeightedObservation(id: 'r$i', polarity: 1, distanceM: 0, observedAt: t, sourceReliability: 0.6),
      ];
      final b = fuseBeta(observations: obs, priorLogOdds: prior, t: t, decayTauSeconds: 7200);
      beta.add(pessimisticBeta(belief: b, z: z).toStringAsFixed(3));
      final f = fuse(observations: obs, priorLogOdds: prior, t: t, decayTauSeconds: 7200);
      wald.add(pessimistic(pMean: f.pMean, nEff: f.nEff, z: z).toStringAsFixed(3));
    }
    print('z=$z wald=${wald.join(' ')} beta=${beta.join(' ')}');
  }
}
