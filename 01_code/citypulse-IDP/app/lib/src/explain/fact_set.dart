/// The shared fact-set extractor for every Tier ≥ 1 explanation rewriter
/// (on-device SLM, T4.3; cloud, T4.4) — `docs/DECISIONS.md` ADR-004: the SLM
/// is "only a rewriter, never a fact source," and its prompt must be "the
/// fact set only," never the raw `DecisionTrace`. One extractor for both
/// tiers, per this task's brief, rather than two divergent ones that could
/// silently drift apart on what counts as a narratable fact.
///
/// **What this deliberately excludes, and why (ADR-007 — "no precise
/// coordinates leave the device," extended here to the on-device tier too
/// for consistency, per this task's brief).** `DecisionTrace`
/// (`packages/pulse_router/lib/src/decision_trace.dart`) never carries a raw
/// lat/lon coordinate or a user/device identifier in the first place — the
/// router works in abstract node/edge ids and a caller-supplied opaque
/// `geometry_ref` string (e.g. `"nodes:2337,2338,..."`), resolved to real
/// coordinates only client-side, in `route_service.dart`'s own
/// node-coordinate lookup, strictly *after* the trace is built. So there is
/// no coordinate *in* the trace for this extractor to accidentally leak.
/// This extractor additionally leaves out `geometry_ref` and every internal
/// `edge_id` — neither is a narratable fact (nothing a rewritten sentence
/// should ever say), and dropping them is one more layer of defence in
/// depth on top of "the trace itself has no coordinates." `query_id` is also
/// left out of the payload sent to a rewriter — it identifies a *query*, not
/// a person, but a rewriter has no legitimate reason to echo it back, and
/// the caller already holds it to stamp the returned `Explanation`.
///
/// **Do not read this file as re-deciding ADR-007 for Tier 1.** ADR-007's
/// own text scopes the no-raw-coordinates rule to "cloud LLM calls" — an
/// on-device rewriter has nothing to leak *to* since nothing leaves the
/// device (this task's brief says exactly this). The same extractor is
/// still used for both tiers purely for consistency and because it is what
/// makes the verifier's grounding checks meaningful for either tier's
/// output, not because Tier 1 needs ADR-007's protection.
library;

import 'package:pulse_router/pulse_router.dart';

/// The narratable subset of a [DecisionTrace], serialisable as a rewriter
/// prompt payload. See this file's top-level doc comment for exactly what is
/// and is not included, and why.
class FactSet {
  const FactSet._(this._json, this._factPaths);

  /// Extracts a [FactSet] from [trace]. [hazardDisplayNouns] is
  /// `config/hazard_classes.yaml`'s `display_noun` column (the same
  /// vocabulary `renderTemplate`/`verify` use in `packages/pulse_explain`) —
  /// passed through so a rewriter can use the same human-facing nouns Tier 0
  /// does instead of inventing its own; omitted, a blocking edge's raw
  /// `hazard_class` wire string is the only noun available.
  factory FactSet.fromTrace(
    DecisionTrace trace, {
    Map<String, String> hazardDisplayNouns = const {},
  }) {
    final factPaths = <String>[
      'chosen.route_id',
      'chosen.duration_s',
      'chosen.distance_m',
      'chosen.free_flow_duration_s',
      'chosen.hazard_time_penalty_s',
      'chosen.worst_edge_p',
      'confidence_band',
    ];

    Map<String, Object?> blockingEdgeJson(
      int altIndex,
      int edgeIndex,
      BlockingEdge e,
    ) {
      factPaths.add(
        'alternatives[$altIndex].blocking_edges[$edgeIndex].hazard_class',
      );
      factPaths.add(
        'alternatives[$altIndex].blocking_edges[$edgeIndex].street_name',
      );
      factPaths.add(
        'alternatives[$altIndex].blocking_edges[$edgeIndex]'
        '.newest_observation_age_s',
      );
      return {
        'street_name': e.streetName,
        'hazard_class': e.hazardClass,
        'hazard_noun': hazardDisplayNouns[e.hazardClass] ?? e.hazardClass,
        'p_mean': e.pMean,
        'p_pessimistic': e.pPessimistic,
        'n_eff': e.nEff,
        'newest_observation_age_s': e.newestObservationAgeSeconds.round(),
        'source_class': e.sourceClass,
        if (e.depthMm != null) 'depth_mm': e.depthMm,
        'time_penalty_s': e.timePenaltySeconds.round(),
        'removed_by_chance_constraint': e.removedByChanceConstraint,
      };
    }

    Map<String, Object?> alternativeJson(int altIndex, AlternativeRoute a) {
      factPaths.add('alternatives[$altIndex].route_id');
      factPaths.add('alternatives[$altIndex].duration_s');
      return {
        'route_id': a.routeId,
        'duration_s': a.durationSeconds.round(),
        'rejected_because': a.rejectedBecause.wireValue,
        'blocking_edges': [
          for (var i = 0; i < a.blockingEdges.length; i++)
            blockingEdgeJson(altIndex, i, a.blockingEdges[i]),
        ],
      };
    }

    for (var i = 0; i < trace.dataGaps.length; i++) {
      factPaths.add('data_gaps[$i].corridor');
    }
    for (var i = 0; i < trace.contextFacts.length; i++) {
      factPaths.add('context_facts[$i].label');
      factPaths.add('context_facts[$i].value');
    }

    final json = <String, Object?>{
      'chosen': {
        'route_id': trace.chosen.routeId,
        'duration_s': trace.chosen.durationSeconds.round(),
        'distance_m': trace.chosen.distanceMeters.round(),
        'free_flow_duration_s': trace.chosen.freeFlowDurationSeconds.round(),
        'hazard_time_penalty_s': trace.chosen.hazardTimePenaltySeconds.round(),
        'worst_edge_p': trace.chosen.worstEdgeP,
      },
      'alternatives': [
        for (var i = 0; i < trace.alternatives.length; i++)
          alternativeJson(i, trace.alternatives[i]),
      ],
      'context_facts': [
        for (final f in trace.contextFacts)
          {
            'key': f.key,
            'value': f.value,
            'label': f.label,
            'as_of': f.asOf.toUtc().toIso8601String(),
          },
      ],
      'data_gaps': [
        for (final g in trace.dataGaps)
          {'corridor': g.corridor, 'reason': g.reason},
      ],
      'confidence_band': trace.confidenceBand.wireValue,
    };

    return FactSet._(json, List.unmodifiable(factPaths));
  }

  final Map<String, Object?> _json;
  final List<String> _factPaths;

  /// The JSON-safe payload to embed in an on-device prompt string or POST as
  /// a cloud request body — a *redacted subset* of `DecisionTrace.toJson()`,
  /// never the trace object itself. Contains no raw coordinate pair and no
  /// user/device identifier (see this file's top-level doc comment).
  Map<String, Object?> toJson() => Map.unmodifiable(_json);

  /// Every `DecisionTrace` field path this fact set drew from — the same
  /// path syntax `renderTemplate`'s `factsUsed` uses (e.g.
  /// `"alternatives[0].blocking_edges[0].street_name"`).
  ///
  /// **Honest scope note.** This is the set of facts made *available* to a
  /// rewriter, not a verified account of which facts its free-form output
  /// actually drew on — unlike Tier 0's `renderTemplate`, which builds its
  /// `factsUsed` compositionally sentence by sentence, a Tier ≥ 1 rewriter
  /// produces prose this codebase does not attempt to attribute word-by-word
  /// back to individual fields (that would be a materially larger NLP-shaped
  /// undertaking, the same kind of bounded gap `pulse_explain`'s verifier
  /// already discloses for its own coherence checks). Callers pass this as
  /// `verifyOrFallback`'s `candidateFactsUsed` — the *ground truth* the text
  /// is checked against is still the full trace via [verify]/[verifyOrFallback]
  /// regardless of what this list claims, so an over-broad `factsUsed` here
  /// cannot let an ungrounded claim through.
  List<String> get availableFactPaths => _factPaths;
}
