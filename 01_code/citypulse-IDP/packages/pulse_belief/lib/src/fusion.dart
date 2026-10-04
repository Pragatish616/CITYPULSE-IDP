import 'dart:math' as math;

import 'package:pulse_belief/src/kernel.dart';
import 'package:pulse_belief/src/math_utils.dart';
import 'package:pulse_belief/src/observation.dart';

/// The `edge_id`/`hazard_class`-scoped, `z`-independent half of
/// `EdgeBelief` (`docs/CONTRACTS.md` §2) — everything `fuse` can compute
/// without knowing which user class is querying. The router attaches
/// `z` and `p_pessimistic` at query time via `pessimistic`.
class EdgeBelief {
  /// Builds an [EdgeBelief] directly from already-computed fields — normally
  /// produced by [fuse].
  const EdgeBelief({
    required this.priorLogOdds,
    required this.posteriorLogOdds,
    required this.pMean,
    required this.nEff,
    required this.newestObservationAt,
    required this.contributingObservationIds,
  });

  /// `ℓ₀(e)` — the static terrain prior, as passed in.
  final double priorLogOdds;

  /// `ℓ(e,t) = ℓ₀(e) + Σᵢ yᵢ·κ(d(e,xᵢ))·exp(−(t−tᵢ)/T_c)·logit(α_{cᵢ})`.
  final double posteriorLogOdds;

  /// `p̄(e,t) = σ(ℓ(e,t))`.
  final double pMean;

  /// `n_eff(e,t) = Σᵢ κ(d(e,xᵢ))·exp(−(t−tᵢ)/T_c)` — unsigned, so opposing
  /// observations cancel in `ℓ` but still both count as evidence here.
  final double nEff;

  /// `newest_observation_at`, or `null` if no observation contributed any
  /// weight (empty input, or every candidate fell outside the kernel's
  /// cutoff).
  final DateTime? newestObservationAt;

  /// `contributing_observations` — ids of every observation that
  /// contributed non-zero weight, in input order.
  final List<String> contributingObservationIds;
}

/// Fuses [observations] onto one edge at query time [t], per CLAUDE.md §6's
/// log-odds model.
///
/// [priorLogOdds] is `ℓ₀(e)` for this edge and hazard class (the static
/// terrain prior — T1.3, built once and shipped to device). [decayTauSeconds]
/// is `T_c` for this hazard class (`config/hazard_classes.yaml`
/// `T_c_seconds`). [kernel] is `κ(d)`.
///
/// An observation with `observedAt` after [t] is rejected outright (the
/// belief state cannot see the future) rather than silently clamped —
/// **enforced with a real, non-strippable check**, not an assertion: a
/// future-dated `observed_at` (`docs/CONTRACTS.md` §1, untrusted at the
/// network boundary) would otherwise make `ageSeconds` negative, which
/// *inflates* that observation's weight above its kernel value instead of
/// decaying it — the same wrong-direction failure a 2026-09 security review
/// found throughout this pipeline whenever validation was assert-only.
EdgeBelief fuse({
  required List<WeightedObservation> observations,
  required double priorLogOdds,
  required DateTime t,
  required double decayTauSeconds,
  SpatialKernel? kernel,
}) {
  if (!(decayTauSeconds > 0)) {
    throw ArgumentError.value(
      decayTauSeconds,
      'decayTauSeconds',
      'must be positive',
    );
  }
  final resolvedKernel = kernel ?? SpatialKernel();

  var logOddsShift = 0.0;
  var nEff = 0.0;
  DateTime? newest;
  final contributing = <String>[];

  for (final obs in observations) {
    final kappa = resolvedKernel(obs.distanceM);
    if (!(kappa > 0)) continue;

    final ageSeconds = t.difference(obs.observedAt).inMicroseconds / 1e6;
    if (!(ageSeconds >= 0)) {
      throw ArgumentError(
        'observation ${obs.id} observed after query time t '
        '(observedAt=${obs.observedAt}, t=$t)',
      );
    }

    final weight = kappa * math.exp(-ageSeconds / decayTauSeconds);
    nEff += weight;
    logOddsShift += obs.polarity * weight * logit(obs.sourceReliability);

    if (newest == null || obs.observedAt.isAfter(newest)) {
      newest = obs.observedAt;
    }
    contributing.add(obs.id);
  }

  final posteriorLogOdds = priorLogOdds + logOddsShift;
  return EdgeBelief(
    priorLogOdds: priorLogOdds,
    posteriorLogOdds: posteriorLogOdds,
    pMean: sigmoid(posteriorLogOdds),
    nEff: nEff,
    newestObservationAt: newest,
    contributingObservationIds: List.unmodifiable(contributing),
  );
}
