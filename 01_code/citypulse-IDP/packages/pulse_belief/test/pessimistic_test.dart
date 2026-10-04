import 'dart:math' as math;

import 'package:pulse_belief/pulse_belief.dart';
import 'package:test/test.dart';

void main() {
  group('pessimistic', () {
    test('z = 0 reduces p-tilde to p-mean exactly, regardless of n_eff', () {
      expect(pessimistic(pMean: 0.37, nEff: 5, z: 0), equals(0.37));
      expect(pessimistic(pMean: 0.37, nEff: 0, z: 0), equals(0.37));
      expect(pessimistic(pMean: 0.37, nEff: 1000000, z: 0), equals(0.37));
    });

    test('n_eff -> 0 widens the band: lower evidence yields a higher p-tilde '
        'at the same p-mean and z', () {
      const pMean = 0.6;
      const z = 1.0;
      final wideBand = pessimistic(pMean: pMean, nEff: 0.001, z: z);
      final narrowBand = pessimistic(pMean: pMean, nEff: 50, z: z);
      expect(wideBand, greaterThan(narrowBand));
      expect(wideBand, greaterThan(pMean));
    });

    test('a single stale, fresh-ish report still pushes p-tilde above p-mean '
        'whenever z > 0 and there is any uncertainty (0 < p-mean < 1)', () {
      // "Stale" here means already decayed some (n_eff well below its
      // ceiling), which is exactly the regime that widens the band.
      const pMean = 0.55;
      const nEffAfterDecay = 0.4;
      final pTilde = pessimistic(pMean: pMean, nEff: nEffAfterDecay, z: 1.28);
      expect(pTilde, greaterThan(pMean));
    });

    test(
      'p-tilde <= 1 always: the clamp actually engages for the emergency class '
      '(z = 2.0) with a single fresh report at p-mean ~= 0.5 — this must be '
      'a case where the raw, unclamped formula would exceed 1',
      () {
        const pMean = 0.5;
        const nEff = 1.0; // one fresh, moderately-weighted report
        const z = 2.0; // config/hazard_classes.yaml: user_classes.emergency.z

        final rawUnclamped =
            pMean + z * math.sqrt(pMean * (1 - pMean) / (nEff + 1));
        // Confirm the test setup actually exercises the clamp, not just its
        // presence in the source.
        expect(rawUnclamped, greaterThan(1.0));

        final pTilde = pessimistic(pMean: pMean, nEff: nEff, z: z);
        expect(pTilde, equals(1.0));
      },
    );

    test(
      'never exceeds 1 across a sweep of sparse-evidence, high-z configs',
      () {
        for (final pMean in [0.1, 0.3, 0.5, 0.7, 0.9]) {
          for (final nEff in [0.0, 0.1, 0.5, 1.0, 2.0]) {
            final pTilde = pessimistic(pMean: pMean, nEff: nEff, z: 2);
            expect(pTilde, lessThanOrEqualTo(1.0));
          }
        }
      },
    );

    test('rejects out-of-range inputs', () {
      expect(
        () => pessimistic(pMean: -0.1, nEff: 1, z: 1),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => pessimistic(pMean: 1.1, nEff: 1, z: 1),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => pessimistic(pMean: 0.5, nEff: -1, z: 1),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => pessimistic(pMean: 0.5, nEff: 1, z: -1),
        throwsA(isA<ArgumentError>()),
      );
    });

    test(
      'rejects NaN in any argument -- regression for a 2026-09 security '
      'review finding: NaN silently satisfied the old assert-based checks '
      'and produced a NaN p_pessimistic (the opposite of ADR-002 caution)',
      () {
        expect(
          () => pessimistic(pMean: double.nan, nEff: 1, z: 1),
          throwsA(isA<ArgumentError>()),
        );
        expect(
          () => pessimistic(pMean: 0.5, nEff: double.nan, z: 1),
          throwsA(isA<ArgumentError>()),
        );
        expect(
          () => pessimistic(pMean: 0.5, nEff: 1, z: double.nan),
          throwsA(isA<ArgumentError>()),
        );
      },
    );
  });
}
