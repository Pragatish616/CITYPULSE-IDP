import 'package:pulse_router/src/depth_disruption.dart';

/// The outcome of costing one edge at query time: either a finite seconds
/// cost, or "removed" when the hard chance constraint fires.
class EdgeCostResult {
  /// A finite cost — the edge survives and may be used by the search.
  const EdgeCostResult.finite({
    required double this.costSeconds,
    required this.delta,
  }) : removedByChanceConstraint = false;

  /// The edge is removed outright by the chance constraint
  /// (`docs/DECISIONS.md` ADR-003) — never given a large finite weight.
  /// `delta` is not computed for a removed edge (`docs/CONTRACTS.md` §3).
  const EdgeCostResult.removed()
    : costSeconds = null,
      delta = null,
      removedByChanceConstraint = true;

  /// `w_λ(e,t)` in seconds, or `null` if [removedByChanceConstraint].
  final double? costSeconds;

  /// `δ(e,t)`, or `null` if [removedByChanceConstraint] (never evaluated for
  /// a removed edge).
  final double? delta;

  /// Whether `Pr[depth > h_max] <= ε` was violated, per ADR-003 — edge
  /// removal, not a large finite weight.
  final bool removedByChanceConstraint;
}

/// `w_λ(e,t) = τ₀·[1 + p̃·(δ−1)] + λ·p̃·s·τ₀`, with the hard chance
/// constraint `Pr[depth > h_max] <= ε` enforced as edge removal
/// (`docs/DECISIONS.md` ADR-003).
///
/// **Chance-constraint modelling choice (this task, not yet in any ADR):**
/// with only a pessimistic point probability `pPessimistic` and a point depth
/// estimate `depthMm` available — not a full depth distribution — this
/// approximates `Pr[depth > h_max]` as `pPessimistic` whenever `depthMm` is
/// known to exceed `hMaxMm`, and `0` otherwise. This matches the worked
/// example in `docs/CONTRACTS.md` §3 (`depth_mm: 320 > h_max_mm: 300` with
/// `p_pessimistic: 1.0` removes the edge) but is a simplification worth
/// revisiting once a real depth distribution is available — flag, don't
/// silently refine, per `CLAUDE.md` §8.
///
/// **Validates with real, non-strippable checks, not `assert`.** `assert()`
/// is compiled out in Dart release builds; a 2026-09 security review found
/// that a `NaN` `pPessimistic` or `depthMm` (both transitively derived from
/// untrusted hazard observations, `docs/CONTRACTS.md` §1) would then make
/// the chance-constraint check below — `depthMm > hMaxMm && pPessimistic >=
/// epsilon` — evaluate `false` (any comparison against `NaN` is `false`),
/// **failing open**: the one piece of this codebase where a bug is directly
/// physically dangerous would silently keep a hazardous edge open instead of
/// removing it. Every check below is phrased in positive space (`x >= 0`,
/// not `!(x < 0)`) for exactly this reason — it is what makes a `NaN`
/// argument fail it.
EdgeCostResult edgeCost({
  required double freeFlowSeconds,
  required double freeFlowKmh,
  required double pPessimistic,
  required double? depthMm,
  required double severity,
  required double lambda,
  required double hMaxMm,
  required double epsilon,
}) {
  if (!(freeFlowSeconds > 0)) {
    throw ArgumentError.value(
      freeFlowSeconds,
      'freeFlowSeconds',
      'must be positive',
    );
  }
  if (!(freeFlowKmh > 0)) {
    throw ArgumentError.value(freeFlowKmh, 'freeFlowKmh', 'must be positive');
  }
  if (!(pPessimistic >= 0 && pPessimistic <= 1)) {
    throw ArgumentError.value(
      pPessimistic,
      'pPessimistic',
      'must be in [0, 1]',
    );
  }
  if (depthMm != null && !(depthMm >= 0)) {
    throw ArgumentError.value(
      depthMm,
      'depthMm',
      'must be non-negative when not null',
    );
  }
  if (!(severity >= 0)) {
    throw ArgumentError.value(severity, 'severity', 'must be non-negative');
  }
  if (!(lambda >= 0)) {
    throw ArgumentError.value(lambda, 'lambda', 'must be non-negative');
  }
  if (!(epsilon > 0 && epsilon <= 1)) {
    throw ArgumentError.value(epsilon, 'epsilon', 'must be in (0, 1]');
  }

  final chanceConstraintBreached =
      depthMm != null && depthMm > hMaxMm && pPessimistic >= epsilon;
  if (chanceConstraintBreached) {
    return const EdgeCostResult.removed();
  }

  final delta = slowdownDelta(freeFlowKmh: freeFlowKmh, depthMm: depthMm);
  final costSeconds =
      freeFlowSeconds * (1 + pPessimistic * (delta - 1)) +
      lambda * pPessimistic * severity * freeFlowSeconds;
  return EdgeCostResult.finite(costSeconds: costSeconds, delta: delta);
}
