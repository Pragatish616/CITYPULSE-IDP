// ADR-021: the route advisor is a transparent scoring model. These tests pin its behaviour, not any
// claim about real-world accuracy (there is no outcome data to check it against).
import 'package:pulse_router/pulse_router.dart';
import 'package:test/test.dart';

RouteFacts _facts({
  double p = 0,
  double ratio = 0,
  ConfidenceBand band = ConfidenceBand.high,
  int gaps = 0,
  UserClass userClass = UserClass.commuter,
  EventState event = EventState.active,
  int blocked = 0,
  List<CandidateFacts> candidates = const [],
}) => RouteFacts(
  worstEdgeP: p,
  hazardPenaltyRatio: ratio,
  confidence: band,
  dataGapCount: gaps,
  userClass: userClass,
  eventState: event,
  blockedAlternatives: blocked,
  candidates: candidates,
);

double _sum(Iterable<double> v) => v.fold(0, (a, b) => a + b);

void main() {
  group('probabilities', () {
    test('risk and action each sum to 1, for a spread of inputs', () {
      for (final p in [0.0, 0.1, 0.3, 0.6, 0.95, 1.0]) {
        for (final band in ConfidenceBand.values) {
          for (final c in UserClass.values) {
            final a = advise(
              _facts(p: p, ratio: p / 2, band: band, userClass: c),
            );
            expect(
              _sum(a.risk.values),
              closeTo(1, 1e-9),
              reason: '$p $band $c',
            );
            expect(
              _sum(a.action.values),
              closeTo(1, 1e-9),
              reason: '$p $band $c',
            );
            expect(a.risk.values.every((v) => v >= 0 && v <= 1), isTrue);
          }
        }
      }
    });

    test(
      'nonsense numbers do not break it, and unknown hazard counts as high',
      () {
        final a = advise(_facts(p: double.nan, ratio: double.infinity));
        expect(_sum(a.action.values), closeTo(1, 1e-9));
        expect(a.bestAction, AdviceAction.avoid);
      },
    );

    test('the same facts give the same answer', () {
      final a = advise(_facts(p: 0.4, ratio: 0.2));
      final b = advise(_facts(p: 0.4, ratio: 0.2));
      expect(a.action, b.action);
      expect(a.risk, b.risk);
    });
  });

  group('the verdict follows the hazard', () {
    test('no hazard with strong evidence: lower risk, proceed with care', () {
      final a = advise(_facts());
      expect(a.riskLevel, RiskLevel.lower);
      expect(a.bestAction, AdviceAction.proceedWithCare);
      expect(a.evidence, EvidenceLevel.strong);
    });

    test('a middling hazard: moderate risk, wait', () {
      final a = advise(_facts(p: 0.4, ratio: 0.2));
      expect(a.riskLevel, RiskLevel.moderate);
      expect(a.bestAction, AdviceAction.wait);
    });

    test('a severe hazard: high risk, avoid', () {
      final a = advise(_facts(p: 0.9, ratio: 0.6));
      expect(a.riskLevel, RiskLevel.high);
      expect(a.bestAction, AdviceAction.avoid);
      expect(a.reasons, contains(AdviceReason.highRiskStreet));
    });

    test('more hazard never makes "avoid" less likely', () {
      var last = -1.0;
      for (var p = 0.0; p <= 1.0001; p += 0.05) {
        final v = advise(_facts(p: p, ratio: p / 2))
            .action[AdviceAction.avoid]!;
        expect(v, greaterThanOrEqualTo(last - 1e-12), reason: 'p=$p');
        last = v;
      }
    });

    test('time lost to hazard counts as well as the worst street', () {
      final calm = advise(_facts(p: 0.3, ratio: 0));
      final slowed = advise(_facts(p: 0.3, ratio: 0.5));
      expect(
        slowed.risk[RiskLevel.high]!,
        greaterThan(calm.risk[RiskLevel.high]!),
      );
    });
  });

  group('absence of data is not safety (ADR-011)', () {
    test('thin evidence never raises the chance of "proceed with care"', () {
      final strong = advise(_facts());
      for (final band in [
        ConfidenceBand.moderate,
        ConfidenceBand.low,
        ConfidenceBand.stale,
      ]) {
        final thin = advise(_facts(band: band));
        expect(
          thin.action[AdviceAction.proceedWithCare]!,
          lessThan(strong.action[AdviceAction.proceedWithCare]!),
          reason: '$band',
        );
      }
    });

    test('with no evidence the likeliest level is not "lower", and the advice is not decisive', () {
      final a = advise(
        _facts(band: ConfidenceBand.stale, gaps: 3, event: EventState.dry),
      );
      expect(a.evidence, EvidenceLevel.little);
      expect(a.riskLevel, RiskLevel.moderate);
      expect(a.bestAction, isNot(AdviceAction.proceedWithCare));
      expect(a.decisiveness, lessThan(advise(_facts()).decisiveness));
    });

    test('a quiet route on a dry day carries less evidence than the same route in an event', () {
      final dry = advise(_facts(event: EventState.dry));
      final active = advise(_facts());
      expect(dry.evidenceScore, lessThan(active.evidenceScore));
      expect(dry.reasons, contains(AdviceReason.noEvent));
    });

    test('there is no answer that says a road is safe', () {
      for (final n in [
        ...AdviceAction.values.map((e) => e.name),
        ...RiskLevel.values.map((e) => e.name),
      ]) {
        expect(
          n.toLowerCase(),
          isNot(anyOf('go', 'safe', 'clear', 'open', 'ok')),
        );
      }
    });
  });

  group('the traveller matters', () {
    test('a walker is more likely than a rider, and a rider than a driver, to be told to avoid', () {
      double avoid(UserClass c) =>
          advise(_facts(p: 0.55, ratio: 0.2, userClass: c))
              .action[AdviceAction.avoid]!;
      expect(
        avoid(UserClass.pedestrian),
        greaterThan(avoid(UserClass.cyclist)),
      );
      expect(avoid(UserClass.cyclist), greaterThan(avoid(UserClass.commuter)));
    });
  });

  group('reasons', () {
    test('at most two, most important first', () {
      final a = advise(
        _facts(
          p: 0.7,
          blocked: 2,
          band: ConfidenceBand.low,
          event: EventState.dry,
        ),
      );
      expect(a.reasons.length, 2);
      expect(a.reasons.first, AdviceReason.highRiskStreet);
      expect(a.reasons[1], AdviceReason.floodedAlternativesAvoided);
    });

    test('stale and low data are named', () {
      expect(
        advise(_facts(band: ConfidenceBand.stale)).reasons,
        contains(AdviceReason.staleData),
      );
      expect(
        advise(_facts(band: ConfidenceBand.low)).reasons,
        contains(AdviceReason.littleData),
      );
    });
  });

  group('route choice', () {
    test('one route alone is chosen with probability 1', () {
      expect(advise(_facts()).choice.chosenProbability, 1);
    });

    test('a slightly slower but much less risky chosen route wins clearly', () {
      final a = advise(
        _facts(
          candidates: const [
            CandidateFacts(
              routeId: 'A',
              durationSeconds: 1800,
              riskScore: 0.05,
            ),
            CandidateFacts(routeId: 'B', durationSeconds: 1500, riskScore: 0.9),
          ],
        ),
      );
      expect(a.choice.compared, 2);
      expect(a.choice.chosenProbability, greaterThan(0.9));
    });

    test(
      'a chosen route no better than the alternative is only weakly preferred',
      () {
        final a = advise(
          _facts(
            candidates: const [
              CandidateFacts(
                routeId: 'A',
                durationSeconds: 1800,
                riskScore: 0.2,
              ),
              CandidateFacts(
                routeId: 'B',
                durationSeconds: 1800,
                riskScore: 0.2,
              ),
            ],
          ),
        );
        expect(a.choice.chosenProbability, closeTo(0.5, 1e-9));
      },
    );
  });

  test('one piece of advice costs microseconds (measured over 100,000 calls)', () {
    final f = _facts(
      p: 0.4,
      ratio: 0.2,
      candidates: const [
        CandidateFacts(routeId: 'A', durationSeconds: 1800, riskScore: 0.2),
        CandidateFacts(routeId: 'B', durationSeconds: 1500, riskScore: 0.7),
      ],
    );
    final sw = Stopwatch()..start();
    var sink = 0.0;
    const n = 100000;
    for (var i = 0; i < n; i++) {
      sink += advise(f).decisiveness;
    }
    sw.stop();
    final microsPerCall = sw.elapsedMicroseconds / n;
    // ignore: avoid_print
    print(
      'advise(): ${microsPerCall.toStringAsFixed(2)} us per call over $n calls (sink $sink)',
    );
    // Generous: a phone is slower than a laptop, and this still leaves a large margin on a 16 ms frame.
    expect(microsPerCall, lessThan(100));
  });

  test('facts read from a real trace', () {
    final trace = DecisionTrace(
      queryId: 'q',
      computedAt: DateTime.utc(2026, 10, 3),
      mode: RoutingMode.offline,
      userClass: UserClass.pedestrian,
      z: 1.28,
      lambda: 1.2,
      chosen: ChosenRoute(
        routeId: 'A',
        durationSeconds: 1500,
        distanceMeters: 9000,
        freeFlowDurationSeconds: 1200,
        worstEdgeP: 0.35,
        geometryRef: 'g',
      ),
      alternatives: const [
        AlternativeRoute(
          routeId: 'B',
          durationSeconds: 1000,
          rejectedBecause: RejectedBecause.chanceConstraint,
          blockingEdges: [],
        ),
      ],
      contextFacts: const [],
      dataGaps: const [
        DataGap(corridor: 'x', reason: 'no_observations_in_window'),
      ],
      confidenceBand: ConfidenceBand.moderate,
    );
    final facts = RouteFacts.fromTrace(trace, eventState: EventState.active);
    expect(facts.blockedAlternatives, 1);
    expect(facts.hazardPenaltyRatio, closeTo(0.25, 1e-9));
    expect(facts.candidates.length, 2);
    expect(facts.candidates[1].riskScore, 1);
    final a = advise(facts);
    expect(a.reasons, contains(AdviceReason.floodedAlternativesAvoided));
    expect(a.choice.chosenProbability, greaterThan(0.5));
  });
}
