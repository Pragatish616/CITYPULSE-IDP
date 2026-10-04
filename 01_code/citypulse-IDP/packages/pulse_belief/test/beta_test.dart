import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:pulse_belief/pulse_belief.dart';
import 'package:test/test.dart';

void main() {
  final t0 = DateTime.utc(2026, 9, 14, 12);
  const crowd = 0.60;
  const sensor = 0.97;

  WeightedObservation obs(
    String id, {
    required double alpha,
    int polarity = 1,
    Duration age = Duration.zero,
    double distanceM = 0,
  }) => WeightedObservation(
    id: id,
    polarity: polarity,
    distanceM: distanceM,
    observedAt: t0.subtract(age),
    sourceReliability: alpha,
  );

  double ptilde({
    required double p0,
    required List<WeightedObservation> reports,
    required double z,
    double tau = 7200,
  }) {
    final belief = fuseBeta(
      observations: reports,
      priorLogOdds: math.log(p0 / (1 - p0)),
      t: t0,
      decayTauSeconds: tau,
    );
    return pessimisticBeta(belief: belief, z: z);
  }

  group('Beta special functions match SciPy 1.18', () {
    final fixture =
        jsonDecode(File('test/fixtures/beta_scipy.json').readAsStringSync())
            as Map<String, Object?>;

    test('betaQuantile reproduces scipy.stats.beta.ppf on 360 (a, b, q) '
        'points, including a < 1 priors', () {
      var worst = 0.0;
      for (final c in (fixture['ppf']! as List<Object?>)
          .cast<Map<String, Object?>>()) {
        final a = (c['a']! as num).toDouble();
        final b = (c['b']! as num).toDouble();
        final q = (c['q']! as num).toDouble();
        final expected = (c['ppf']! as num).toDouble();
        final got = betaQuantile(q, a, b);
        if (expected < 1e-9 || expected > 1 - 1e-9) {
          // The quantile is within 1e-9 of 0 or 1 (only possible when both
          // a and b are far below the prior strength the router uses). Near
          // 1 a double cannot tell 1 - 1e-14 from 1 - 1e-15, so the
          // probability-space check below would measure rounding, not the
          // algorithm. Require it to land on the right boundary.
          expect(got, closeTo(expected, 1e-9), reason: 'a=$a b=$b q=$q');
          continue;
        }
        // Correct if it matches SciPy in x (to 1e-12) or in probability (to
        // 1e-9). Either is enough: where the density is steep a 1e-15 error
        // in x is a much larger error in q, and where it is flat the reverse.
        final qError = (betaCdf(got, a, b) - q).abs();
        final xError = (got - expected).abs();
        worst = math.max(worst, math.min(xError / 1e3, qError));
        expect(
          xError < 1e-12 || qError < 1e-9,
          isTrue,
          reason: 'a=$a b=$b q=$q: got $got, scipy $expected, '
              'x error $xError, cdf error $qError',
        );
      }
      expect(worst, lessThan(1e-9));
    });

    test('betaCdf reproduces scipy.stats.beta.cdf', () {
      for (final c in (fixture['cdf']! as List<Object?>)
          .cast<Map<String, Object?>>()) {
        final a = (c['a']! as num).toDouble();
        final b = (c['b']! as num).toDouble();
        final x = (c['x']! as num).toDouble();
        expect(
          betaCdf(x, a, b),
          closeTo((c['cdf']! as num).toDouble(), 1e-10),
          reason: 'a=$a b=$b x=$x',
        );
      }
    });

    test('normalCdf is accurate to 2e-7 at the z values the classes use', () {
      expect(normalCdf(0), closeTo(0.5, 1e-9));
      expect(normalCdf(1.28), closeTo(0.8997274, 2e-7));
      expect(normalCdf(2), closeTo(0.9772499, 2e-7));
      expect(normalCdf(-1.28), closeTo(1 - 0.8997274, 2e-7));
    });

    test('rejects invalid input instead of returning NaN', () {
      expect(() => betaQuantile(0.5, 0, 1), throwsArgumentError);
      expect(() => betaQuantile(0.5, 1, -2), throwsArgumentError);
      expect(() => betaQuantile(1.5, 1, 1), throwsArgumentError);
      expect(() => betaQuantile(double.nan, 1, 1), throwsArgumentError);
      expect(() => betaCdf(double.nan, 1, 1), throwsArgumentError);
      expect(() => normalCdf(double.nan), throwsArgumentError);
    });
  });

  group('fuseBeta / pessimisticBeta', () {
    test('no evidence: p̃ at z = 0 is exactly the prior (the commuter '
        'default is unchanged on prior-only edges)', () {
      for (final p0 in [0.02, 0.05, 0.12, 0.25, 0.45]) {
        expect(
          ptilde(p0: p0, reports: const [], z: 0),
          closeTo(p0, 1e-12),
        );
      }
    });

    test('the F-01 regression: at p0 = 0.05 and crowd α = 0.6, p̃ rises with '
        'every extra report at z = 1.28 and z = 2 (the Wald index went '
        '0.329 -> 0.309 -> 0.333 -> 0.380 and 0.486 -> 0.441 -> ...)', () {
      for (final z in [1.28, 2.0]) {
        final series = [
          for (var k = 0; k <= 4; k++)
            ptilde(
              p0: 0.05,
              reports: [for (var i = 0; i < k; i++) obs('c$i', alpha: crowd)],
              z: z,
            ),
        ];
        for (var k = 1; k < series.length; k++) {
          expect(
            series[k],
            greaterThan(series[k - 1]),
            reason: 'z=$z: p̃ must increase with report $k; series=$series',
          );
        }
      }
    });

    test('PROPERTY: a positive report never lowers p̃, for every prior, '
        'reliability in (0.5, 1), z, starting evidence and age', () {
      final priors = [0.005, 0.02, 0.05, 0.12, 0.25, 0.45, 0.8];
      final alphas = [0.51, 0.55, 0.6, 0.7, 0.8, 0.9, 0.97, 0.999];
      final zs = [0.0, 0.5, 1.0, 1.28, 2.0, 3.0];
      final startingStates = <List<WeightedObservation>>[
        const [],
        [obs('s1', alpha: crowd)],
        [obs('s2', alpha: sensor), obs('s3', alpha: crowd)],
        [obs('n1', alpha: 0.9, polarity: -1)],
        [obs('n2', alpha: sensor, polarity: -1), obs('n3', alpha: crowd)],
        [obs('old', alpha: 0.9, age: const Duration(hours: 3))],
      ];
      var checked = 0;
      for (final p0 in priors) {
        for (final z in zs) {
          for (final start in startingStates) {
            final before = ptilde(p0: p0, reports: start, z: z);
            for (final alpha in alphas) {
              for (final age in [
                Duration.zero,
                const Duration(minutes: 10),
                const Duration(hours: 1),
              ]) {
                final after = ptilde(
                  p0: p0,
                  reports: [...start, obs('new', alpha: alpha, age: age)],
                  z: z,
                );
                expect(
                  after,
                  greaterThanOrEqualTo(before - 1e-12),
                  reason:
                      'p0=$p0 z=$z α=$alpha age=$age start=${start.length}: '
                      '$before -> $after',
                );
                checked++;
              }
            }
          }
        }
      }
      expect(checked, greaterThan(5000));
    });

    test('PROPERTY: a negative report never raises p̃', () {
      for (final p0 in [0.02, 0.12, 0.45]) {
        for (final z in [0.0, 1.28, 2.0]) {
          for (final alpha in [0.55, 0.7, 0.97]) {
            final before = ptilde(
              p0: p0,
              reports: [obs('p', alpha: 0.9)],
              z: z,
            );
            final after = ptilde(
              p0: p0,
              reports: [
                obs('p', alpha: 0.9),
                obs('n', alpha: alpha, polarity: -1),
              ],
              z: z,
            );
            expect(after, lessThanOrEqualTo(before + 1e-12));
          }
        }
      }
    });

    test('PROPERTY: ageing a positive report moves p̃ monotonically back '
        'to the prior (it never rises as the report gets older)', () {
      for (final alpha in [0.6, 0.7, 0.9, 0.97]) {
        for (final z in [0.0, 1.28, 2.0]) {
          double? previous;
          for (final hours in [0, 1, 2, 4, 8, 24, 72]) {
            final v = ptilde(
              p0: 0.05,
              reports: [obs('r', alpha: alpha, age: Duration(hours: hours))],
              z: z,
            );
            if (previous != null) {
              expect(
                v,
                lessThanOrEqualTo(previous + 1e-12),
                reason: 'α=$alpha z=$z after ${hours}h: $previous -> $v',
              );
            }
            previous = v;
          }
          // Long after the report it is the prior's own quantile again.
          expect(
            previous,
            closeTo(ptilde(p0: 0.05, reports: const [], z: z), 1e-6),
          );
        }
      }
    });

    test('PROPERTY: p̃ is in [p̄, 1] and p̃ is non-decreasing in z', () {
      for (final p0 in [0.02, 0.25, 0.45]) {
        for (final k in [0, 1, 3]) {
          final reports = [for (var i = 0; i < k; i++) obs('r$i', alpha: 0.7)];
          final belief = fuseBeta(
            observations: reports,
            priorLogOdds: math.log(p0 / (1 - p0)),
            t: t0,
            decayTauSeconds: 7200,
          );
          var previous = belief.pMean;
          for (final z in [0.0, 0.5, 1.0, 1.28, 1.64, 2.0, 3.0]) {
            final v = pessimisticBeta(belief: belief, z: z);
            expect(v, greaterThanOrEqualTo(belief.pMean - 1e-12));
            expect(v, lessThanOrEqualTo(1.0));
            expect(v, greaterThanOrEqualTo(previous - 1e-12));
            previous = v;
          }
        }
      }
    });

    test('F-12: opposing reports cancel instead of reading as certainty', () {
      final belief = fuseBeta(
        observations: [
          for (var i = 0; i < 5; i++) obs('p$i', alpha: 0.9),
          for (var i = 0; i < 5; i++) obs('n$i', alpha: 0.9, polarity: -1),
        ],
        priorLogOdds: math.log(0.12 / 0.88),
        t: t0,
        decayTauSeconds: 7200,
      );
      expect(belief.netEvidence, closeTo(0, 1e-12));
      expect(belief.nEff, closeTo(0, 1e-12));
      expect(belief.pMean, closeTo(0.12, 1e-12));
      // Same as having no reports at all, at every z.
      for (final z in [0.0, 1.28, 2.0]) {
        expect(
          pessimisticBeta(belief: belief, z: z),
          closeTo(ptilde(p0: 0.12, reports: const [], z: z), 1e-12),
        );
      }
    });

    test('F-12: n_eff is reliability-weighted -- three crowd reports are '
        'about a third of one sensor report, not three', () {
      double neff(List<WeightedObservation> r) => fuseBeta(
        observations: r,
        priorLogOdds: -2,
        t: t0,
        decayTauSeconds: 7200,
      ).nEff;
      final three = neff([for (var i = 0; i < 3; i++) obs('c$i', alpha: crowd)]);
      final one = neff([obs('s', alpha: sensor)]);
      expect(three, lessThan(0.5));
      expect(one, closeTo(1.0, 1e-9));
      expect(three, lessThan(one));
    });

    test('F-12: the index does not saturate to 1 on a high-prior edge at '
        'z = 2 (the Wald index was 1.0 on all 8,759 prior-only edges)', () {
      for (final p0 in [0.25, 0.45]) {
        final v = ptilde(p0: p0, reports: const [], z: 2);
        expect(v, lessThan(1.0), reason: 'p0=$p0 -> $v');
        expect(v, greaterThan(p0));
      }
    });

    test('a strong fresh report on a low-prior edge raises the mean a lot '
        'and the z = 2 index more', () {
      final belief = fuseBeta(
        observations: [obs('s', alpha: sensor)],
        priorLogOdds: math.log(0.05 / 0.95),
        t: t0,
        decayTauSeconds: 7200,
      );
      expect(belief.pMean, greaterThan(0.3));
      expect(
        pessimisticBeta(belief: belief, z: 2),
        greaterThan(belief.pMean),
      );
    });

    test('beyond the spatial kernel cutoff an observation contributes '
        'nothing', () {
      final belief = fuseBeta(
        observations: [obs('far', alpha: sensor, distanceM: 301)],
        priorLogOdds: -2,
        t: t0,
        decayTauSeconds: 7200,
      );
      expect(belief.nEff, equals(0));
      expect(belief.newestObservationAt, isNull);
      expect(belief.contributingObservationIds, isEmpty);
    });

    test('a future-dated observation is rejected with a real check', () {
      expect(
        () => fuseBeta(
          observations: [obs('f', alpha: 0.9, age: const Duration(hours: -1))],
          priorLogOdds: -2,
          t: t0,
          decayTauSeconds: 7200,
        ),
        throwsArgumentError,
      );
    });

    test('NaN / invalid inputs are rejected, never propagated', () {
      expect(
        () => fuseBeta(
          observations: const [],
          priorLogOdds: double.nan,
          t: t0,
          decayTauSeconds: 7200,
        ),
        throwsArgumentError,
      );
      expect(
        () => fuseBeta(
          observations: const [],
          priorLogOdds: -2,
          t: t0,
          decayTauSeconds: 0,
        ),
        throwsArgumentError,
      );
      final belief = fuseBeta(
        observations: const [],
        priorLogOdds: -2,
        t: t0,
        decayTauSeconds: 7200,
      );
      expect(
        () => pessimisticBeta(belief: belief, z: double.nan),
        throwsArgumentError,
      );
      expect(
        () => pessimisticBeta(belief: belief, z: -1),
        throwsArgumentError,
      );
      expect(() => BeliefParams(priorStrength: 0), throwsArgumentError);
      expect(
        () => BeliefParams(referenceReliability: 0.4),
        throwsArgumentError,
      );
    });

    test('reliabilityWeight: sensor = 1, crowd small, α ≤ 0.5 carries '
        'nothing', () {
      expect(reliabilityWeight(0.97, 0.97), closeTo(1, 1e-12));
      expect(reliabilityWeight(0.99, 0.97), equals(1)); // capped
      expect(reliabilityWeight(0.6, 0.97), closeTo(0.1166, 1e-3));
      expect(reliabilityWeight(0.5, 0.97), equals(0));
      expect(reliabilityWeight(0.3, 0.97), equals(0));
      expect(() => reliabilityWeight(1, 0.97), throwsArgumentError);
    });
  });
}
