/// The Tier 0 deterministic template renderer — `T4.1`
/// (`docs/IMPLEMENTATION_PLAN.md`), `docs/DECISIONS.md` ADR-004. A pure
/// function `DecisionTrace -> Explanation` that runs always, costs well
/// under a millisecond, and is the permanent fallback for every other tier.
///
/// **Scope, per T4.1's acceptance criteria — covers exactly four things:**
/// the chosen-vs-best-alternative delta, the top blocking edge, the
/// confidence band, and a data-gap sentence when `data_gaps` is non-empty.
/// `context_facts` is not rendered here — nothing in T4.1's acceptance
/// criteria calls for it, and every sentence this renderer adds is another
/// surface the verifier and the ADR-011 audit below have to cover; add it
/// as a deliberate follow-up task, not a silent scope increase here.
///
/// **ADR-011 implementation note (a), satisfied by construction:** this
/// renderer's fixed sentence vocabulary is a small, closed, human-authored
/// set (the string literals below) that never uses the words "safe",
/// "clear", "passable", or any other phrase on the rule-6 denylist
/// (`verifier.dart`) — audited by hand here, and pinned as a fixed test
/// fixture in `test/template_renderer_test.dart` per ADR-011's own
/// instruction not to "ship rule 6 as a single unvalidated regex and call
/// it done."
library;

import 'package:pulse_explain/src/explanation.dart';
import 'package:pulse_explain/src/verifier.dart';
import 'package:pulse_router/pulse_router.dart';

/// Renders [trace] as Tier 0 `Explanation`. [hazardDisplayNouns] is the
/// `display_noun` column of `config/hazard_classes.yaml`, keyed by
/// `hazard_class` — loaded by the caller, never duplicated here
/// (`docs/CONTRACTS.md` §5: config lives in one place). A hazard class with
/// no entry falls back to its raw wire string rather than crashing, so a
/// newly added hazard class degrades to a slightly less friendly noun
/// instead of failing every explanation for every route that touches it.
///
/// This function always returns an [Explanation] whose
/// `verification.passed` is `true` — it verifies its own output before
/// returning, using the same [verify] every other tier is checked with, and
/// **enforces the guarantee with a real, non-strippable check, not just a
/// doc comment or a test fixture** (a 2026-09 security review's general
/// finding, applied here per this codebase's established convention — see
/// e.g. `ChosenRoute`'s constructor and `classifyConfidence`'s NaN guard in
/// `pulse_router`): if this ever fails — a future `hazardDisplayNouns` entry
/// or an unmapped `hazard_class`/OSM street name containing, say, a rule-6
/// denylist word or an ungroundable capitalized word — it throws instead of
/// silently returning an unverified [Explanation], because per
/// `docs/CONTRACTS.md` §4 rule 5 a failing Tier 0 fallback has nowhere left
/// to fall back to, and [verifyOrFallback] deliberately does not re-verify
/// it.
Explanation renderTemplate({
  required DecisionTrace trace,
  required Map<String, String> hazardDisplayNouns,
  String locale = 'en',
}) {
  final factsUsed = <String>[];

  // Evaluated left to right, so factsUsed accumulates in the same order the
  // sentences below eventually appear in.
  final sentences = <String?>[
    _deltaSentence(trace, factsUsed),
    _blockingEdgeSentence(trace, hazardDisplayNouns, factsUsed),
    _confidenceSentence(trace, factsUsed),
    _dataGapSentence(trace, factsUsed),
  ].whereType<String>();

  final text = sentences.join(' ');
  final verification = verify(
    text,
    trace,
    hazardDisplayNouns: hazardDisplayNouns,
  );

  if (!verification.passed) {
    throw StateError(
      'renderTemplate (T4.1) produced text that failed its own verify() -- '
      'this must never happen (docs/CONTRACTS.md §4 rule 5: "never show an '
      'unverified explanation"; verifyOrFallback does not re-verify Tier 0). '
      'text: "$text". violations: ${verification.unsupportedClaims}.',
    );
  }

  return Explanation(
    queryId: trace.queryId,
    tier: 0,
    text: text,
    locale: locale,
    factsUsed: List.unmodifiable(factsUsed),
    verification: verification,
  );
}

/// The fixed sentence shown when [renderTemplate] itself fails. It uses only
/// words already on the verifier's allowlist, carries no number, name or
/// claim about any road, and holds the hedge that rule 4 demands under low
/// or stale confidence.
const String kMinimalExplanationText =
    'Route A is shown. Hazard data may be limited, so use your own judgement.';

/// [renderTemplate] that cannot throw (KNOWN_FLAWS F-07, ADR-016).
///
/// `renderTemplate` deliberately throws if its own text fails `verify()`,
/// because a failing Tier 0 has nothing to fall back to. That is the right
/// behaviour for a library but the wrong one for a screen: the old app let
/// the `StateError` escape, showed no route at all, and printed the
/// unverified text in an error banner. This wrapper turns the failure into
/// [kMinimalExplanationText], reports it through [onFailure] for logging and
/// counting, and **never returns or logs the failing text to the user**.
///
/// The returned [Explanation] is `fallbackUsed: true` so the failure shows up
/// in the verification pass rate rather than disappearing.
Explanation renderTemplateSafe({
  required DecisionTrace trace,
  required Map<String, String> hazardDisplayNouns,
  String locale = 'en',
  void Function(Object error)? onFailure,
}) {
  try {
    return renderTemplate(
      trace: trace,
      hazardDisplayNouns: hazardDisplayNouns,
      locale: locale,
    );
  } on Object catch (error) {
    onFailure?.call(error);
    final verification = verify(
      kMinimalExplanationText,
      trace,
      hazardDisplayNouns: hazardDisplayNouns,
    );
    return Explanation(
      queryId: trace.queryId,
      tier: 0,
      text: kMinimalExplanationText,
      locale: locale,
      factsUsed: const ['chosen.route_id'],
      verification: VerificationResult(
        numeralsGrounded: verification.numeralsGrounded,
        entitiesGrounded: verification.entitiesGrounded,
        contrastiveValid: verification.contrastiveValid,
        unsupportedClaims: verification.unsupportedClaims,
        fallbackUsed: true,
        latencyMs: verification.latencyMs,
      ),
    );
  }
}

String _plural(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';

/// Rounds a seconds duration to whole minutes for display. `0` collapses
/// callers into a "moments"/"about the same" phrasing instead — see call
/// sites — so this never has to render the slightly odd "0 minutes ago".
int _minutes(double seconds) => (seconds / 60.0).round();

String _deltaSentence(DecisionTrace trace, List<String> factsUsed) {
  factsUsed
    ..add('chosen.route_id')
    ..add('chosen.duration_s');
  if (trace.alternatives.isEmpty) {
    return 'Route ${trace.chosen.routeId} is the only route found for this '
        'trip.';
  }

  final alt = trace.alternatives.first;
  factsUsed
    ..add('alternatives[0].route_id')
    ..add('alternatives[0].duration_s')
    ..add('chosen.free_flow_duration_s');

  // Free-flow against free-flow (KNOWN_FLAWS F-04 item 1, ADR-016). The
  // alternative's duration is the plain driving time of the fastest route.
  // `chosen.duration_s` is the hazard-*penalised* cost the search minimised;
  // subtracting the two compared a cost with a time and overstated how much
  // longer the chosen route takes. `chosen.free_flow_duration_s` is the
  // chosen route's own driving time, so the difference is a real number of
  // minutes the traveller would spend.
  final deltaSeconds =
      trace.chosen.freeFlowDurationSeconds - alt.durationSeconds;
  final deltaMinutes = _minutes(deltaSeconds.abs());

  if (deltaMinutes == 0) {
    return 'Route ${trace.chosen.routeId} takes about the same time as '
        'Route ${alt.routeId}.';
  }
  final direction = deltaSeconds > 0 ? 'slower' : 'faster';
  return 'Route ${trace.chosen.routeId} is ${_plural(deltaMinutes, 'minute')} '
      '$direction than Route ${alt.routeId}.';
}

String? _blockingEdgeSentence(
  DecisionTrace trace,
  Map<String, String> hazardDisplayNouns,
  List<String> factsUsed,
) {
  if (trace.alternatives.isEmpty) return null;
  final blockingEdges = trace.alternatives.first.blockingEdges;
  if (blockingEdges.isEmpty) return null;

  final edge = blockingEdges.first;
  factsUsed
    ..add('alternatives[0].blocking_edges[0].hazard_class')
    ..add('alternatives[0].blocking_edges[0].street_name')
    ..add('alternatives[0].blocking_edges[0].newest_observation_age_s');

  final noun = hazardDisplayNouns[edge.hazardClass] ?? edge.hazardClass;

  // "A stretch of X" because the avoided segment is one edge: the chosen route
  // may well cross X elsewhere, and "avoids X" would then be false.

  // A prior-only edge has a hazard-map entry but no report at all. Saying
  // "reported moments ago" for it invented a report (KNOWN_FLAWS F-04 item 3,
  // ADR-016); say what is actually known instead.
  if (!edge.hasObservation) {
    return 'It avoids a stretch of ${edge.streetName} that the hazard map '
        'marks for $noun, where no report has been received.';
  }

  final ageMinutes = _minutes(edge.newestObservationAgeSeconds);
  final ageClause = ageMinutes <= 0
      ? 'moments ago'
      : '${_plural(ageMinutes, 'minute')} ago';

  return 'It avoids a stretch of ${edge.streetName} where $noun was reported '
      '$ageClause.';
}

String _confidenceSentence(DecisionTrace trace, List<String> factsUsed) {
  factsUsed.add('confidence_band');
  return switch (trace.confidenceBand) {
    ConfidenceBand.high => 'Hazard confidence for this route is high.',
    ConfidenceBand.moderate => 'Hazard confidence for this route is moderate.',
    ConfidenceBand.low =>
      'Hazard confidence for this route is low: there is limited recent '
          'hazard data for parts of it, not a guarantee about road '
          'conditions. Use your own judgement.',
    ConfidenceBand.stale =>
      'Hazard confidence for this route is stale: the most recent hazard '
          'data for parts of it is out of date, not a guarantee about '
          'current conditions. Use your own judgement.',
  };
}

String? _dataGapSentence(DecisionTrace trace, List<String> factsUsed) {
  if (trace.dataGaps.isEmpty) return null;
  for (var i = 0; i < trace.dataGaps.length; i++) {
    factsUsed.add('data_gaps[$i].corridor');
  }
  final corridors = trace.dataGaps.map((g) => g.corridor).join(', ');
  return 'No recent hazard data is available for $corridors -- absence of '
      'data is not the same as absence of hazard.';
}
