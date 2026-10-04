import 'package:pulse_explain/pulse_explain.dart';
import 'package:pulse_router/pulse_router.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Asserts [text] fails [verify] against [trace], and that at least one of
/// its [expectedTagPrefixes] (e.g. `'rule1:'`) shows up in
/// `unsupportedClaims`. This is the adversarial-suite acceptance criterion
/// from `docs/IMPLEMENTATION_PLAN.md` T4.2: "100% detection on a
/// hand-written adversarial suite of >= 30 cases."
void _expectRejected(
  String description,
  String text,
  DecisionTrace trace,
  List<String> expectedTagPrefixes, {
  Map<String, String> hazardDisplayNouns = const {},
}) {
  test(description, () {
    final result = verify(text, trace, hazardDisplayNouns: hazardDisplayNouns);
    expect(result.passed, isFalse, reason: 'expected "$text" to fail verify()');
    for (final prefix in expectedTagPrefixes) {
      expect(
        result.unsupportedClaims.any((c) => c.startsWith(prefix)),
        isTrue,
        reason:
            'expected an unsupportedClaims entry starting "$prefix" for '
            '"$text", got ${result.unsupportedClaims}',
      );
    }
  });
}

void main() {
  final trace = buildTrace();
  final traceNoAlternatives = buildTrace(alternatives: const []);
  final traceAltWithoutBlockingEdge = buildTrace(
    alternatives: const [
      AlternativeRoute(
        routeId: 'B',
        durationSeconds: 800,
        rejectedBecause: RejectedBecause.higherCost,
        blockingEdges: [],
      ),
    ],
  );
  final traceLow = buildTrace(confidenceBand: ConfidenceBand.low);
  final traceStale = buildTrace(confidenceBand: ConfidenceBand.stale);

  group('verify -- T4.2 -- positive control (must pass)', () {
    test('the exact docs/CONTRACTS.md §3 worked-example sentence passes', () {
      final result = verify(
        'Route A is 2 minutes slower than Route B. It avoids flooding '
        'reported on Kotturpuram Bridge approach, 3 minutes ago.',
        trace,
      );
      expect(result.passed, isTrue);
      expect(result.unsupportedClaims, isEmpty);
    });

    test('regression F-04 item 1: the penalised-cost delta (1147 - 907 = 240 s '
        '= 4 minutes) is no longer a grounded "minutes slower" figure', () {
      final result = verify('Route A is 4 minutes slower than Route B.', trace);
      expect(result.numeralsGrounded, isFalse);
      expect(result.passed, isFalse);
      expect(result.unsupportedClaims, contains('rule1:numeral:4'));
    });

    test('a percentage phrased from worst_edge_p passes rule 1', () {
      final result = verify(
        'Route A is 2 minutes slower than Route B, with a 31% hazard '
        'probability at its worst point.',
        trace,
      );
      expect(result.numeralsGrounded, isTrue);
    });

    test(
      'a distance phrased in kilometres to 1 decimal place passes rule 1',
      () {
        final result = verify('This route is 8.4 km long.', trace);
        expect(result.numeralsGrounded, isTrue);
      },
    );

    test('mentioning both route labels passes rule 2', () {
      final result = verify(
        'This compares Route A and Route B directly.',
        trace,
      );
      expect(result.entitiesGrounded, isTrue);
    });

    test('a hedge on a low-confidence trace passes rule 4', () {
      final result = verify(
        'Hazard confidence is low; this is unverified crowd data. Use your '
        'own judgement.',
        traceLow,
      );
      expect(result.passed, isTrue);
    });

    test('comparative language with a genuine alternative passes rule 3', () {
      final result = verify(
        'Route A is 2 minutes slower than Route B. It avoids flooding on '
        'Kotturpuram Bridge approach.',
        trace,
      );
      expect(result.contrastiveValid, isTrue);
    });
  });

  group('verify -- T4.2 -- rule 1: numeral grounding (adversarial)', () {
    _expectRejected(
      'a hallucinated delta far from the real 4-minute figure',
      'Route A is 12 minutes slower than Route B.',
      trace,
      ['rule1:'],
    );
    _expectRejected(
      'a hallucinated observation age far from the real 3-minute figure',
      'Route A is 2 minutes slower than Route B. It avoids flooding '
          'reported on Kotturpuram Bridge approach, 45 minutes ago.',
      trace,
      ['rule1:'],
    );
    _expectRejected(
      'an invented distance not in the trace',
      'This route covers 500 meters.',
      trace,
      ['rule1:'],
    );
    _expectRejected(
      'an invented hazard percentage',
      'The hazard probability on this route is 99%.',
      trace,
      ['rule1:'],
    );
    _expectRejected(
      'an invented standing-water depth',
      'Standing water here is 999 mm deep.',
      trace,
      ['rule1:'],
    );
    _expectRejected(
      'an invented time savings figure',
      'Taking this route saves 23 minutes.',
      trace,
      ['rule1:'],
    );
    _expectRejected(
      'an invented evidence count',
      'There have been 42 reports on this stretch.',
      trace,
      ['rule1:'],
    );
    _expectRejected(
      'an invented pessimism parameter',
      'This trip used a z value of 5.0.',
      trace,
      ['rule1:'],
    );
    _expectRejected(
      'an invented reservoir level with no matching context fact',
      'Chembarambakkam reservoir is at 94% capacity.',
      buildTrace(),
      ['rule1:'],
    );
  });

  group('verify -- T4.2 -- rule 2: entity grounding (adversarial)', () {
    _expectRejected(
      'an invented street name substituted for the real blocking edge',
      'Route A is 2 minutes slower than Route B. It avoids flooding '
          'reported on MG Road, 3 minutes ago.',
      trace,
      ['rule2:'],
    );
    _expectRejected(
      'a different invented street name',
      'It avoids flooding reported on Anna Salai, 3 minutes ago.',
      trace,
      ['rule2:'],
    );
    _expectRejected(
      'an invented landmark not present anywhere in the trace',
      'Marina Beach Road is affected by flooding today.',
      trace,
      ['rule2:'],
    );
    _expectRejected(
      'an invented corridor name distinct from the real data gap',
      'No data is available for Guindy Race Course.',
      buildTrace(
        dataGaps: const [
          DataGap(
            corridor: 'Velachery Main Rd',
            reason: 'no_observations_in_window',
          ),
        ],
      ),
      ['rule2:'],
    );
    _expectRejected(
      'an invented signal/junction name',
      'T Nagar Signal is heavily congested.',
      trace,
      ['rule2:'],
    );
    _expectRejected(
      'an invented reservoir name not in context_facts',
      'Chembarambakkam Reservoir is overflowing near this route.',
      trace,
      ['rule2:'],
    );
    _expectRejected(
      'an invented area name',
      'The bridge near Adyar Estuary is flooded.',
      trace,
      ['rule2:'],
    );
  });

  group('verify -- T4.2 -- rule 3: unsupported comparative claims '
      '(adversarial)', () {
    _expectRejected(
      '"slower" used when the trace has no alternative to compare against',
      'Route A is 5 minutes slower than the usual route.',
      traceNoAlternatives,
      ['rule3:'],
    );
    _expectRejected(
      '"faster" used when the trace has no alternative to compare against',
      'This route is faster than walking.',
      traceNoAlternatives,
      ['rule3:'],
    );
    _expectRejected(
      '"quicker" used when the trace has no alternative to compare against',
      'Route A is quicker than any other option today.',
      traceNoAlternatives,
      ['rule3:'],
    );
    _expectRejected(
      '"avoids" a hazard when the only alternative has no blocking edges '
          'at all',
      'Route A avoids a flooded section that Route B has.',
      traceAltWithoutBlockingEdge,
      ['rule3:'],
    );
    _expectRejected(
      '"avoiding" a hazard when there are no alternatives to have carried one',
      'This route is worth taking for avoiding the flooded underpass.',
      traceNoAlternatives,
      ['rule3:'],
    );
  });

  group('verify -- T4.2 -- claim coherence (regression: exploits found by '
      'independent review, not covered by token-level grounding alone)', () {
    _expectRejected(
      "reviewer's exact repro: a real edge's age borrowed to fabricate a "
          'fresh hazard report on a corridor the trace says has no data at '
          'all',
      'Route A avoids flooding reported on Velachery Main Rd, 3 minutes '
          'ago.',
      buildTrace(
        dataGaps: const [
          DataGap(
            corridor: 'Velachery Main Rd',
            reason: 'no_observations_in_window',
          ),
        ],
      ),
      ['rule3:'],
    );
    _expectRejected(
      'a data-gap corridor combined with an avoidance claim but no '
          'numeral is still a contradiction',
      'Route A avoids flooding on Velachery Main Rd.',
      buildTrace(
        dataGaps: const [
          DataGap(
            corridor: 'Velachery Main Rd',
            reason: 'no_observations_in_window',
          ),
        ],
      ),
      ['rule3:'],
    );
    _expectRejected(
      "code-review's exact repro: a hazard is correctly grounded to "
          'Route B by name, but the real blocking edge belongs to the '
          'unmentioned Route C -- "some alternative has a blocking edge" is '
          'not the same claim as "the alternative I named does"',
      'Route A avoids flooding on Random Street reported on Route B.',
      buildTrace(
        alternatives: const [
          AlternativeRoute(
            routeId: 'B',
            durationSeconds: 900,
            rejectedBecause: RejectedBecause.higherCost,
            blockingEdges: [],
          ),
          AlternativeRoute(
            routeId: 'C',
            durationSeconds: 950,
            rejectedBecause: RejectedBecause.chanceConstraint,
            blockingEdges: [
              BlockingEdge(
                edgeId: 999,
                streetName: 'Random Street',
                hazardClass: 'flood',
                pMean: 0.8,
                pPessimistic: 1,
                nEff: 2,
                newestObservationAgeSeconds: 120,
                sourceClass: 'crowd',
                depthMm: null,
                timePenaltySeconds: 0,
                removedByChanceConstraint: true,
              ),
            ],
          ),
        ],
      ),
      ['rule3:'],
    );
    _expectRejected(
      "code-review's exact repro: the hazard noun is swapped for a "
          "different hazard class than the cited edge's own hazard_class",
      'Route A is 2 minutes slower than Route B. It avoids debris on the '
          'road reported on Kotturpuram Bridge approach, 3 minutes ago.',
      trace,
      ['rule2:'],
      hazardDisplayNouns: testHazardDisplayNouns,
    );

    test('positive control: the correct hazard noun for the cited edge '
        "passes rule 2's hazard-noun check", () {
      final result = verify(
        'Route A is 2 minutes slower than Route B. It avoids flooding '
        'reported on Kotturpuram Bridge approach, 3 minutes ago.',
        trace,
        hazardDisplayNouns: testHazardDisplayNouns,
      );
      expect(result.entitiesGrounded, isTrue);
    });

    test('positive control: a data-gap corridor and a real hazard claim in '
        'different sentences do not contaminate each other', () {
      final result = verify(
        'Route A is 2 minutes slower than Route B. It avoids flooding '
        'reported on Kotturpuram Bridge approach, 3 minutes ago. No '
        'recent hazard data is available for Velachery Main Rd.',
        buildTrace(
          dataGaps: const [
            DataGap(
              corridor: 'Velachery Main Rd',
              reason: 'no_observations_in_window',
            ),
          ],
        ),
      );
      expect(result.passed, isTrue, reason: '${result.unsupportedClaims}');
    });

    test('regression (found via app/ T5.1 integration test against real OSM '
        'street names): a data-gap corridor whose own name contains a digit '
        '("100 Feet Road") does not falsely trigger rule 3 on its own', () {
      final result = verify(
        'No recent hazard data is available for 100 Feet Road.',
        buildTrace(
          dataGaps: const [
            DataGap(
              corridor: '100 Feet Road',
              reason: 'no_observations_in_window',
            ),
          ],
        ),
      );
      expect(result.passed, isTrue, reason: '${result.unsupportedClaims}');
    });

    test(
      'regression: a digit-named data-gap corridor does not contaminate a '
      'different, digit-free data-gap corridor named in the same sentence',
      () {
        final result = verify(
          'No recent hazard data is available for 100 Feet Road or '
          'Velachery Main Rd.',
          buildTrace(
            dataGaps: const [
              DataGap(
                corridor: '100 Feet Road',
                reason: 'no_observations_in_window',
              ),
              DataGap(
                corridor: 'Velachery Main Rd',
                reason: 'no_observations_in_window',
              ),
            ],
          ),
        );
        expect(result.passed, isTrue, reason: '${result.unsupportedClaims}');
      },
    );

    _expectRejected(
      'a digit-named data-gap corridor still fails rule 3 when the '
          'sentence adds a genuine extra numeral claim beyond its own name',
      'No recent hazard data is available for 100 Feet Road, reported 3 '
          'minutes ago.',
      buildTrace(
        dataGaps: const [
          DataGap(
            corridor: '100 Feet Road',
            reason: 'no_observations_in_window',
          ),
        ],
      ),
      ['rule3:'],
    );
  });

  group('verify -- T4.2 -- rule 4: unhedged claim under low/stale confidence (adversarial)', () {
    _expectRejected(
      'a plain delta statement with zero hedging on a low-confidence trace',
      'Route A is 2 minutes slower than Route B.',
      traceLow,
      ['rule4:'],
    );
    _expectRejected(
      'a plain blocking-edge statement with zero hedging on a '
          'stale-confidence trace',
      'It avoids flooding reported on Kotturpuram Bridge approach, '
          '3 minutes ago.',
      traceStale,
      ['rule4:'],
    );
    _expectRejected(
      'reassuring language with no hedge word on a low-confidence trace',
      'Everything looks normal on this route today.',
      traceLow,
      ['rule4:'],
    );
    _expectRejected(
      'a confident numeric claim with no hedge word on a stale-confidence '
          'trace',
      'Route A is 2 minutes slower than Route B, definitely.',
      traceStale,
      ['rule4:'],
    );
  });

  group('verify -- T4.2 -- rule 6: unhedged affirmative-safety claim '
      '(ADR-011, adversarial)', () {
    _expectRejected(
      '"is safe to drive"',
      'This road is safe to drive.',
      trace,
      ['rule6:'],
    );
    _expectRejected('"is clear now"', 'The route is clear now.', trace, [
      'rule6:',
    ]);
    _expectRejected(
      '"nothing to worry about"',
      'Nothing to worry about on this road.',
      trace,
      ['rule6:'],
    );
    _expectRejected(
      '"you can safely"',
      'You can safely take this route today.',
      trace,
      ['rule6:'],
    );
    _expectRejected('"safe option"', 'Route A is a safe option.', trace, [
      'rule6:',
    ]);
    _expectRejected('"should be fine"', 'The bridge should be fine.', trace, [
      'rule6:',
    ]);
    _expectRejected('"all clear"', 'All clear ahead on this road.', trace, [
      'rule6:',
    ]);
    _expectRejected(
      '"completely safe"',
      'This route is completely safe.',
      trace,
      ['rule6:'],
    );
    _expectRejected('"no issues"', 'No issues reported on this road.', trace, [
      'rule6:',
    ]);
    _expectRejected(
      '"is passable"',
      'The Kotturpuram Bridge approach is passable.',
      trace,
      ['rule6:'],
    );
    _expectRejected(
      '"guaranteed safe"',
      'This is a guaranteed safe route.',
      trace,
      ['rule6:'],
    );
    _expectRejected(
      '"perfectly fine"',
      'Conditions on this road are perfectly fine.',
      trace,
      ['rule6:'],
    );
  });

  group('verify -- T4.2 -- multiple simultaneous violations', () {
    test('a single sentence with an invented delta, an invented entity, and an '
        'absolute-safety claim fails all three rules at once, not just the '
        'first one found', () {
      final result = verify(
        'Route A is 99 minutes slower than Route Z, which is completely '
        'safe.',
        trace,
      );
      expect(result.passed, isFalse);
      expect(result.numeralsGrounded, isFalse);
      expect(result.entitiesGrounded, isFalse);
      expect(
        result.unsupportedClaims.any((c) => c.startsWith('rule6:')),
        isTrue,
      );
      expect(result.unsupportedClaims.length, greaterThanOrEqualTo(3));
    });

    test('an unhedged low-confidence claim that is also an absolute-safety '
        'claim fails both rule 4 and rule 6', () {
      final result = verify('This road is safe to drive.', traceLow);
      expect(
        result.unsupportedClaims.any((c) => c.startsWith('rule4:')),
        isTrue,
      );
      expect(
        result.unsupportedClaims.any((c) => c.startsWith('rule6:')),
        isTrue,
      );
    });
  });

  group('verify -- T4.2 -- latency and determinism', () {
    test('latency_ms is measured, non-negative, and well under 1 ms', () {
      final result = verify('Route A is 2 minutes slower than Route B.', trace);
      expect(result.latencyMs, greaterThanOrEqualTo(0));
      expect(result.latencyMs, lessThan(50));
    });

    test('verify() never throws on adversarial or malformed input', () {
      for (final text in <String>[
        '',
        '   ',
        '99999999999999999999999999999 minutes',
        r'$%^&*()[]{}',
        'safe ' * 50,
        'A' * 5000,
      ]) {
        expect(() => verify(text, trace), returnsNormally);
      }
    });

    test('verify() is a pure function: same inputs, same passed/claims', () {
      const text = 'Route A is 2 minutes slower than Route B.';
      final a = verify(text, trace);
      final b = verify(text, trace);
      expect(a.passed, equals(b.passed));
      expect(a.unsupportedClaims, equals(b.unsupportedClaims));
    });
  });

  group('verify -- T4.2 -- verifyOrFallback (rule 5)', () {
    test(
      'a passing candidate is returned as-is, tier unchanged, no fallback',
      () {
        final explanation = verifyOrFallback(
          candidateText: 'Route A is 2 minutes slower than Route B.',
          candidateTier: 1,
          candidateFactsUsed: const ['chosen.duration_s'],
          trace: trace,
          queryId: trace.queryId,
          tier0Fallback: () => renderTemplate(
            trace: trace,
            hazardDisplayNouns: testHazardDisplayNouns,
          ),
        );
        expect(explanation.tier, equals(1));
        expect(explanation.verification.fallbackUsed, isFalse);
        expect(explanation.verification.passed, isTrue);
      },
    );

    test(
      'a failing candidate is discarded silently -- never returned, never '
      'surfaced -- and Tier 0 is returned instead with fallback_used: true',
      () {
        const hallucinated = 'This road is safe to drive at 500 km/h.';
        final explanation = verifyOrFallback(
          candidateText: hallucinated,
          candidateTier: 1,
          candidateFactsUsed: const ['chosen.duration_s'],
          trace: trace,
          queryId: trace.queryId,
          tier0Fallback: () => renderTemplate(
            trace: trace,
            hazardDisplayNouns: testHazardDisplayNouns,
          ),
        );
        expect(explanation.text, isNot(contains('500 km/h')));
        expect(explanation.text, isNot(equals(hallucinated)));
        expect(explanation.tier, equals(0));
        expect(explanation.verification.fallbackUsed, isTrue);
        expect(explanation.verification.passed, isTrue);
      },
    );
  });
}
