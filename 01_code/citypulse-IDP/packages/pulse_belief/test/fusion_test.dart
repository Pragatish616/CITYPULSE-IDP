import 'package:pulse_belief/pulse_belief.dart';
import 'package:test/test.dart';

void main() {
  final t0 = DateTime.utc(2026, 9, 13, 12);

  WeightedObservation obsAt({
    required String id,
    required int polarity,
    required double distanceM,
    required Duration age,
    double sourceReliability = 0.9,
  }) {
    return WeightedObservation(
      id: id,
      polarity: polarity,
      distanceM: distanceM,
      observedAt: t0.subtract(age),
      sourceReliability: sourceReliability,
    );
  }

  group('fuse — empty and no-contribution cases', () {
    test('no observations: posterior equals the prior exactly', () {
      final belief = fuse(
        observations: [],
        priorLogOdds: -1.5,
        t: t0,
        decayTauSeconds: 3600,
      );
      expect(belief.posteriorLogOdds, equals(-1.5));
      expect(belief.nEff, equals(0.0));
      expect(belief.newestObservationAt, isNull);
      expect(belief.contributingObservationIds, isEmpty);
    });

    test('an observation beyond the kernel cutoff contributes nothing', () {
      final far = obsAt(
        id: 'far',
        polarity: 1,
        distanceM: 10000,
        age: Duration.zero,
      );
      final belief = fuse(
        observations: [far],
        priorLogOdds: 0,
        t: t0,
        decayTauSeconds: 3600,
      );
      expect(belief.posteriorLogOdds, equals(0.0));
      expect(belief.nEff, equals(0.0));
      expect(belief.newestObservationAt, isNull);
      expect(belief.contributingObservationIds, isEmpty);
    });
  });

  group('fuse — decay monotonicity', () {
    test('an older observation of the same weight contributes less evidence '
        'and shifts the posterior less, as age increases', () {
      const decayTau = 3600.0;
      final ages = [
        Duration.zero,
        const Duration(minutes: 30),
        const Duration(hours: 1),
        const Duration(hours: 2),
      ];

      final nEffs = <double>[];
      final shifts = <double>[];
      for (final age in ages) {
        final obs = obsAt(id: 'o', polarity: 1, distanceM: 0, age: age);
        final belief = fuse(
          observations: [obs],
          priorLogOdds: 0,
          t: t0,
          decayTauSeconds: decayTau,
        );
        nEffs.add(belief.nEff);
        shifts.add(belief.posteriorLogOdds - belief.priorLogOdds);
      }

      for (var i = 1; i < ages.length; i++) {
        expect(
          nEffs[i],
          lessThan(nEffs[i - 1]),
          reason: 'n_eff must strictly decrease with age',
        );
        expect(
          shifts[i],
          lessThan(shifts[i - 1]),
          reason:
              'the posterior shift must strictly decrease with age '
              '(converging to the prior)',
        );
      }
    });
  });

  group('fuse — opposing observations cancel', () {
    test(
      'a present (+1) and an absent (-1) report of equal weight cancel in the '
      'posterior, but both still count toward n_eff',
      () {
        final present = obsAt(
          id: 'present',
          polarity: 1,
          distanceM: 0,
          age: const Duration(minutes: 5),
        );
        final absent = obsAt(
          id: 'absent',
          polarity: -1,
          distanceM: 0,
          age: const Duration(minutes: 5),
        );

        final belief = fuse(
          observations: [present, absent],
          priorLogOdds: -0.8,
          t: t0,
          decayTauSeconds: 3600,
        );

        expect(belief.posteriorLogOdds, closeTo(-0.8, 1e-9));

        final soloBelief = fuse(
          observations: [present],
          priorLogOdds: -0.8,
          t: t0,
          decayTauSeconds: 3600,
        );
        // n_eff is unsigned evidence weight -- both observations count, so
        // fusing both must yield double the n_eff of fusing just one.
        expect(belief.nEff, closeTo(2 * soloBelief.nEff, 1e-9));
      },
    );
  });

  group('fuse — n_eff shrinking widens the pessimistic band', () {
    test('a single stale crowd report has lower n_eff than a fresh one, and '
        'feeding both n_eff values into pessimistic() at the same p-mean shows '
        'the stale report widens the band', () {
      const decayTau = 7200.0; // flood T_c, config/hazard_classes.yaml
      const crowdReliability =
          0.60; // config/hazard_classes.yaml source_reliability.crowd

      final fresh = obsAt(
        id: 'fresh',
        polarity: 1,
        distanceM: 0,
        age: Duration.zero,
        sourceReliability: crowdReliability,
      );
      final stale = obsAt(
        id: 'stale',
        polarity: 1,
        distanceM: 0,
        age: const Duration(hours: 2),
        sourceReliability: crowdReliability,
      );

      final freshBelief = fuse(
        observations: [fresh],
        priorLogOdds: 0,
        t: t0,
        decayTauSeconds: decayTau,
      );
      final staleBelief = fuse(
        observations: [stale],
        priorLogOdds: 0,
        t: t0,
        decayTauSeconds: decayTau,
      );

      expect(staleBelief.nEff, lessThan(freshBelief.nEff));

      const sharedPMean = 0.5; // hold p-mean fixed to isolate the n_eff effect
      // z chosen small enough that neither call hits the min{1,...} clamp --
      // that clamp is covered separately in pessimistic_test.dart, and
      // letting both sides saturate here would hide the n_eff effect this
      // test exists to demonstrate.
      const z = 0.5;
      final tighterBand = pessimistic(
        pMean: sharedPMean,
        nEff: freshBelief.nEff,
        z: z,
      );
      final widerBand = pessimistic(
        pMean: sharedPMean,
        nEff: staleBelief.nEff,
        z: z,
      );
      expect(widerBand, greaterThan(tighterBand));
      expect(widerBand, greaterThan(sharedPMean));
    });
  });

  group('fuse — bookkeeping', () {
    test(
      'newestObservationAt tracks the maximum observed_at, not input order',
      () {
        final older = obsAt(
          id: 'older',
          polarity: 1,
          distanceM: 0,
          age: const Duration(hours: 2),
        );
        final newer = obsAt(
          id: 'newer',
          polarity: 1,
          distanceM: 0,
          age: const Duration(minutes: 1),
        );
        final belief = fuse(
          observations: [older, newer],
          priorLogOdds: 0,
          t: t0,
          decayTauSeconds: 3600,
        );
        expect(belief.newestObservationAt, equals(newer.observedAt));
      },
    );

    test('contributingObservationIds lists every non-zero-weight observation, '
        'in input order', () {
      final a = obsAt(id: 'a', polarity: 1, distanceM: 0, age: Duration.zero);
      final farAway = obsAt(
        id: 'excluded',
        polarity: 1,
        distanceM: 10000,
        age: Duration.zero,
      );
      final b = obsAt(
        id: 'b',
        polarity: -1,
        distanceM: 10,
        age: const Duration(minutes: 1),
      );
      final belief = fuse(
        observations: [a, farAway, b],
        priorLogOdds: 0,
        t: t0,
        decayTauSeconds: 3600,
      );
      expect(belief.contributingObservationIds, equals(['a', 'b']));
    });

    test('rejects an observation timestamped after the query clock t', () {
      final future = WeightedObservation(
        id: 'future',
        polarity: 1,
        distanceM: 0,
        observedAt: t0.add(const Duration(minutes: 1)),
        sourceReliability: 0.9,
      );
      expect(
        () => fuse(
          observations: [future],
          priorLogOdds: 0,
          t: t0,
          decayTauSeconds: 3600,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('WeightedObservation validation', () {
    test('rejects a polarity other than +1 or -1', () {
      expect(
        () => WeightedObservation(
          id: 'x',
          polarity: 0,
          distanceM: 0,
          observedAt: t0,
          sourceReliability: 0.9,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects a negative distance', () {
      expect(
        () => WeightedObservation(
          id: 'x',
          polarity: 1,
          distanceM: -1,
          observedAt: t0,
          sourceReliability: 0.9,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects a source reliability outside (0, 1)', () {
      expect(
        () => WeightedObservation(
          id: 'x',
          polarity: 1,
          distanceM: 0,
          observedAt: t0,
          sourceReliability: 1,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => WeightedObservation(
          id: 'x',
          polarity: 1,
          distanceM: 0,
          observedAt: t0,
          sourceReliability: 0,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects NaN distanceM or sourceReliability -- regression for a '
        '2026-09 security review finding: NaN silently passed the old '
        'assert-based checks and propagated through fuse/pessimistic/edgeCost '
        'as NaN, always in the less-cautious direction', () {
      expect(
        () => WeightedObservation(
          id: 'x',
          polarity: 1,
          distanceM: double.nan,
          observedAt: t0,
          sourceReliability: 0.9,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => WeightedObservation(
          id: 'x',
          polarity: 1,
          distanceM: 0,
          observedAt: t0,
          sourceReliability: double.nan,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
