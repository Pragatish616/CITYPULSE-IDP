/// `DecisionTrace` (`docs/CONTRACTS.md` §3, T2.2) — the single object every
/// explanation layer (Tier 0 template, Tier 1 SLM, the verifier, the
/// evaluation harness) may read facts from. If a fact is not in this object,
/// no explanation may state it.
///
/// **Scope note (this task, not a silent addition to the contract):**
/// `docs/CONTRACTS.md` §3 specifies the *schema*, not an algorithm for
/// choosing which alternative routes to include or how many. This file
/// implements the schema and a builder that assembles a trace from
/// already-computed pieces (a chosen `RouteResult`, zero or more alternative
/// routes each already evaluated against the chance constraint, and
/// already-fused `EdgeBelief`-derived facts for any blocking edges) — it
/// does not itself decide *which* alternatives to search for. That
/// composition (e.g. k-shortest-paths, or re-routing with the chosen path's
/// edges removed) belongs to the caller (the CLI, T2.4, or a future query
/// orchestrator).
///
/// **Documentation discrepancy found while implementing this (flag, don't
/// silently resolve, per `CLAUDE.md` §8):** `docs/CONTRACTS.md` §3's prose
/// says `free_flow_duration_s` is `chosen.duration_s` minus the best
/// alternative's duration, but its own worked example contradicts that
/// sentence: `1023 = 1147 − 124`, i.e. `free_flow_duration_s = duration_s −
/// hazard_time_penalty_s`, entirely within `chosen` and independent of
/// `alternatives`. This implementation follows the worked example (the
/// unambiguous, internally-consistent source), not the prose, and computes
/// `hazard_time_penalty_s = duration_s − free_flow_duration_s`.
library;

import 'dart:convert';
import 'dart:math' as math;

/// `mode` — whether this query ran with only the on-device belief state, or
/// enriched by a live server round-trip within its deadline (ADR-005).
enum RoutingMode {
  /// The client's own local belief state only; no network round-trip.
  offline,

  /// Enriched by a live server round-trip that completed within its
  /// deadline (ADR-005) — the local tier's answer is still the fallback.
  onlineEnriched;

  /// The exact string this enum serialises as in `DecisionTrace.mode`.
  String get wireValue => switch (this) {
    RoutingMode.offline => 'offline',
    RoutingMode.onlineEnriched => 'online_enriched',
  };
}

/// `user_class` — selects `z` and `λ` (`config/hazard_classes.yaml`).
enum UserClass {
  /// `z ≈ 0` — resents detours; the pessimistic band is nearly the mean.
  commuter,

  /// `z ≈ 2` — cannot afford to be wrong; the widest pessimistic band.
  emergency,

  /// `z ≈ 1.28`; also uses a lower depth threshold (`h_max_mm_pedestrian`).
  pedestrian,

  /// A bicycle (ADR-019). `z` and `λ` are placeholders between the pedestrian and
  /// the car; its speeds and road access come from the `bicycle` travel profile.
  cyclist;

  /// The exact string this enum serialises as in `DecisionTrace.user_class`.
  String get wireValue => name;
}

/// `confidence_band` — shown to the user; no single-color "all clear"
/// (ADR-011). **Placeholder classification pending calibration** — see
/// `classifyConfidence` below.
enum ConfidenceBand {
  /// Plenty of fresh evidence.
  high,

  /// Some evidence, but thinner or older than [high].
  moderate,

  /// Little or no evidence — absence of data, not evidence of safety.
  low,

  /// There was evidence once, but it has decayed past the point the model
  /// treats it as current.
  stale;

  /// The exact string this enum serialises as in `confidence_band`.
  String get wireValue => name;
}

/// `alternatives[].rejected_because`.
enum RejectedBecause {
  /// The route was removed outright by the hard chance constraint
  /// (`Pr[depth > h_max] ≤ ε`, ADR-003) — never a large finite weight.
  chanceConstraint,

  /// The route survived costing but lost to the chosen route on total cost.
  higherCost;

  /// The exact string this enum serialises as in `rejected_because`.
  String get wireValue => switch (this) {
    RejectedBecause.chanceConstraint => 'chance_constraint',
    RejectedBecause.higherCost => 'higher_cost',
  };
}

/// Reads a required field of type [T], turning a missing or mistyped value
/// into a [FormatException] that names the field. The JSON may come from a
/// server or a cache, so it is validated, not trusted.
T _field<T>(Map<String, Object?> json, String key, String where) {
  final value = json[key];
  if (value is T) return value;
  throw FormatException(
    '$where: field "$key" is missing or is not a $T: $value',
  );
}

double _number(Map<String, Object?> json, String key, String where) =>
    _field<num>(json, key, where).toDouble();

T _byWire<T>(
  Iterable<T> values,
  String Function(T) wire,
  String raw,
  String what,
) {
  for (final v in values) {
    if (wire(v) == raw) return v;
  }
  throw FormatException('unknown $what "$raw"');
}

String _rfc3339(DateTime t) {
  assert(t.isUtc, 'DecisionTrace timestamps must be UTC: got $t');
  return t.toIso8601String().replaceFirst(RegExp(r'\.0+Z$'), 'Z');
}

/// One route's belief-derived facts for a single hazard-relevant edge —
/// `docs/CONTRACTS.md` §3's `blocking_edges[]` entry. Assembled by the
/// caller from an `EdgeBelief` (`pulse_belief`) and an `EdgeCostResult`
/// (`edge_cost.dart`); this package does not depend on `pulse_belief`
/// directly, so the caller passes the already-fused numbers through.
class BlockingEdge {
  /// Creates one `blocking_edges[]` entry from already-fused hazard facts.
  const BlockingEdge({
    required this.edgeId,
    required this.streetName,
    required this.hazardClass,
    required this.pMean,
    required this.pPessimistic,
    required this.nEff,
    required this.newestObservationAgeSeconds,
    required this.sourceClass,
    required this.depthMm,
    required this.timePenaltySeconds,
    required this.removedByChanceConstraint,
    this.hasObservation = true,
  });

  /// Whether any observation contributed evidence to this edge. `false` for a
  /// prior-only edge (the hazard map flags the area but nobody has reported
  /// it): [newestObservationAgeSeconds] is then `0` and meaningless, and no
  /// explanation may say "reported N minutes ago" (KNOWN_FLAWS F-04 item 3,
  /// ADR-016). Additive and defaulted so every existing caller and fixture
  /// still compiles; serialised only when `false` so existing wire documents
  /// and the golden trace are unchanged.
  final bool hasObservation;

  /// Matches the router's `edge_id` for this edge.
  final int edgeId;

  /// Human-readable street name, resolved by the caller (this package has
  /// no geocoding — plain node/edge ids carry no street names).
  final String streetName;

  /// The hazard class this edge's belief was fused under (e.g. `"flood"`).
  final String hazardClass;

  /// `p̄(e,t)` — the posterior mean hazard probability.
  final double pMean;

  /// `p̃(e,t)` — the pessimistic probability actually used for routing.
  final double pPessimistic;

  /// `n_eff(e,t)` — effective evidence count.
  final double nEff;

  /// Seconds between this edge's newest contributing observation and the
  /// trace's `computed_at`.
  final double newestObservationAgeSeconds;

  /// The dominant contributing observation's source class (e.g.
  /// `"crowd"`, `"municipal_sensor"`).
  final String sourceClass;

  /// Standing-water depth in millimetres, if this hazard class carries one.
  final double? depthMm;

  /// Seconds this edge adds beyond its own free-flow time. Always `0` when
  /// [removedByChanceConstraint] — `δ` is never evaluated for a removed edge
  /// (`docs/CONTRACTS.md` §3's note).
  final double timePenaltySeconds;

  /// Whether `Pr[depth > h_max] ≤ ε` was violated for this edge.
  final bool removedByChanceConstraint;

  /// Rebuilds a blocking edge from its wire form. Throws [FormatException]
  /// if a field is missing or mistyped.
  factory BlockingEdge.fromJson(Map<String, Object?> json) {
    const where = 'blocking_edge';
    return BlockingEdge(
      edgeId: _field<int>(json, 'edge_id', where),
      streetName: _field<String>(json, 'street_name', where),
      hazardClass: _field<String>(json, 'hazard_class', where),
      pMean: _number(json, 'p_mean', where),
      pPessimistic: _number(json, 'p_pessimistic', where),
      nEff: _number(json, 'n_eff', where),
      newestObservationAgeSeconds: _number(
        json,
        'newest_observation_age_s',
        where,
      ),
      sourceClass: _field<String>(json, 'source_class', where),
      depthMm: (json['depth_mm'] as num?)?.toDouble(),
      timePenaltySeconds: _number(json, 'time_penalty_s', where),
      removedByChanceConstraint: _field<bool>(
        json,
        'removed_by_chance_constraint',
        where,
      ),
      hasObservation: json['has_observation'] as bool? ?? true,
    );
  }

  /// The `docs/CONTRACTS.md` §3 wire representation of this edge.
  Map<String, Object?> toJson() => {
    'edge_id': edgeId,
    'street_name': streetName,
    'hazard_class': hazardClass,
    'p_mean': pMean,
    'p_pessimistic': pPessimistic,
    'n_eff': nEff,
    'newest_observation_age_s': newestObservationAgeSeconds.round(),
    'source_class': sourceClass,
    'depth_mm': depthMm,
    'time_penalty_s': timePenaltySeconds.round(),
    'removed_by_chance_constraint': removedByChanceConstraint,
    if (!hasObservation) 'has_observation': false,
  };
}

/// One rejected alternative route — `docs/CONTRACTS.md` §3 `alternatives[]`.
class AlternativeRoute {
  /// Creates one rejected-alternative entry.
  const AlternativeRoute({
    required this.routeId,
    required this.durationSeconds,
    required this.rejectedBecause,
    required this.blockingEdges,
  });

  /// A label for this route within the trace (e.g. `"B"`), not a stable id.
  final String routeId;

  /// This alternative's own total duration — free-flow time when it was
  /// found by ignoring hazard cost, per this file's builder contract.
  final double durationSeconds;

  /// Why this route lost to `chosen`.
  final RejectedBecause rejectedBecause;

  /// The edges that either caused removal (`chanceConstraint`) or that
  /// carry the highest hazard probability (`higherCost`).
  final List<BlockingEdge> blockingEdges;

  /// Rebuilds an alternative from its wire form.
  factory AlternativeRoute.fromJson(Map<String, Object?> json) {
    const where = 'alternative';
    return AlternativeRoute(
      routeId: _field<String>(json, 'route_id', where),
      durationSeconds: _number(json, 'duration_s', where),
      rejectedBecause: _byWire(
        RejectedBecause.values,
        (v) => v.wireValue,
        _field<String>(json, 'rejected_because', where),
        'rejected_because',
      ),
      blockingEdges: [
        for (final e in _field<List<Object?>>(json, 'blocking_edges', where))
          BlockingEdge.fromJson(e! as Map<String, Object?>),
      ],
    );
  }

  /// The `docs/CONTRACTS.md` §3 wire representation of this alternative.
  Map<String, Object?> toJson() => {
    'route_id': routeId,
    'duration_s': durationSeconds.round(),
    'rejected_because': rejectedBecause.wireValue,
    'blocking_edges': [for (final e in blockingEdges) e.toJson()],
  };
}

/// The chosen route — `docs/CONTRACTS.md` §3 `chosen`.
///
/// `hazardTimePenaltySeconds` is derived, never independently supplied — see
/// this file's top-level doc comment on the `free_flow_duration_s` /
/// `hazard_time_penalty_s` relationship.
class ChosenRoute {
  /// Creates the chosen route's facts. Enforces the ALT-admissibility
  /// invariant (`docs/DECISIONS.md` ADR-003) — a hazard-aware duration can
  /// never be cheaper than the same route's free-flow duration — with a
  /// real, non-strippable check, not an assertion: this is the one field
  /// relationship in this file that a corrupted or buggy caller could get
  /// backwards, and `assert()` alone would let a release build accept it
  /// silently (a 2026-09 security review's general finding, applied here).
  ///
  /// **Tolerant of floating-point summation order, not just bit-exact
  /// equality (found 2026-09-14 running the real ~471k-edge Chennai graph,
  /// T1.3, through this check for the first time — every prior test used
  /// small hand-built graphs where this never surfaced).** With zero hazard
  /// cost, `durationSeconds` and `freeFlowDurationSeconds` are the same sum
  /// of the same per-edge values, but accumulated in different orders —
  /// Dijkstra's incremental relaxation (and, for `bidirectionalDijkstra`
  /// specifically, a forward-meets-backward sum at the join node) versus a
  /// plain left-to-right `fold` over the finished path — and IEEE 754
  /// addition is not associative. Summing ~thousands of edge weights around
  /// 2000s total produced `durationSeconds=2170.457 <
  /// freeFlowDurationSeconds=2170.4570000000003`, a ~3e-13 relative
  /// difference: real floating-point noise, not a real admissibility
  /// violation. The tolerance below is sized to absorb exactly that class of
  /// noise (double-precision epsilon scales with magnitude) while remaining
  /// many orders of magnitude tighter than any discrepancy that would
  /// actually indicate a broken cost function.
  ChosenRoute({
    required this.routeId,
    required this.durationSeconds,
    required this.distanceMeters,
    required this.freeFlowDurationSeconds,
    required this.worstEdgeP,
    required this.geometryRef,
  }) {
    final tolerance = math.max(
      1e-6,
      1e-9 * math.max(durationSeconds.abs(), freeFlowDurationSeconds.abs()),
    );
    if (!(durationSeconds >= freeFlowDurationSeconds - tolerance)) {
      throw ArgumentError(
        'a hazard-adjusted duration below free-flow breaks the '
        'ALT-admissibility invariant (docs/DECISIONS.md ADR-003): '
        'durationSeconds=$durationSeconds < '
        'freeFlowDurationSeconds=$freeFlowDurationSeconds '
        '(tolerance=$tolerance)',
      );
    }
  }

  /// Rebuilds the chosen route from its wire form. The invariant
  /// `duration_s >= free_flow_duration_s` is re-checked by the constructor, so
  /// a server cannot hand a client an impossible trace.
  factory ChosenRoute.fromJson(Map<String, Object?> json) {
    const where = 'chosen';
    return ChosenRoute(
      routeId: _field<String>(json, 'route_id', where),
      durationSeconds: _number(json, 'duration_s', where),
      distanceMeters: _number(json, 'distance_m', where),
      freeFlowDurationSeconds: _number(json, 'free_flow_duration_s', where),
      worstEdgeP: _number(json, 'worst_edge_p', where),
      geometryRef: _field<String>(json, 'geometry_ref', where),
    );
  }

  /// A label for this route within the trace (e.g. `"A"`), not a stable id.
  final String routeId;

  /// The hazard-aware total cost actually used to select this route —
  /// `w_λ` summed over its edges (`docs/DECISIONS.md` ADR-003).
  final double durationSeconds;

  /// Total route length in metres.
  final double distanceMeters;

  /// `τ₀` summed over this route's own edges — this route's free-flow
  /// time, not any alternative's.
  final double freeFlowDurationSeconds;

  /// The pessimistic hazard probability of the single riskiest edge on this
  /// route — the most conservative single number worth surfacing, per this
  /// task's reading of `docs/CONTRACTS.md` §3 (the field name is not further
  /// specified there).
  final double worstEdgeP;

  /// A reference to this route's geometry. This package has no node
  /// coordinates (it is an abstract graph — see `CsrGraph`), so this is a
  /// caller-supplied opaque string, not an encoded polyline.
  final String geometryRef;

  /// `duration_s − free_flow_duration_s` — always `≥ 0` per the constructor's
  /// assertion.
  double get hazardTimePenaltySeconds =>
      durationSeconds - freeFlowDurationSeconds;

  /// The `docs/CONTRACTS.md` §3 wire representation of the chosen route.
  Map<String, Object?> toJson() => {
    'route_id': routeId,
    'duration_s': durationSeconds.round(),
    'distance_m': distanceMeters.round(),
    'free_flow_duration_s': freeFlowDurationSeconds.round(),
    'hazard_time_penalty_s': hazardTimePenaltySeconds.round(),
    'worst_edge_p': worstEdgeP,
    'geometry_ref': geometryRef,
  };
}

/// `context_facts[]` — the only channel for extra colour (reservoir levels,
/// rainfall). Anything an explanation mentions must be here or in
/// `alternatives` (`docs/CONTRACTS.md` §3).
class ContextFact {
  /// Creates one context fact.
  const ContextFact({
    required this.key,
    required this.value,
    required this.label,
    required this.asOf,
  });

  /// A stable machine-readable key, e.g. `"reservoir_level_pct"`.
  final String key;

  /// A JSON-safe value (`num`, `String`, or `bool`).
  final Object? value;

  /// A human-readable label, e.g. `"Chembarambakkam"`.
  final String label;

  /// When this fact was last known to be true.
  final DateTime asOf;

  /// Rebuilds a context fact from its wire form.
  factory ContextFact.fromJson(Map<String, Object?> json) {
    const where = 'context_fact';
    return ContextFact(
      key: _field<String>(json, 'key', where),
      value: json['value'],
      label: _field<String>(json, 'label', where),
      asOf: DateTime.parse(_field<String>(json, 'as_of', where)).toUtc(),
    );
  }

  /// The `docs/CONTRACTS.md` §3 wire representation of this fact.
  Map<String, Object?> toJson() => {
    'key': key,
    'value': value,
    'label': label,
    'as_of': _rfc3339(asOf),
  };
}

/// `data_gaps[]` — absence of hazard data is not the same as absence of
/// hazard; this is not optional (`docs/CONTRACTS.md` §3).
class DataGap {
  /// Creates one data-gap entry.
  const DataGap({required this.corridor, required this.reason});

  /// A human-readable corridor name.
  final String corridor;

  /// Why this corridor has no usable evidence, e.g.
  /// `"no_observations_in_window"`.
  final String reason;

  /// Rebuilds a data gap from its wire form.
  factory DataGap.fromJson(Map<String, Object?> json) => DataGap(
    corridor: _field<String>(json, 'corridor', 'data_gap'),
    reason: _field<String>(json, 'reason', 'data_gap'),
  );

  /// The `docs/CONTRACTS.md` §3 wire representation of this data gap.
  Map<String, Object?> toJson() => {'corridor': corridor, 'reason': reason};
}

/// The full `DecisionTrace` (`docs/CONTRACTS.md` §3).
class DecisionTrace {
  /// Creates a `DecisionTrace` from already-computed pieces. See this
  /// file's top-level doc comment for what this constructor does and does
  /// not decide.
  const DecisionTrace({
    required this.queryId,
    required this.computedAt,
    required this.mode,
    required this.userClass,
    required this.z,
    required this.lambda,
    required this.chosen,
    required this.alternatives,
    required this.contextFacts,
    required this.dataGaps,
    required this.confidenceBand,
  });

  /// Rebuilds a trace from its wire form, e.g. a `router_api` response.
  /// Throws [FormatException] on any missing or mistyped field and
  /// [ArgumentError] if the chosen route breaks the ALT-admissibility
  /// invariant.
  factory DecisionTrace.fromJson(Map<String, Object?> json) {
    const where = 'decision_trace';
    return DecisionTrace(
      queryId: _field<String>(json, 'query_id', where),
      computedAt: DateTime.parse(_field<String>(json, 'computed_at', where))
          .toUtc(),
      mode: _byWire(
        RoutingMode.values,
        (v) => v.wireValue,
        _field<String>(json, 'mode', where),
        'mode',
      ),
      userClass: _byWire(
        UserClass.values,
        (v) => v.wireValue,
        _field<String>(json, 'user_class', where),
        'user_class',
      ),
      z: _number(json, 'z', where),
      lambda: _number(json, 'lambda', where),
      chosen: ChosenRoute.fromJson(
        _field<Map<String, Object?>>(json, 'chosen', where),
      ),
      alternatives: [
        for (final a in _field<List<Object?>>(json, 'alternatives', where))
          AlternativeRoute.fromJson(a! as Map<String, Object?>),
      ],
      contextFacts: [
        for (final f in _field<List<Object?>>(json, 'context_facts', where))
          ContextFact.fromJson(f! as Map<String, Object?>),
      ],
      dataGaps: [
        for (final g in _field<List<Object?>>(json, 'data_gaps', where))
          DataGap.fromJson(g! as Map<String, Object?>),
      ],
      confidenceBand: _byWire(
        ConfidenceBand.values,
        (v) => v.wireValue,
        _field<String>(json, 'confidence_band', where),
        'confidence_band',
      ),
    );
  }

  /// UUIDv7 identifying this query.
  final String queryId;

  /// When this trace was computed. Must be UTC.
  final DateTime computedAt;

  /// Whether this query ran offline-only or online-enriched.
  final RoutingMode mode;

  /// Which user class's `z`/`λ` this query used.
  final UserClass userClass;

  /// The pessimism level actually used (`docs/DECISIONS.md` ADR-002).
  final double z;

  /// The harm-term weight actually used (`docs/DECISIONS.md` ADR-003).
  final double lambda;

  /// The route the router selected.
  final ChosenRoute chosen;

  /// Rejected alternative routes, most relevant first. May be empty.
  final List<AlternativeRoute> alternatives;

  /// Extra colour (reservoir levels, rainfall) an explanation may cite.
  final List<ContextFact> contextFacts;

  /// Corridors with no usable evidence. Never omitted just because it is
  /// empty in a template — an empty list here is itself informative.
  final List<DataGap> dataGaps;

  /// The overall confidence band shown to the user.
  final ConfidenceBand confidenceBand;

  /// The `docs/CONTRACTS.md` §3 wire representation of this trace.
  Map<String, Object?> toJson() => {
    'query_id': queryId,
    'computed_at': _rfc3339(computedAt),
    'mode': mode.wireValue,
    'user_class': userClass.wireValue,
    'z': z,
    'lambda': lambda,
    'chosen': chosen.toJson(),
    'alternatives': [for (final a in alternatives) a.toJson()],
    'context_facts': [for (final f in contextFacts) f.toJson()],
    'data_gaps': [for (final g in dataGaps) g.toJson()],
    'confidence_band': confidenceBand.wireValue,
  };

  /// Canonical, deterministic serialisation — same input, same bytes, every
  /// time. This is what the golden-file test pins.
  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());
}

/// **Placeholder pending calibration (this task, not a validated rule).**
/// `docs/GLOSSARY.md` and `docs/CONTRACTS.md` name `confidence_band` as
/// high/moderate/low/stale but specify no formula. This is a simple,
/// documented starting rule — evidence mass first, then staleness — not yet
/// fit against real Chennai data (that belongs with T3.4's other calibration
/// work). Treat every threshold here as provisional.
///
/// - `stale`: there was evidence once, but the newest observation is older
///   than `staleAfterSeconds` (default `2 * decayTauSeconds` — i.e. decayed
///   past the point the exponential model treats it as still current).
/// - `low`: `nEff < lowNEffThreshold` (default `1.0` — under one
///   full-weight, fully-fresh observation's worth of evidence).
/// - `moderate`: `nEff < moderateNEffThreshold` (default `3.0`).
/// - `high`: otherwise.
///
/// **Validates with real, non-strippable checks, not `assert`.** A 2026-09
/// security review flagged this as the single most severe instance of the
/// assert-stripped-in-release problem in this codebase: a `NaN` `nEff` made
/// every comparison below evaluate `false` and fell through to
/// `ConfidenceBand.high` — the single most reassuring value, computed from
/// garbage input, and shown directly to the user per ADR-011.
ConfidenceBand classifyConfidence({
  required double nEff,
  required double? newestObservationAgeSeconds,
  required double decayTauSeconds,
  double lowNEffThreshold = 1.0,
  double moderateNEffThreshold = 3.0,
  double? staleAfterSeconds,
}) {
  if (!(nEff >= 0)) {
    throw ArgumentError.value(nEff, 'nEff', 'must be non-negative');
  }
  if (!(decayTauSeconds > 0)) {
    throw ArgumentError.value(
      decayTauSeconds,
      'decayTauSeconds',
      'must be positive',
    );
  }
  if (newestObservationAgeSeconds != null &&
      !(newestObservationAgeSeconds >= 0)) {
    throw ArgumentError.value(
      newestObservationAgeSeconds,
      'newestObservationAgeSeconds',
      'must be non-negative when not null',
    );
  }

  final staleAfter = staleAfterSeconds ?? 2 * decayTauSeconds;
  if (newestObservationAgeSeconds != null &&
      newestObservationAgeSeconds > staleAfter) {
    return ConfidenceBand.stale;
  }
  if (nEff < lowNEffThreshold) return ConfidenceBand.low;
  if (nEff < moderateNEffThreshold) return ConfidenceBand.moderate;
  return ConfidenceBand.high;
}
