import 'dart:math' as math;

/// The pessimistic upper-confidence-bound plug-in (`docs/DECISIONS.md`
/// ADR-002) — the probability actually used for routing:
///
/// `p̃ = min{1, p̄ + z·√(p̄(1−p̄)/(n_eff+1))}`
///
/// **The `min{1, …}` clamp is load-bearing, not decoration.** For the
/// `emergency` class (`z = 2.0`) with sparse evidence, the unclamped term
/// routinely exceeds `1` — a nonsensical probability that would corrupt
/// `EdgeBelief.p_pessimistic`'s `[0,1]` semantics and Study 2's Brier score.
/// See ADR-002's worked example and `docs/CONTRACTS.md` §2.
///
/// `pMean` is `p̄`, `nEff` is the effective evidence count from `fuse`, and
/// `z` is the per-user-class pessimism level (`config/hazard_classes.yaml`
/// `user_classes.*.z`).
///
/// **Validates with real, non-strippable checks, not `assert`.** `pMean`
/// and `nEff` both derive, transitively, from untrusted hazard observations
/// (`docs/CONTRACTS.md` §1). A security review (2026-09) confirmed that a
/// `NaN` `pMean` here silently returns `NaN`, and every check below is
/// phrased so a `NaN` argument fails it (any comparison against `NaN` is
/// `false`), which is what makes them effective as fail-fast guards rather
/// than decoration.
double pessimistic({
  required double pMean,
  required double nEff,
  required double z,
}) {
  if (!(pMean >= 0 && pMean <= 1)) {
    throw ArgumentError.value(pMean, 'pMean', 'must be in [0, 1]');
  }
  if (!(nEff >= 0)) {
    throw ArgumentError.value(nEff, 'nEff', 'must be non-negative');
  }
  if (!(z >= 0)) {
    throw ArgumentError.value(z, 'z', 'must be non-negative');
  }

  final band = z * math.sqrt(pMean * (1 - pMean) / (nEff + 1));
  final raw = pMean + band;
  return raw > 1.0 ? 1.0 : raw;
}
