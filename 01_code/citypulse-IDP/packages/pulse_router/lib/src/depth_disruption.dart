/// Pregnolato, Ford, Wilkinson, Dawson (2017), "The Impact of Flooding on Road
/// Transport: A Depth-Disruption Function," *Transportation Research Part D*
/// 55, 67–81. DOI 10.1016/j.trd.2017.06.020.
///
/// **[UNVERIFIED DETAIL]** — per `CLAUDE.md` §7's citation discipline: this
/// coefficient form is the widely-quoted one from secondary sources
/// (`research/raw/A-routing-algorithms.md` §2.4); it has not yet been checked
/// against the paper PDF. Do not cite it in the paper without opening the
/// primary source first.
///
/// Fitted over standing-water depth `0..~300 mm` (R² = 0.95 per the secondary
/// source). This implementation clamps its input to that domain rather than
/// extrapolating the raw quadratic, which turns upward past ~307 mm and would
/// otherwise report a *higher* safe speed for deeper water — see
/// `docs/CONTRACTS.md` §3's note on not evaluating `δ` past the validated
/// domain without clamping first.
const _validDomainMaxMm = 300.0;

/// `v_safe(h)` in km/h for standing-water depth `depthMm` in millimetres.
///
/// Throws [ArgumentError] — not an assertion, which Dart strips in release
/// builds — for a negative or `NaN` `depthMm`. Phrased in positive space
/// (`depthMm >= 0`) so a `NaN` argument fails it: the domain clamp just
/// below is a `>` comparison, which a `NaN` would silently skip rather than
/// be caught by, letting `NaN` flow into the quadratic below it.
double pregnolatoVSafeKmh(double depthMm) {
  if (!(depthMm >= 0)) {
    throw ArgumentError.value(depthMm, 'depthMm', 'must be non-negative');
  }
  final h = depthMm > _validDomainMaxMm ? _validDomainMaxMm : depthMm;
  final v = 0.0009 * h * h - 0.5529 * h + 86.9448;
  return v < 0 ? 0 : v;
}

/// The slowdown multiplier `δ(e,t) = max(1, v_free(e) / v_safe(h(e,t)))`
/// (`docs/DECISIONS.md` ADR-003).
///
/// **The `max(1, ...)` clamp is required, not an optimisation.** Pregnolato's
/// fitted `v_safe(0) ≈ 87 km/h` means an edge with `v_free(e) > 87 km/h`
/// (rare) or, far more commonly in Chennai, an ordinary arterial at
/// `v_free(e) ≈ 30 km/h` at shallow depth would otherwise compute
/// `δ < 1` — the hazard-adjusted cost dropping *below* free-flow, which
/// silently breaks the ALT-admissibility invariant `w_λ(e,t) ≥ τ₀(e,t)` that
/// `CLAUDE.md` §6 and `docs/DECISIONS.md` ADR-003 require on every edge.
///
/// `depthMm == null` means no depth observation for this hazard — `δ = 1`
/// (no slowdown), not "unknown" or "impassable"; absence of a depth reading
/// is not evidence of depth.
double slowdownDelta({required double freeFlowKmh, required double? depthMm}) {
  if (!(freeFlowKmh > 0)) {
    throw ArgumentError.value(freeFlowKmh, 'freeFlowKmh', 'must be positive');
  }
  if (depthMm == null) return 1;

  final vSafe = pregnolatoVSafeKmh(depthMm);
  if (vSafe <= 0) return double.infinity;

  final raw = freeFlowKmh / vSafe;
  return raw > 1 ? raw : 1;
}
