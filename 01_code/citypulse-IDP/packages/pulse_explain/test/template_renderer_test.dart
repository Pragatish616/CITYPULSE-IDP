import 'package:pulse_explain/pulse_explain.dart';
import 'package:pulse_router/pulse_router.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('renderTemplate -- T4.1', () {
    test('renders the delta, blocking-edge and confidence sentences for the '
        'docs/CONTRACTS.md §3 worked example, and its own output passes '
        'verify() -- T4.1 acceptance criterion', () {
      final explanation = renderTemplate(
        trace: buildTrace(),
        hazardDisplayNouns: testHazardDisplayNouns,
      );

      // F-04 item 1 (ADR-016): the delta is chosen free-flow (1023 s) against
      // the alternative (907 s), i.e. 116 s -> 2 minutes. The contract's old
      // "4 minutes" came from 1147 - 907, a hazard-penalised cost minus a
      // driving time.
      expect(
        explanation.text,
        contains('Route A is 2 minutes slower than Route B.'),
      );
      expect(explanation.text, isNot(contains('4 minutes')));
      expect(
        explanation.text,
        contains(
          'It avoids a stretch of Kotturpuram Bridge approach where flooding '
          'was reported 3 minutes ago.',
        ),
      );
      expect(
        explanation.text,
        contains('Hazard confidence for this route is moderate.'),
      );
      expect(explanation.tier, equals(0));
      expect(explanation.locale, equals('en'));
      expect(
        explanation.queryId,
        equals('0192f3d0-0000-7000-8000-000000000000'),
      );
      expect(explanation.verification.passed, isTrue);
      expect(explanation.verification.fallbackUsed, isFalse);
    });

    test('the only-route sentence is used when there are no alternatives', () {
      final explanation = renderTemplate(
        trace: buildTrace(alternatives: const []),
        hazardDisplayNouns: testHazardDisplayNouns,
      );
      expect(
        explanation.text,
        contains('Route A is the only route found for this trip.'),
      );
      expect(explanation.text, isNot(contains('avoids')));
      expect(explanation.verification.passed, isTrue);
    });

    test('an alternative with no blocking edges (rejected purely on cost) '
        'renders the delta sentence without a fabricated avoidance claim', () {
      final explanation = renderTemplate(
        trace: buildTrace(
          alternatives: const [
            AlternativeRoute(
              routeId: 'B',
              durationSeconds: 800,
              rejectedBecause: RejectedBecause.higherCost,
              blockingEdges: [],
            ),
          ],
        ),
        hazardDisplayNouns: testHazardDisplayNouns,
      );
      // 1023 s free-flow against 800 s = 223 s -> 4 minutes (was 6, from the
      // penalised 1147 s).
      expect(
        explanation.text,
        contains('Route A is 4 minutes slower than Route B.'),
      );
      expect(explanation.text, isNot(contains('avoids')));
      expect(explanation.verification.passed, isTrue);
    });

    test('a prior-only avoided edge never claims a report (F-04 item 3)', () {
      final explanation = renderTemplate(
        trace: buildTrace(
          alternatives: const [
            AlternativeRoute(
              routeId: 'B',
              durationSeconds: 907,
              rejectedBecause: RejectedBecause.higherCost,
              blockingEdges: [
                BlockingEdge(
                  edgeId: 7,
                  streetName: 'Velachery Main Road',
                  hazardClass: 'flood',
                  pMean: 0.4,
                  pPessimistic: 0.4,
                  nEff: 0,
                  newestObservationAgeSeconds: 0,
                  sourceClass: 'unknown',
                  depthMm: null,
                  timePenaltySeconds: 60,
                  removedByChanceConstraint: false,
                  hasObservation: false,
                ),
              ],
            ),
          ],
        ),
        hazardDisplayNouns: testHazardDisplayNouns,
      );
      expect(explanation.text, isNot(contains('moments ago')));
      expect(explanation.text, isNot(contains('reported on')));
      expect(
        explanation.text,
        contains(
          'It avoids a stretch of Velachery Main Road that the hazard map '
          'marks for flooding, where no report has been received.',
        ),
      );
      expect(explanation.verification.passed, isTrue);
    });

    test('renderTemplateSafe returns a verified fixed sentence instead of '
        'throwing when Tier 0 fails its own check (F-07)', () {
      // A hazard noun containing a rule-6 denylist phrase makes
      // renderTemplate fail its own verify().
      final failures = <Object>[];
      final explanation = renderTemplateSafe(
        trace: buildTrace(),
        hazardDisplayNouns: const {'flood': 'a safe route issue'},
        onFailure: failures.add,
      );
      expect(failures, hasLength(1));
      expect(explanation.text, equals(kMinimalExplanationText));
      expect(explanation.verification.passed, isTrue);
      expect(explanation.verification.fallbackUsed, isTrue);
      // The failing text is never part of what the user sees.
      expect(explanation.text, isNot(contains('safe')));
    });

    test('renderTemplateSafe is identical to renderTemplate when Tier 0 '
        'succeeds', () {
      final safe = renderTemplateSafe(
        trace: buildTrace(),
        hazardDisplayNouns: testHazardDisplayNouns,
      );
      final plain = renderTemplate(
        trace: buildTrace(),
        hazardDisplayNouns: testHazardDisplayNouns,
      );
      expect(safe.text, equals(plain.text));
      expect(safe.verification.fallbackUsed, isFalse);
    });

    test('the minimal fixed sentence passes the verifier under every '
        'confidence band', () {
      for (final band in ConfidenceBand.values) {
        final result = verify(
          kMinimalExplanationText,
          buildTrace(confidenceBand: band),
          hazardDisplayNouns: testHazardDisplayNouns,
        );
        expect(
          result.passed,
          isTrue,
          reason: '$band: ${result.unsupportedClaims}',
        );
      }
    });

    test(
      'a zero-minute delta reads as "about the same time", not "0 minutes"',
      () {
        final explanation = renderTemplate(
          trace: buildTrace(
            chosenDurationSeconds: 900,
            chosenFreeFlowDurationSeconds: 850,
            alternatives: const [
              AlternativeRoute(
                routeId: 'B',
                durationSeconds: 860,
                rejectedBecause: RejectedBecause.higherCost,
                blockingEdges: [],
              ),
            ],
          ),
          hazardDisplayNouns: testHazardDisplayNouns,
        );
        expect(
          explanation.text,
          contains('Route A takes about the same time as Route B.'),
        );
        expect(explanation.text, isNot(contains('0 minutes')));
        expect(explanation.verification.passed, isTrue);
      },
    );

    test(
      'singular "1 minute" is not pluralised, for both the delta and the age',
      () {
        final explanation = renderTemplate(
          trace: buildTrace(
            chosenDurationSeconds: 967,
            chosenFreeFlowDurationSeconds: 967, // 907 + 60 s -> 1-minute delta
            alternatives: [
              const AlternativeRoute(
                routeId: 'B',
                durationSeconds: 907,
                rejectedBecause: RejectedBecause.chanceConstraint,
                blockingEdges: [
                  BlockingEdge(
                    edgeId: 184223,
                    streetName: 'Kotturpuram Bridge approach',
                    hazardClass: 'flood',
                    pMean: 0.79,
                    pPessimistic: 1,
                    nEff: 1.8,
                    newestObservationAgeSeconds: 65,
                    sourceClass: 'crowd',
                    depthMm: 320,
                    timePenaltySeconds: 0,
                    removedByChanceConstraint: true,
                  ),
                ],
              ),
            ],
          ),
          hazardDisplayNouns: testHazardDisplayNouns,
        );
        expect(explanation.text, contains('1 minute slower than'));
        expect(explanation.text, isNot(contains('1 minutes')));
        expect(explanation.text, contains('1 minute ago'));
        expect(explanation.verification.passed, isTrue);
      },
    );

    test(
      'an age under 30 seconds reads as "moments ago", not "0 minutes ago"',
      () {
        final explanation = renderTemplate(
          trace: buildTrace(
            alternatives: [
              const AlternativeRoute(
                routeId: 'B',
                durationSeconds: 907,
                rejectedBecause: RejectedBecause.chanceConstraint,
                blockingEdges: [
                  BlockingEdge(
                    edgeId: 184223,
                    streetName: 'Kotturpuram Bridge approach',
                    hazardClass: 'flood',
                    pMean: 0.79,
                    pPessimistic: 1,
                    nEff: 1.8,
                    newestObservationAgeSeconds: 10,
                    sourceClass: 'crowd',
                    depthMm: 320,
                    timePenaltySeconds: 0,
                    removedByChanceConstraint: true,
                  ),
                ],
              ),
            ],
          ),
          hazardDisplayNouns: testHazardDisplayNouns,
        );
        expect(explanation.text, contains('moments ago'));
        expect(explanation.text, isNot(contains('0 minutes ago')));
        expect(explanation.verification.passed, isTrue);
      },
    );

    for (final band in [ConfidenceBand.low, ConfidenceBand.stale]) {
      test('$band confidence renders a hedge and still passes rule 4 by '
          'construction', () {
        final explanation = renderTemplate(
          trace: buildTrace(confidenceBand: band),
          hazardDisplayNouns: testHazardDisplayNouns,
        );
        expect(explanation.text, contains('Use your own judgement.'));
        expect(explanation.verification.passed, isTrue);
        expect(explanation.verification.unsupportedClaims, isEmpty);
      });
    }

    test('high and moderate confidence render without a hedge sentence', () {
      for (final band in [ConfidenceBand.high, ConfidenceBand.moderate]) {
        final explanation = renderTemplate(
          trace: buildTrace(confidenceBand: band),
          hazardDisplayNouns: testHazardDisplayNouns,
        );
        expect(explanation.text, isNot(contains('judgement')));
        expect(explanation.verification.passed, isTrue);
      }
    });

    test('data gaps render a sentence naming every corridor, and are omitted '
        'when empty', () {
      final withGaps = renderTemplate(
        trace: buildTrace(
          dataGaps: const [
            DataGap(
              corridor: 'Velachery Main Rd',
              reason: 'no_observations_in_window',
            ),
            DataGap(
              corridor: 'OMR Service Road',
              reason: 'no_observations_in_window',
            ),
          ],
        ),
        hazardDisplayNouns: testHazardDisplayNouns,
      );
      expect(
        withGaps.text,
        contains(
          'No recent hazard data is available for Velachery Main Rd, '
          'OMR Service Road',
        ),
      );
      expect(withGaps.verification.passed, isTrue);

      final withoutGaps = renderTemplate(
        trace: buildTrace(),
        hazardDisplayNouns: testHazardDisplayNouns,
      );
      expect(withoutGaps.text, isNot(contains('No recent hazard data')));
    });

    test('an unmapped hazard class falls back to its raw wire string instead '
        'of crashing', () {
      final explanation = renderTemplate(
        trace: buildTrace(
          alternatives: [
            const AlternativeRoute(
              routeId: 'B',
              durationSeconds: 907,
              rejectedBecause: RejectedBecause.chanceConstraint,
              blockingEdges: [
                BlockingEdge(
                  edgeId: 1,
                  streetName: 'Pallikaranai Radial Road',
                  hazardClass: 'landslide', // not in testHazardDisplayNouns
                  pMean: 0.9,
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
        hazardDisplayNouns: testHazardDisplayNouns,
      );
      expect(explanation.text, contains('where landslide was reported'));
      expect(explanation.verification.passed, isTrue);
    });

    test(
      'facts_used records the trace paths the rendered text actually drew from',
      () {
        final explanation = renderTemplate(
          trace: buildTrace(
            dataGaps: const [
              DataGap(
                corridor: 'Velachery Main Rd',
                reason: 'no_observations_in_window',
              ),
            ],
          ),
          hazardDisplayNouns: testHazardDisplayNouns,
        );
        expect(
          explanation.factsUsed,
          containsAll(<String>[
            'chosen.route_id',
            'chosen.duration_s',
            'alternatives[0].route_id',
            'alternatives[0].duration_s',
            'alternatives[0].blocking_edges[0].hazard_class',
            'alternatives[0].blocking_edges[0].street_name',
            'alternatives[0].blocking_edges[0].newest_observation_age_s',
            'confidence_band',
            'data_gaps[0].corridor',
          ]),
        );
      },
    );

    test('a custom locale is passed through unchanged', () {
      final explanation = renderTemplate(
        trace: buildTrace(),
        hazardDisplayNouns: testHazardDisplayNouns,
        locale: 'ta',
      );
      expect(explanation.locale, equals('ta'));
    });

    test('renderTemplate throws instead of silently returning unverified text '
        '-- proves the runtime guarantee is enforced, not just documented '
        '(regression for independent-review finding: a future '
        'hazardDisplayNouns entry containing rule-6 vocabulary would '
        'otherwise silently produce a failing Explanation)', () {
      expect(
        () => renderTemplate(
          trace: buildTrace(),
          hazardDisplayNouns: {'flood': 'a totally safe flood'},
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('Explanation.toJson() and VerificationResult.toJson() match '
        "docs/CONTRACTS.md §4's field names exactly", () {
      final explanation = renderTemplate(
        trace: buildTrace(),
        hazardDisplayNouns: testHazardDisplayNouns,
      );
      final json = explanation.toJson();
      expect(
        json.keys,
        containsAll(<String>[
          'query_id',
          'tier',
          'text',
          'locale',
          'facts_used',
          'verification',
        ]),
      );
      final verification = json['verification']! as Map<String, Object?>;
      expect(
        verification.keys,
        containsAll(<String>[
          'passed',
          'numerals_grounded',
          'entities_grounded',
          'contrastive_valid',
          'unsupported_claims',
          'fallback_used',
          'latency_ms',
        ]),
      );
      expect(json['tier'], equals(0));
      expect(json['query_id'], equals(explanation.queryId));
      expect(verification['passed'], isTrue);
      // Round-trips through the same JsonEncoder DecisionTrace itself
      // uses, so a malformed value (a non-JSON-safe type slipping into
      // the object graph) fails loudly here rather than at the actual
      // wire boundary.
      expect(explanation.toJsonString(), isA<String>());
    });

    test(
      'ADR-011 audit: every fixed template sentence, across every branch this '
      'renderer can take, is free of the rule-6 absolute-safety vocabulary -- '
      'the hand audit ADR-011 requires, pinned as a fixed test fixture rather '
      'than left as a one-time claim',
      () {
        const bannedWords = [
          'safe',
          ' clear',
          'clear ',
          'passable',
          'fine',
          'no issue',
          'no problem',
          'all clear',
          'guarantee', // only allowed inside "not a guarantee"
        ];

        final blockingEdgeVariants = [
          const <BlockingEdge>[],
          [
            const BlockingEdge(
              edgeId: 1,
              streetName: 'Test Street',
              hazardClass: 'flood',
              pMean: 0.5,
              pPessimistic: 0.9,
              nEff: 1,
              newestObservationAgeSeconds: 60,
              sourceClass: 'crowd',
              depthMm: null,
              timePenaltySeconds: 0,
              removedByChanceConstraint: true,
            ),
          ],
        ];
        final alternativeVariants = [
          const <AlternativeRoute>[],
          for (final edges in blockingEdgeVariants)
            [
              AlternativeRoute(
                routeId: 'B',
                durationSeconds: 900,
                rejectedBecause: RejectedBecause.chanceConstraint,
                blockingEdges: edges,
              ),
            ],
        ];
        final dataGapVariants = [
          const <DataGap>[],
          const [
            DataGap(
              corridor: 'Test Corridor',
              reason: 'no_observations_in_window',
            ),
          ],
        ];

        for (final band in ConfidenceBand.values) {
          for (final alternatives in alternativeVariants) {
            for (final dataGaps in dataGapVariants) {
              for (final hazardClass in [
                ...testHazardDisplayNouns.keys,
                'unmapped_class',
              ]) {
                final adjustedAlternatives = [
                  for (final alt in alternatives)
                    AlternativeRoute(
                      routeId: alt.routeId,
                      durationSeconds: alt.durationSeconds,
                      rejectedBecause: alt.rejectedBecause,
                      blockingEdges: [
                        for (final e in alt.blockingEdges)
                          BlockingEdge(
                            edgeId: e.edgeId,
                            streetName: e.streetName,
                            hazardClass: hazardClass,
                            pMean: e.pMean,
                            pPessimistic: e.pPessimistic,
                            nEff: e.nEff,
                            newestObservationAgeSeconds:
                                e.newestObservationAgeSeconds,
                            sourceClass: e.sourceClass,
                            depthMm: e.depthMm,
                            timePenaltySeconds: e.timePenaltySeconds,
                            removedByChanceConstraint:
                                e.removedByChanceConstraint,
                          ),
                      ],
                    ),
                ];
                final explanation = renderTemplate(
                  trace: buildTrace(
                    alternatives: adjustedAlternatives,
                    dataGaps: dataGaps,
                    confidenceBand: band,
                  ),
                  hazardDisplayNouns: testHazardDisplayNouns,
                );
                final lower = explanation.text.toLowerCase();
                for (final banned in bannedWords) {
                  if (banned == 'guarantee') {
                    expect(
                      lower.contains('guarantee') &&
                          !lower.contains('not a guarantee'),
                      isFalse,
                      reason:
                          '"guarantee" must only appear inside "not a '
                          'guarantee" -- text was: ${explanation.text}',
                    );
                  } else {
                    expect(
                      lower,
                      isNot(contains(banned)),
                      reason:
                          'banned word "$banned" found in: ${explanation.text}',
                    );
                  }
                }
                expect(
                  explanation.verification.passed,
                  isTrue,
                  reason:
                      "verify() rejected Tier 0's own output: "
                      '${explanation.text} -- '
                      '${explanation.verification.unsupportedClaims}',
                );
              }
            }
          }
        }
      },
    );
  });
}
