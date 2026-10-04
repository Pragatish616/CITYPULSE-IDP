import 'dart:math' as math;

import 'package:pulse_belief/src/beta.dart';
import 'package:pulse_belief/src/kernel.dart';
import 'package:pulse_belief/src/math_utils.dart';
import 'package:pulse_belief/src/observation.dart';

/// The three numbers the Beta belief needs beyond the data (ADR-015).
///
/// **All three are placeholders, not fitted values** -- like the `T_c`
/// decay constants (F-15) they cannot be fitted until there are time-stamped,
/// independent labels. They are held here, not scattered in code, so a
/// sensitivity sweep can vary them (see `docs/DECISIONS.md` ADR-015).
class BeliefParams {
  /// Validated with real, non-strippable checks (this codebase's convention).
  factory BeliefParams({
    double priorStrength = 2.0,
    double evidenceScale = 2.0,
    double referenceReliability = 0.97,
  }) {
    if (!(priorStrength > 0) || !priorStrength.isFinite) {
      throw ArgumentError.value(priorStrength, 'priorStrength', 'must be > 0');
    }
    if (!(evidenceScale > 0) || !evidenceScale.isFinite) {
      throw ArgumentError.value(evidenceScale, 'evidenceScale', 'must be > 0');
    }
    if (!(referenceReliability > 0.5 && referenceReliability < 1)) {
      throw ArgumentError.value(
        referenceReliability,
        'referenceReliability',
        'must be in (0.5, 1)',
      );
    }
    return BeliefParams._(priorStrength, evidenceScale, referenceReliability);
  }

  const BeliefParams._(
    this.priorStrength,
    this.evidenceScale,
    this.referenceReliability,
  );

  /// `n0` -- the prior's pseudo-count: `Beta(n0·p0, n0·(1−p0))`. Larger means
  /// the static prior resists change from the first few reports.
  final double priorStrength;

  /// `s` -- pseudo-counts contributed by one fresh, full-reliability report.
  final double evidenceScale;

  /// `α_ref` -- the reliability that counts as a full report (the sensor
  /// class, 0.97). Every other source is weighted `logit(α)/logit(α_ref)`.
  final double referenceReliability;

  /// The defaults used by the router unless a caller overrides them.
  static final BeliefParams defaults = BeliefParams();
}

/// How much one source's report counts, relative to a reference-reliability
/// report: `min(1, logit(α)/logit(α_ref))`, and `0` for `α ≤ 0.5` (a source no
/// better than a coin flip carries no information).
///
/// This keeps the **relative** weighting the original log-odds model used
/// (each report's shift was proportional to `logit(α)`), but as a bounded
/// evidence mass rather than a log-odds shift, which is what lets the
/// posterior be a proper Beta.
double reliabilityWeight(double alpha, double referenceReliability) {
  if (!(alpha > 0 && alpha < 1)) {
    throw ArgumentError.value(alpha, 'alpha', 'must be in (0, 1)');
  }
  final w = logit(alpha) / logit(referenceReliability);
  if (w <= 0) return 0;
  return w > 1 ? 1 : w;
}

/// An edge's belief as a Beta posterior (ADR-015, replacing the Wald band of
/// ADR-002; KNOWN_FLAWS F-01 and F-12).
///
/// `Beta(a, b)` with `a = n0·p0 + s·S⁺` and `b = n0·(1−p0) + s·S⁻`, where
/// `S = Σ polarity·κ·e^(−Δt/T_c)·w(α)` is the **signed, reliability-weighted**
/// evidence. Because evidence enters only through `S`:
///
///  * a positive report raises `S`, which stochastically raises the Beta, so
///    **every** upper quantile rises -- the index can no longer fall after a
///    weak report, whatever its reliability (the F-01 dip is structurally
///    impossible, and `test/beta_test.dart` checks it on a grid);
///  * opposing reports cancel in `S` instead of both counting as "more
///    evidence" (F-12: conflict used to read as certainty);
///  * ageing shrinks `|S|`, so evidence decays monotonically back to the
///    prior's own quantile.
class BetaBelief {
  /// Builds a belief directly. Normally produced by [fuseBeta].
  const BetaBelief({
    required this.priorLogOdds,
    required this.alpha,
    required this.beta,
    required this.netEvidence,
    required this.newestObservationAt,
    required this.contributingObservationIds,
  });

  /// `ℓ0(e)`, as passed in.
  final double priorLogOdds;

  /// The Beta's `a` parameter (pseudo-count for "hazard present").
  final double alpha;

  /// The Beta's `b` parameter (pseudo-count for "hazard absent").
  final double beta;

  /// `S`: signed, reliability-weighted, decayed evidence, in
  /// "fresh full-reliability reports". Positive supports the hazard.
  final double netEvidence;

  /// The newest observation that contributed weight, or `null`.
  final DateTime? newestObservationAt;

  /// Ids of every observation that contributed non-zero kernel weight.
  final List<String> contributingObservationIds;

  /// `p̄ = a/(a+b)`, the posterior mean.
  double get pMean => alpha / (alpha + beta);

  /// `ln(p̄/(1−p̄))`, kept so callers and traces that still speak log-odds
  /// have a value.
  double get posteriorLogOdds => math.log(alpha / beta);

  /// Net, reliability-weighted evidence mass in report-equivalents,
  /// `|S|`. This replaces the old unsigned `n_eff`: it is small for
  /// low-reliability sources (three crowd reports are about 0.35, not 3) and
  /// zero when reports cancel, so the confidence band built from it no longer
  /// reads weak or contradictory evidence as certainty.
  double get nEff => netEvidence.abs();
}

/// Fuses [observations] onto one edge at query time [t] as a [BetaBelief].
///
/// Signature mirrors `fuse` (`fusion.dart`) so call sites differ only in the
/// result type. Rejects a future-dated observation with a real, non-strippable
/// check (the same security-review finding `fuse` records).
BetaBelief fuseBeta({
  required List<WeightedObservation> observations,
  required double priorLogOdds,
  required DateTime t,
  required double decayTauSeconds,
  SpatialKernel? kernel,
  BeliefParams? params,
}) {
  if (!(decayTauSeconds > 0)) {
    throw ArgumentError.value(
      decayTauSeconds,
      'decayTauSeconds',
      'must be positive',
    );
  }
  if (!priorLogOdds.isFinite) {
    throw ArgumentError.value(priorLogOdds, 'priorLogOdds', 'must be finite');
  }
  final p = params ?? BeliefParams.defaults;
  final resolvedKernel = kernel ?? SpatialKernel();

  var signed = 0.0;
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
    signed +=
        obs.polarity *
        weight *
        reliabilityWeight(obs.sourceReliability, p.referenceReliability);
    if (newest == null || obs.observedAt.isAfter(newest)) {
      newest = obs.observedAt;
    }
    contributing.add(obs.id);
  }

  // Keep the prior strictly inside (0, 1) so both Beta parameters stay > 0.
  final p0 = sigmoid(priorLogOdds).clamp(1e-6, 1 - 1e-6);
  final a0 = p.priorStrength * p0;
  final b0 = p.priorStrength * (1 - p0);
  return BetaBelief(
    priorLogOdds: priorLogOdds,
    alpha: a0 + p.evidenceScale * math.max(signed, 0),
    beta: b0 + p.evidenceScale * math.max(-signed, 0),
    netEvidence: signed,
    newestObservationAt: newest,
    contributingObservationIds: List.unmodifiable(contributing),
  );
}

/// The pessimistic index `p̃`: the `Φ(z)` upper quantile of the belief's Beta,
/// never below its mean, never above 1 (ADR-015).
///
/// `z = 0` gives the mean (the commuter default), so commuters on a prior-only
/// edge see exactly `p̃ = p0`, as before. Larger `z` reads a higher quantile:
/// `z = 1.28` is the 90th percentile, `z = 2` the 97.7th. Unlike the old Wald
/// band this is a genuine posterior quantile -- it cannot exceed 1, does not
/// collapse near 0, and does not saturate to 1 on every high-prior edge.
double pessimisticBeta({required BetaBelief belief, required double z}) {
  if (!(z >= 0) || !z.isFinite) {
    throw ArgumentError.value(z, 'z', 'must be finite and non-negative');
  }
  final mean = belief.pMean;
  if (z == 0) return mean;
  final q = normalCdf(z);
  // p̃ is floored at the mean, so when the mean already sits at or above the
  // q-quantile the root-finding is unnecessary. Exact, and it is the common
  // case on a skewed low-prior edge, where it saves the whole search.
  if (betaCdf(mean, belief.alpha, belief.beta) >= q) return mean;
  final upper = betaQuantile(q, belief.alpha, belief.beta);
  final index = math.max(mean, upper);
  return index > 1.0 ? 1.0 : index;
}
