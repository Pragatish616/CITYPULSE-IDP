/// The symbolic verifier — `docs/CONTRACTS.md` §4's six rules, `T4.2`
/// (`docs/IMPLEMENTATION_PLAN.md`). **Build this before T4.3**: the
/// verifier is the contribution being measured; the SLM is the thing under
/// test (`docs/DECISIONS.md` ADR-004).
///
/// **This package's reading of the six rules, documented rather than
/// silently assumed (`CLAUDE.md` §8.4):**
///
/// - **Rules 1–3** (numeral/entity grounding, comparative support) check
///   the candidate text against the trace, per `docs/CONTRACTS.md` §4.
/// - **Rule 4** ("no hedge-free assertion about an edge whose
///   `confidence_band` is low or stale") is checked against
///   `trace.confidenceBand` — the only confidence band the schema actually
///   carries. `BlockingEdge` has no `confidence_band` field of its own
///   (only raw `p_mean`/`n_eff`/age), so a genuinely per-edge reading of
///   rule 4 is not implementable against the current contract. This
///   implementation is therefore route-level: whenever the whole trace's
///   `confidence_band` is `low` or `stale`, the text must carry a hedge.
/// - **Rule 6** (ADR-011, added after `docs/CONTRACTS.md` §4's original
///   five rules) is exactly what ADR-011's own implementation note
///   prescribes: a denylist, applied here as the automatic first-pass
///   filter. ADR-011 is explicit that a denylist "will both over- and
///   under-trigger — that is expected, not a bug," and that its
///   precision/recall must be validated against Study 3's human-κ
///   subsample before it gates anything — that validation is T4.5/Study 3
///   work, not available yet. **Do not read a passing rule-6 check here as
///   meeting ADR-011's ≥95%-recall bar**; it is the mechanism the bar will
///   later be measured against.
/// - **Grounding tolerance** (rule 1's "within rounding tolerance declared
///   per field") is a fixed absolute tolerance per derived quantity — see
///   `_groundedNumbers` — wide enough to accept the nearest-integer display
///   form CityPulse itself ever renders (minutes, whole percent, one
///   decimal place of kilometres), not a general-purpose unit parser.
///
/// **`unsupported_claims` tagging convention (`ruleN:...`) — see
/// `docs/CONTRACTS.md` §4 for the canonical statement of this.** Rules 4 and
/// 6 have no dedicated boolean field in the wire schema's worked example, so
/// they surface only as tagged entries here; [VerificationResult.passed] is
/// `true` iff the list is empty regardless of which rule a tag names.
///
/// **Claim coherence, not just token grounding (added after independent
/// review — see the two checks below marked "coherence").** Checking that
/// every numeral and every proper noun individually appears *somewhere* in
/// the trace is not sufficient: a sentence can assemble real facts about
/// *different* parts of the trace into a claim that, taken as a whole, is
/// fabricated — for example, borrowing a real edge's observation age to
/// describe a *different* corridor that the trace's own `data_gaps` says has
/// no observations at all. Two targeted checks close the two concrete
/// exploits two independent reviews found:
/// - [_checkDataGapContradiction] rejects any sentence that names a
///   `data_gaps` corridor alongside a numeral, an avoidance claim, or a
///   hazard noun — a data gap means no observation exists there, so nothing
///   honest can be said about it beyond "no data." **The corridor's own name
///   is excluded from that scan** (see the function's doc comment) — a real
///   Chennai road name routinely contains a digit ("100 Feet Road", "2nd
///   Main Road"), and that digit is not a numeral *claim*, so it must not
///   trigger this check, and must not contaminate any *other* data-gap
///   corridor named in the same sentence either.
/// - [_checkComparatives]'s avoidance check, when the text names a specific
///   alternative's `route_id`, requires *that* alternative (not just *some*
///   alternative) to have a non-empty `blocking_edges`.
///
/// **Known residual scope boundary, disclosed rather than silently
/// accepted:** neither check performs general claim-to-fact binding. A
/// sentence that names one alternative's real street alongside a *different*
/// alternative's real numeral (with no `data_gaps` corridor and no named
/// `route_id` involved) is not caught — that would require binding every
/// numeral to the nearest grounded street mention, which is a materially
/// larger, NLP-shaped undertaking this task does not attempt. ADR-011
/// accepts exactly this class of imprecision for rule 6; the same tradeoff
/// applies here for the same reason: a documented, bounded gap beats an
/// unbounded parsing project this project's timeline does not have room for.
library;

import 'package:pulse_explain/src/explanation.dart';
import 'package:pulse_router/pulse_router.dart';

/// Verifies [text] against every fact [trace] actually contains, per
/// `docs/CONTRACTS.md` §4's six rules (see this file's top-level comment for
/// this package's documented reading of each rule, and its disclosed scope
/// boundary). [hazardDisplayNouns] is `config/hazard_classes.yaml`'s
/// `display_noun` column, keyed by `hazard_class` — optional (defaults to
/// empty) because a caller with no vocabulary to hand still gets rules 1–4
/// and 6 for free; without it, rule 2's hazard-noun check and the
/// hazard-noun half of the data-gap coherence check are skipped, since
/// neither can be evaluated without knowing what a hazard noun looks like.
///
/// Pure and deterministic other than [VerificationResult.latencyMs], which
/// is real wall-clock time (this is the number `docs/DECISIONS.md` ADR-004
/// promises is "<1 ms" for Tier 0 — measuring it for real, rather than
/// hard-coding it, is how that claim stays honest).
///
/// Never throws on malformed or adversarial [text] — an arbitrary string
/// (hand-written, or eventually SLM output) is exactly the input this
/// function exists to handle safely.
VerificationResult verify(
  String text,
  DecisionTrace trace, {
  Map<String, String> hazardDisplayNouns = const {},
}) {
  final stopwatch = Stopwatch()..start();

  final claims = <String>[
    ..._checkNumerals(text, trace),
    ..._checkTypedQuantities(text, trace),
    ..._checkEntities(text, trace),
    ..._checkHazardNouns(text, trace, hazardDisplayNouns),
    ..._checkComparatives(text, trace),
    ..._checkComparativeDirection(text, trace),
    ..._checkAvoidanceAttribution(text, trace, hazardDisplayNouns),
    ..._checkDataGapContradiction(text, trace, hazardDisplayNouns),
    ..._checkConfidenceHedge(text, trace),
    ..._checkNoAbsoluteSafetyClaim(text, trace),
  ];

  stopwatch.stop();

  return VerificationResult(
    numeralsGrounded: !claims.any((c) => c.startsWith('rule1:')),
    entitiesGrounded: !claims.any((c) => c.startsWith('rule2:')),
    contrastiveValid: !claims.any((c) => c.startsWith('rule3:')),
    unsupportedClaims: List.unmodifiable(claims),
    fallbackUsed: false,
    latencyMs: stopwatch.elapsedMicroseconds / 1000.0,
  );
}

/// Rule 5's fallback composition: run [candidateText] (tier [candidateTier],
/// facts [candidateFactsUsed]) through [verify]; if it passes, wrap it as
/// the returned [Explanation]. If it fails, **discard it silently** — per
/// `docs/CONTRACTS.md` §4 rule 5, the caller must never see the failing
/// text or be told verification failed — and return [tier0Fallback]'s
/// result instead, with `fallback_used` stamped `true`.
///
/// [tier0Fallback] must itself always pass (`renderTemplate` in
/// `template_renderer.dart` enforces this with a real runtime check, not
/// just a test) — this function does not re-verify the fallback, since a
/// failing fallback would have nowhere left to fall back to.
Explanation verifyOrFallback({
  required String candidateText,
  required int candidateTier,
  required List<String> candidateFactsUsed,
  required DecisionTrace trace,
  required String queryId,
  required Explanation Function() tier0Fallback,
  String locale = 'en',
  Map<String, String> hazardDisplayNouns = const {},
}) {
  final result = verify(
    candidateText,
    trace,
    hazardDisplayNouns: hazardDisplayNouns,
  );
  if (result.passed) {
    return Explanation(
      queryId: queryId,
      tier: candidateTier,
      text: candidateText,
      locale: locale,
      factsUsed: List.unmodifiable(candidateFactsUsed),
      verification: result,
    );
  }

  final fallback = tier0Fallback();
  return Explanation(
    queryId: fallback.queryId,
    tier: fallback.tier,
    text: fallback.text,
    locale: fallback.locale,
    factsUsed: fallback.factsUsed,
    verification: VerificationResult(
      numeralsGrounded: fallback.verification.numeralsGrounded,
      entitiesGrounded: fallback.verification.entitiesGrounded,
      contrastiveValid: fallback.verification.contrastiveValid,
      unsupportedClaims: fallback.verification.unsupportedClaims,
      fallbackUsed: true,
      latencyMs: fallback.verification.latencyMs,
    ),
  );
}

/// Splits [text] into sentences on `.`/`!`/`?` followed by whitespace, for
/// the coherence checks below that must reason about "the same sentence"
/// rather than "the whole multi-sentence text" — the granularity at which a
/// single claim is actually made.
List<String> _splitSentences(String text) =>
    text.split(RegExp(r'(?<=[.!?])\s+'));

// ---------------------------------------------------------------------------
// Rule 1 — numeral grounding
// ---------------------------------------------------------------------------

final RegExp _numeralPattern = RegExp(r'\d+(?:\.\d+)?%?');

/// One value this trace can honestly be said to contain, plus how much
/// display-rounding slack a match against it is allowed.
class _GroundedNumber {
  const _GroundedNumber(this.value, this.tolerance);
  final double value;
  final double tolerance;
}

/// Every name the trace supplies (street names, data-gap corridors,
/// context-fact labels), longest first.
List<String> _traceNames(DecisionTrace trace) {
  final names = <String>{};
  for (final alt in trace.alternatives) {
    for (final edge in alt.blockingEdges) {
      names.add(edge.streetName);
    }
  }
  for (final gap in trace.dataGaps) {
    names.add(gap.corridor);
  }
  for (final fact in trace.contextFacts) {
    names.add(fact.label);
  }
  return names.where((n) => n.trim().isNotEmpty).toList()
    ..sort((a, b) => b.length.compareTo(a.length));
}

/// [text] with every trace-supplied name replaced by a space. A real Chennai
/// street name can contain a digit ("100 Feet Road") or a word the safety
/// lexicon bans ("Dry Dock Road", "Open Road"); neither is a *claim*, so
/// claim scans run on the remainder.
String _stripEntityNames(String text, DecisionTrace trace) {
  var out = text;
  for (final name in _traceNames(trace)) {
    out = out.replaceAll(
      RegExp(RegExp.escape(name), caseSensitive: false),
      ' ',
    );
  }
  return out;
}

List<String> _checkNumerals(String text, DecisionTrace trace) {
  final grounded = _groundedNumbers(trace);
  final violations = <String>[];
  for (final match in _numeralPattern.allMatches(
    _stripEntityNames(text, trace),
  )) {
    final raw = match.group(0)!;
    final numeric = double.parse(
      raw.endsWith('%') ? raw.substring(0, raw.length - 1) : raw,
    );
    final isGrounded = grounded.any(
      (g) => (g.value - numeric).abs() <= g.tolerance,
    );
    if (!isGrounded) {
      violations.add('rule1:numeral:$raw');
    }
  }
  return violations;
}

/// Every numeric quantity [trace] can honestly support a sentence about,
/// including the unit conversions CityPulse's own copy uses (minutes from
/// seconds, whole percent from a `[0,1]` probability, one-decimal
/// kilometres from metres) and the pairwise deltas the contract calls out
/// by name (`docs/CONTRACTS.md` §3: "`free_flow_duration_s` lets the
/// explanation say '4 minutes slower' truthfully").
List<_GroundedNumber> _groundedNumbers(DecisionTrace trace) {
  final out = <_GroundedNumber>[];

  void addSeconds(double seconds) {
    out
      ..add(_GroundedNumber(seconds, 0.5))
      ..add(_GroundedNumber(seconds / 60.0, 0.5));
  }

  void addMetres(double metres) {
    out
      ..add(_GroundedNumber(metres, 0.5))
      ..add(_GroundedNumber(metres / 1000.0, 0.05));
  }

  void addProbability(double p) {
    out
      ..add(_GroundedNumber(p, 0.005))
      ..add(_GroundedNumber(p * 100, 0.5));
  }

  void addPlain(double v, [double tolerance = 0.05]) {
    out.add(_GroundedNumber(v, tolerance));
  }

  addSeconds(trace.chosen.durationSeconds);
  addMetres(trace.chosen.distanceMeters);
  addSeconds(trace.chosen.freeFlowDurationSeconds);
  addSeconds(trace.chosen.hazardTimePenaltySeconds);
  addProbability(trace.chosen.worstEdgeP);

  addPlain(trace.z, 0.005);
  addPlain(trace.lambda, 0.005);

  for (final alt in trace.alternatives) {
    addSeconds(alt.durationSeconds);
    // The only honest "N minutes slower/faster" is free-flow against
    // free-flow. The old grounding also accepted `chosen.duration_s -
    // alt.duration_s`, which subtracts a hazard-penalised cost from a plain
    // driving time (KNOWN_FLAWS F-04 item 1, ADR-016), so a sentence built on
    // that number passed as "grounded".
    addSeconds(
      (trace.chosen.freeFlowDurationSeconds - alt.durationSeconds).abs(),
    );
    for (final edge in alt.blockingEdges) {
      addProbability(edge.pMean);
      addProbability(edge.pPessimistic);
      addPlain(edge.nEff);
      addSeconds(edge.newestObservationAgeSeconds);
      addSeconds(edge.timePenaltySeconds);
      if (edge.depthMm != null) addPlain(edge.depthMm!, 0.5);
    }
  }

  for (final fact in trace.contextFacts) {
    final value = fact.value;
    if (value is num) addPlain(value.toDouble(), 0.5);
  }

  return out;
}

// ---------------------------------------------------------------------------
// Rule 1, typed — a number must be the right *kind* of number
// ---------------------------------------------------------------------------

/// A number followed by a unit: "2 minutes", "31%", "8.4 km". The generic
/// grounding above accepts a numeral that matches *any* quantity in the trace,
/// so "8.4 minutes" (a distance in km) or "79 minutes ago" (a probability in
/// percent) passed (KNOWN_FLAWS F-05; 14 of 16 such cases were falsely
/// accepted in the 2 Oct 2026 baseline). This check requires the quantity to
/// match the unit it is written with.
final RegExp _quantityPattern = RegExp(
  r'(\d+(?:\.\d+)?)\s*'
  r'(%|per\s?cent\b|percent\b|kilomet(?:re|er)s?\b|km\b|millimet(?:re|er)s?\b|'
  r'mm\b|met(?:re|er)s?\b|m\b|minutes?\b|mins?\b|seconds?\b|secs?\b|'
  r'hours?\b|hrs?\b)',
  caseSensitive: false,
);

enum _Unit { percent, km, metres, millimetres, minutes, seconds, hours }

_Unit _unitOf(String raw) {
  final u = raw.toLowerCase().replaceAll(RegExp(r'\s'), '');
  if (u == '%' || u.startsWith('per')) return _Unit.percent;
  if (u.startsWith('kilo') || u == 'km') return _Unit.km;
  if (u.startsWith('milli') || u == 'mm') return _Unit.millimetres;
  if (u.startsWith('met') || u == 'm') return _Unit.metres;
  if (u.startsWith('min')) return _Unit.minutes;
  if (u.startsWith('sec')) return _Unit.seconds;
  return _Unit.hours;
}

/// Durations a trace can honestly call a *time*: free-flow driving times,
/// their differences, hazard penalties and report ages. `chosen.duration_s`
/// is deliberately absent -- it is the penalised cost the search minimised,
/// not a number of minutes anyone would spend (F-04 item 1).
class _TimeFacts {
  _TimeFacts(DecisionTrace trace) {
    void addTrip(double s) => trips.add(s);
    addTrip(trace.chosen.freeFlowDurationSeconds);
    penalties.add(trace.chosen.hazardTimePenaltySeconds);
    for (final alt in trace.alternatives) {
      addTrip(alt.durationSeconds);
      deltas.add(
        (trace.chosen.freeFlowDurationSeconds - alt.durationSeconds).abs(),
      );
      for (final edge in alt.blockingEdges) {
        penalties.add(edge.timePenaltySeconds);
        if (edge.hasObservation) ages.add(edge.newestObservationAgeSeconds);
      }
    }
  }

  final List<double> trips = [];
  final List<double> deltas = [];
  final List<double> penalties = [];
  final List<double> ages = [];

  Iterable<double> get all => [...trips, ...deltas, ...penalties, ...ages];
}

bool _near(double value, Iterable<double> facts, double tolerance) =>
    facts.any((f) => (f - value).abs() <= tolerance);

List<String> _checkTypedQuantities(String text, DecisionTrace trace) {
  final stripped = _stripEntityNames(text, trace);
  final time = _TimeFacts(trace);
  final probabilities = <double>[
    trace.chosen.worstEdgeP,
    for (final alt in trace.alternatives)
      for (final e in alt.blockingEdges) ...[e.pMean, e.pPessimistic],
  ];
  final depths = <double>[
    for (final alt in trace.alternatives)
      for (final e in alt.blockingEdges)
        if (e.depthMm != null) e.depthMm!,
  ];

  final violations = <String>[];
  for (final m in _quantityPattern.allMatches(stripped)) {
    final value = double.parse(m.group(1)!);
    final unit = _unitOf(m.group(2)!);
    final label = m.group(0)!.trim();
    final after = stripped.substring(m.end).toLowerCase();

    final bool ok;
    switch (unit) {
      case _Unit.percent:
        ok = _near(value, probabilities.map((p) => p * 100), 0.5);
      case _Unit.km:
        ok = _near(value, [trace.chosen.distanceMeters / 1000], 0.05);
      case _Unit.metres:
        ok = _near(value, [trace.chosen.distanceMeters], 0.5);
      case _Unit.millimetres:
        ok = _near(value, depths, 0.5);
      case _Unit.seconds:
        ok = _near(value, time.all, 0.5);
      case _Unit.hours:
        ok = _near(value, time.all.map((s) => s / 3600), 0.05);
      case _Unit.minutes:
        // Subject binding: the word after the number says which fact it is.
        if (RegExp(r'^\s*(?:slower|faster|quicker|longer|shorter)\b')
            .hasMatch(after)) {
          ok = _near(value, time.deltas.map((s) => s / 60), 0.5);
        } else if (RegExp(r'^\s*(?:ago|old)\b').hasMatch(after)) {
          ok = _near(value, time.ages.map((s) => s / 60), 0.5);
        } else {
          ok = _near(value, time.all.map((s) => s / 60), 0.5);
        }
    }
    if (!ok) violations.add('rule1:numeral_unit:$label');
  }
  return violations;
}

// ---------------------------------------------------------------------------
// Rule 2 — entity grounding
// ---------------------------------------------------------------------------

final RegExp _capitalizedWordPattern = RegExp(r"\b[A-Z][a-zA-Z']*\b");

/// Function words and this package's own fixed template vocabulary that are
/// capitalized (usually by sentence position) without being proper nouns.
/// A heuristic allowlist, not a grammar — see this file's top-level note on
/// rule 2's accepted imprecision.
const Set<String> _entityStopWords = {
  'Route',
  'It',
  'This',
  'That',
  'There',
  'No',
  'Not',
  'Use',
  'Your',
  'You',
  'We',
  'I',
  'The',
  'A',
  'An',
  'Hazard',
  'Data',
  'Confidence',
  'Always',
  'Its',
  'For',
  'On',
  'At',
  'Is',
  'Are',
};

List<String> _checkEntities(String text, DecisionTrace trace) {
  final grounded = _groundedEntityWords(trace);
  final violations = <String>[];
  for (final match in _capitalizedWordPattern.allMatches(text)) {
    final word = match.group(0)!;
    if (_entityStopWords.contains(word)) continue;
    if (grounded.contains(word)) continue;
    violations.add('rule2:entity:$word');
  }
  return violations;
}

final RegExp _wordPattern = RegExp("[A-Za-z']+");

/// Every individual word that appears in a trace-supplied name or label —
/// street names, alternative-route corridors, context-fact labels, and the
/// route ids themselves (`chosen.route_id` / `alternatives[].route_id`,
/// which is how "Route A" grounds "A").
Set<String> _groundedEntityWords(DecisionTrace trace) {
  final words = <String>{trace.chosen.routeId};
  void addPhrase(String phrase) {
    for (final m in _wordPattern.allMatches(phrase)) {
      words.add(m.group(0)!);
    }
  }

  for (final alt in trace.alternatives) {
    words.add(alt.routeId);
    for (final edge in alt.blockingEdges) {
      addPhrase(edge.streetName);
    }
  }
  for (final gap in trace.dataGaps) {
    addPhrase(gap.corridor);
  }
  for (final fact in trace.contextFacts) {
    addPhrase(fact.label);
  }
  return words;
}

/// **Rule 2 extension, documented rather than silently added.**
/// `docs/CONTRACTS.md` §4 rule 2 names "proper noun," which a hazard class's
/// display noun (e.g. "flooding") is not — but a wrong hazard noun is
/// exactly the kind of invented fact `CLAUDE.md` §3.5 ("the LLM never
/// invents facts") and rule 1/2's grounding principle exist to catch, and it
/// slips past every other check (it is neither a numeral nor a capitalized
/// word). This closes that gap: a display noun belonging to a hazard class
/// that is not present on *any* blocking edge anywhere in [trace] may not
/// appear in [text]. Requires [hazardDisplayNouns]; a no-op without it
/// (there is no vocabulary to check against).
List<String> _checkHazardNouns(
  String text,
  DecisionTrace trace,
  Map<String, String> hazardDisplayNouns,
) {
  if (hazardDisplayNouns.isEmpty) return const [];
  final lower = text.toLowerCase();
  final presentClasses = <String>{
    for (final alt in trace.alternatives)
      for (final edge in alt.blockingEdges) edge.hazardClass,
  };

  final violations = <String>[];
  for (final entry in hazardDisplayNouns.entries) {
    if (presentClasses.contains(entry.key)) continue;
    final noun = entry.value.trim().toLowerCase();
    if (noun.isEmpty) continue;
    if (lower.contains(noun)) {
      violations.add('rule2:hazard_noun:${entry.value}');
    }
  }
  return violations;
}

// ---------------------------------------------------------------------------
// Rule 3 — comparative claims
// ---------------------------------------------------------------------------

const List<String> _speedComparatives = ['slower', 'faster', 'quicker'];
const List<String> _avoidanceComparatives = [
  'avoids',
  'avoiding',
  'avoided',
  'bypass',
  'steers clear',
  'steer clear',
  'skips',
  'stays away',
  'stay away',
];

/// Matches the verb phrase of an avoidance claim, so the checks below can
/// look at what comes before it (the subject) and after it (the object).
final RegExp _avoidanceVerbPattern = RegExp(
  r'\b(?:avoid(?:s|ing|ed)?|bypass(?:es|ing|ed)?|steers? clear of|skips?|'
  r'stays? away from)\b',
  caseSensitive: false,
);

List<String> _checkComparatives(String text, DecisionTrace trace) {
  final lower = text.toLowerCase();
  final violations = <String>[];

  final claimsSpeedComparison = _speedComparatives.any(lower.contains);
  if (claimsSpeedComparison && trace.alternatives.isEmpty) {
    violations.add('rule3:comparative:speed_claim_without_alternative');
  }

  final claimsAvoidance = _avoidanceComparatives.any(lower.contains);
  if (claimsAvoidance) {
    // Coherence, not just presence (see this file's top-level note): if the
    // text names a specific alternative by its route_id, *that* alternative
    // must be the one carrying the blocking edge -- "some alternative,
    // somewhere, has a blocking edge" is not enough once the text points at
    // a particular one. With no route_id named, fall back to "any."
    final mentionedRouteIds = _mentionedAlternativeRouteIds(text, trace);
    final relevantAlternatives = mentionedRouteIds.isEmpty
        ? trace.alternatives
        : trace.alternatives.where(
            (a) => mentionedRouteIds.contains(a.routeId),
          );
    final supported = relevantAlternatives.any(
      (a) => a.blockingEdges.isNotEmpty,
    );
    if (!supported) {
      violations.add('rule3:comparative:avoids_without_blocking_edge');
    }
  }

  return violations;
}

final RegExp _routeMentionPattern = RegExp(r'\bRoute ([A-Z])\b');

final RegExp _comparatorPattern = RegExp(
  r'\b(slower|faster|quicker|longer|shorter|saves?|beats?|sooner)\b',
  caseSensitive: false,
);

/// Rule 3, direction. The old check only asked "is there *an* alternative?"
/// for "slower"/"faster", so "Route A is 2 minutes faster" passed when Route
/// A was in fact slower (KNOWN_FLAWS F-05; 15 of 15 reversed comparisons were
/// falsely accepted in the 2 Oct 2026 baseline). This compares the claimed
/// direction with the trace, free-flow against free-flow, and ignores
/// differences within [_directionToleranceSeconds] (the template itself says
/// "about the same" below half a minute).
const double _directionToleranceSeconds = 30;

List<String> _checkComparativeDirection(String text, DecisionTrace trace) {
  if (trace.alternatives.isEmpty) return const [];
  final times = <String, double>{
    trace.chosen.routeId: trace.chosen.freeFlowDurationSeconds,
    for (final alt in trace.alternatives) alt.routeId: alt.durationSeconds,
  };

  final violations = <String>[];
  for (final sentence in _splitSentences(text)) {
    final cm = _comparatorPattern.firstMatch(sentence);
    if (cm == null) continue;
    final word = cm.group(1)!.toLowerCase();

    final before = [
      for (final m in _routeMentionPattern.allMatches(
        sentence.substring(0, cm.start),
      ))
        m.group(1)!,
    ];
    final after = [
      for (final m in _routeMentionPattern.allMatches(
        sentence.substring(cm.end),
      ))
        m.group(1)!,
    ];

    // The subject is the route named closest before the comparative
    // ("Compared with Route B, Route A is faster" -> A), else the first one
    // after it. A comparative that names no route cannot be bound to the
    // trace here and is left to the other rules.
    final subject = before.isNotEmpty
        ? before.last
        : (after.isNotEmpty ? after.first : null);
    if (subject == null || !times.containsKey(subject)) continue;

    String? other;
    for (final id in [...after, ...before.reversed]) {
      if (id != subject && times.containsKey(id)) {
        other = id;
        break;
      }
    }
    // "Route A is faster." names one route: compare it with the other end
    // of the trace's chosen-vs-best-alternative pair.
    other ??= subject == trace.chosen.routeId
        ? trace.alternatives.first.routeId
        : trace.chosen.routeId;

    final diff = times[subject]! - times[other]!;
    final claimsSlower = word == 'slower' || word == 'longer';
    if (claimsSlower && diff < -_directionToleranceSeconds ||
        !claimsSlower && diff > _directionToleranceSeconds) {
      violations.add('rule3:comparative:direction:$subject $word');
    }
  }
  return violations;
}

/// Rule 3, attribution. "Route B avoids the flooding on X" was accepted
/// because Route B really does have a blocking edge -- it is the route that
/// *crosses* X. An avoidance claim must be made about the chosen route, and
/// what it avoids must be something the trace actually names.
List<String> _checkAvoidanceAttribution(
  String text,
  DecisionTrace trace,
  Map<String, String> hazardDisplayNouns,
) {
  if (trace.alternatives.isEmpty) return const [];
  final chosenId = trace.chosen.routeId;
  final alternativeIds = {for (final a in trace.alternatives) a.routeId};

  final groundedObjects = <String>{
    for (final alt in trace.alternatives)
      for (final edge in alt.blockingEdges) ...[
        edge.streetName.toLowerCase(),
        edge.hazardClass.toLowerCase(),
        (hazardDisplayNouns[edge.hazardClass] ?? '').toLowerCase(),
      ],
    'the hazard',
    'the flooded stretch',
  }..remove('');

  final violations = <String>[];
  for (final sentence in _splitSentences(text)) {
    final m = _avoidanceVerbPattern.firstMatch(sentence);
    if (m == null) continue;

    final subjects = _routeMentionPattern
        .allMatches(sentence.substring(0, m.start))
        .map((x) => x.group(1)!)
        .toList();
    if (subjects.isNotEmpty) {
      final subject = subjects.last;
      if (alternativeIds.contains(subject) && subject != chosenId) {
        violations.add(
          'rule3:comparative:avoidance_attributed_to_rejected_route:$subject',
        );
      }
    }

    final clause = sentence
        .substring(m.end)
        .split(RegExp(r'[.;!?]'))
        .first
        .toLowerCase();
    if (!groundedObjects.any(clause.contains)) {
      violations.add('rule3:comparative:avoids_ungrounded_object');
    }
  }
  return violations;
}

/// Every `alternatives[].route_id` that literally appears in [text].
Set<String> _mentionedAlternativeRouteIds(String text, DecisionTrace trace) {
  final altIds = {for (final a in trace.alternatives) a.routeId};
  return {
    for (final m in _capitalizedWordPattern.allMatches(text))
      if (altIds.contains(m.group(0))) m.group(0)!,
  };
}

// ---------------------------------------------------------------------------
// Data-gap coherence (folded into rule 3: a claim the trace cannot support)
// ---------------------------------------------------------------------------

/// **Coherence check, added after independent review found the exploit this
/// closes.** `data_gaps[]` means "no observations in window" — the corridor
/// has no hazard fact to report. A sentence that names a `data_gaps`
/// corridor *and* also carries a numeral, an avoidance claim, or a hazard
/// noun is contradicting the trace's own statement that there is nothing to
/// report there, even though every individual token in it might otherwise
/// ground cleanly against some *other*, unrelated fact elsewhere in the
/// trace. Sentence-scoped (see [_splitSentences]): a data-gap corridor
/// named in one sentence does not contaminate a claim made in another.
///
/// **Corridor-name-digit regression (found via `app/`'s T5.1 integration
/// test against real OSM street names, not a synthetic fixture).** A real
/// Chennai road name routinely contains a digit ("100 Feet Road", "2nd Main
/// Road", "Vijayanagar 1st Main Road"). Scanning the *whole* sentence for a
/// numeral, as an earlier version of this function did, means a
/// digit-named corridor's own name is misread as a numeral *claim* — and
/// because the scan wasn't scoped to the individual gap, it also falsely
/// contaminates every *other* data-gap corridor named in the same sentence,
/// even one with a plain, digit-free name. Both `renderTemplate` (this
/// package) and the demo route in `app/` hit exactly this the first time a
/// real digit-named street appeared in `data_gaps`, and `renderTemplate` has
/// nowhere left to fall back to when its own Tier 0 output fails rule 3.
/// Fixed by stripping every data-gap corridor name actually present in the
/// sentence out of the text *before* scanning for a numeral/avoidance
/// claim/hazard noun — the corridor names themselves are never evidence of
/// a contradiction; only genuine additional content is.
List<String> _checkDataGapContradiction(
  String text,
  DecisionTrace trace,
  Map<String, String> hazardDisplayNouns,
) {
  if (trace.dataGaps.isEmpty) return const [];
  final violations = <String>[];
  for (final sentence in _splitSentences(text)) {
    final lower = sentence.toLowerCase();
    final presentGaps = trace.dataGaps
        .where((gap) => lower.contains(gap.corridor.toLowerCase()))
        .toList();
    if (presentGaps.isEmpty) continue;

    var remainder = lower;
    for (final gap in presentGaps) {
      remainder = remainder.replaceAll(gap.corridor.toLowerCase(), ' ');
    }

    final hasNumeral = _numeralPattern.hasMatch(remainder);
    final hasAvoidance = _avoidanceComparatives.any(remainder.contains);
    final hasHazardNoun = hazardDisplayNouns.values.any(
      (noun) =>
          noun.trim().isNotEmpty && remainder.contains(noun.toLowerCase()),
    );
    if (hasNumeral || hasAvoidance || hasHazardNoun) {
      for (final gap in presentGaps) {
        violations.add('rule3:data_gap_contradiction:${gap.corridor}');
      }
    }
  }
  return violations;
}

// ---------------------------------------------------------------------------
// Rule 4 — hedge required under low/stale confidence
// ---------------------------------------------------------------------------

const List<String> _hedgeMarkers = [
  'unverified',
  'unconfirmed',
  'limited',
  'no recent data',
  'not confirmed',
  'not a guarantee',
  'use your own judgement',
  'use your own judgment',
  'may not',
  'uncertain',
  'out of date',
  "don't have",
  'do not have',
  'no data',
  'not certain',
  'unclear',
  'low confidence',
  'stale',
  // Tamil: "data is limited", "use your own judgement", "not certain".
  'தரவு குறைவு',
  'தகவல் குறைவு',
  'உங்கள் சொந்த முடிவை',
  'உறுதி இல்லை',
];

List<String> _checkConfidenceHedge(String text, DecisionTrace trace) {
  final needsHedge =
      trace.confidenceBand == ConfidenceBand.low ||
      trace.confidenceBand == ConfidenceBand.stale;
  if (!needsHedge) return const [];

  final lower = text.toLowerCase();
  final hasHedge = _hedgeMarkers.any(lower.contains);
  return hasHedge ? const [] : const ['rule4:unhedged_low_confidence'];
}

// ---------------------------------------------------------------------------
// Rule 6 — no unhedged affirmative-safety claim (ADR-011)
// ---------------------------------------------------------------------------

/// First-pass denylist per ADR-011's implementation note. Deliberately a
/// flat substring list, not an attempt at negation-aware parsing — ADR-011
/// accepts over/under-triggering here as a known, documented limitation
/// pending Study 3's human-κ validation.
const List<String> _absoluteSafetyPhrases = [
  'is safe',
  'is clear',
  'is passable',
  'safe to drive',
  'safe to travel',
  'safe to use',
  'clear to drive',
  'clear to travel',
  'nothing to worry',
  'no issues',
  'no problem',
  'all clear',
  'should be fine',
  'perfectly fine',
  'completely safe',
  'totally safe',
  'guaranteed safe',
  'safe route',
  'safe option',
  'road is open and safe',
  'you can safely',
];

/// Second-layer lexicon (KNOWN_FLAWS F-05, PLAN.md M1.4). The flat phrase list
/// above matched 20 exact strings and so missed "the bridge is dry now, go
/// ahead", "you can drive through ...", "no water on ..." and every Tamil
/// sentence (35 of 50 templated and 16 of 20 "dry/clear/open" cases were
/// falsely accepted in the 2 Oct 2026 baseline).
///
/// **Deliberately fail-closed.** These patterns match a word wherever it
/// appears, including negated ("not unsafe") or hedged ("probably safe, but
/// ...") forms, because a negation parser is exactly the thing that fails on a
/// paraphrase. A false reject only costs the user a plainer Tier 0 sentence; a
/// false accept tells someone a flooded road is fine. Trace-supplied street
/// names are removed before matching so "Dry Dock Road" does not trip it.
final List<RegExp> _safetyPatterns = [
  r'\b(?:safe|safely|safest|safer|unsafe)\b',
  r'\b(?:dry|dried|dries|drying|drained|receded|recedes|subsided|clear|clears|'
      r'cleared|clearing)\b',
  r'\b(?:passable|open|opened|reopened|re-opened|usable|unblocked|unobstructed|'
      r'unaffected)\b',
  r'\bgo(?:ing)? ahead\b|\bgood to go\b|\bfeel free\b|\bproceed\b|\bcarry on\b',
  r'\b(?:fine|ok|okay)\b',
  r'\bno (?:water|flood(?:ing|s)?|waterlogging|hazards?|risks?|danger|dangers|'
      r'problems?|issues?|obstruction|blockage|worries)\b',
  r'\bnot (?:flooded|waterlogged|blocked|at risk|dangerous)\b',
  r'\b(?:free|clear) (?:of|from) \w+',
  r'\b(?:hazard|risk|flood)[- ]free\b',
  r'\bnothing (?:to worry|wrong|dangerous|to fear)\b|\bno need to worry\b|'
      r'\brelax\b',
  r"\b(?:won'?t|wouldn'?t|will not|would not) "
      r'(?:flood|have|be flooded|face|see|encounter|meet|find|get)\b|'
      r'\bzero risk\b',
  // State-change claims the trace cannot support: the water is gone.
  r'\bno longer\b|\b(?:is|are|was|has been|have been) '
      r'(?:over|gone|finished|ended)\b|\bhas (?:ended|stopped|passed)\b',
  // "can/may/able to" + a movement verb: permission to travel.
  r'\b(?:can|could|may|might|able to|allowed to)(?: be)?(?: able to)?\s+'
      r'(?:safely\s+)?(?:pass|passed|cross|crossed|drive|ride|go|get through|'
      r'travel|proceed|take|taken|use|used|continue)\b',
  r'\b(?:is|are) (?:running|moving)\b|\bnormally\b|\bback to normal\b|'
      r'\bas usual\b|\bit works\b',
].map((p) => RegExp(p, caseSensitive: false)).toList();

/// Tamil safety / dryness / passability stems, matched as substrings (Tamil
/// is agglutinative, so `\b` does not apply). **Written without a native
/// speaker's review -- treat as a starting list and have a Tamil reader extend
/// it before any Tamil explanation ships.** It also matches the legitimate
/// hedge "no guarantee of safety" (fail-closed).
const List<String> _tamilSafetyStems = [
  'பாதுகாப்',
  'வறண்',
  'காய்ந்',
  'செல்லலாம்',
  'போகலாம்',
  'கடக்கலாம்',
  'தொடரலாம்',
  'திறந்',
  'தெளிவாக',
  'வெள்ளமின்றி',
  'வடிந்',
  'தேங்கவில்லை',
  'தண்ணீர் இல்லை',
  'நீர் இல்லை',
  'வெள்ளம் இல்லை',
  'பிரச்சனை இல்லை',
  'ஆபத்தும் இல்லை',
  'ஆபத்து இல்லா',
  'தடையும் இல்லை',
  'கவலைப்பட வேண்டாம்',
  'சரியாக உள்ளது',
];

List<String> _checkNoAbsoluteSafetyClaim(String text, DecisionTrace trace) {
  final lower = _stripEntityNames(text, trace).toLowerCase();
  final violations = <String>[];
  for (final phrase in _absoluteSafetyPhrases) {
    if (lower.contains(phrase)) {
      violations.add('rule6:unhedged_safety_claim:$phrase');
    }
  }
  for (final pattern in _safetyPatterns) {
    for (final m in pattern.allMatches(lower)) {
      final hit = m.group(0)!.trim();
      final tag = 'rule6:unhedged_safety_claim:$hit';
      if (!violations.contains(tag)) violations.add(tag);
    }
  }
  for (final stem in _tamilSafetyStems) {
    if (lower.contains(stem)) {
      violations.add('rule6:unhedged_safety_claim:$stem');
    }
  }
  return violations;
}
