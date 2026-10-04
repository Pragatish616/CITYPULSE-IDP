import 'dart:math' as math;

/// Spatial attribution kernel `κ(d)` (`docs/GLOSSARY.md`) — how much weight an
/// observation at distance `distanceM` metres from a candidate edge
/// contributes to that edge's belief.
///
/// **Placeholder pending calibration.** Neither the shape nor the bandwidth
/// below is fitted to Chennai data — CLAUDE.md §6 defines `κ(d)` only as "a
/// spatial kernel," not a specific function. Exponential decay with a hard
/// cutoff is a defensible, simple starting choice (monotonic, zero tail
/// weight beyond typical edge-snapping error), not a validated one. T3.4
/// (calibration against real Chennai closure data) may replace this with a
/// different shape entirely — treat any number here as provisional.
class SpatialKernel {
  /// Creates a kernel with the given [bandwidthM] and [cutoffM]. Throws
  /// [ArgumentError] — not an assertion, and not `const`-constructible for
  /// exactly that reason: Dart requires a const constructor's initializers
  /// to be constant expressions, which a validating `throw` cannot be — if
  /// either is not positive.
  SpatialKernel({this.bandwidthM = 75, this.cutoffM = 300}) {
    if (!(bandwidthM > 0)) {
      throw ArgumentError.value(bandwidthM, 'bandwidthM', 'must be positive');
    }
    if (!(cutoffM > 0)) {
      throw ArgumentError.value(cutoffM, 'cutoffM', 'must be positive');
    }
  }

  /// Distance, in metres, at which the kernel has decayed to `1/e`.
  final double bandwidthM;

  /// Distance, in metres, beyond which an observation is attributed zero
  /// weight regardless of decay — bounds how far a single point observation
  /// can reach across a road network.
  final double cutoffM;

  /// `κ(d) = exp(-d / bandwidthM)` for `d ≤ cutoffM`, else `0`.
  ///
  /// Throws [ArgumentError] for a negative or `NaN` [distanceM] rather than
  /// letting either through: the `distanceM > cutoffM` short-circuit below
  /// is deliberately *not* how `NaN` is rejected (`NaN > cutoffM` is
  /// `false`, so a `NaN` distance would otherwise fall through to
  /// `math.exp`, itself `NaN`, silently corrupting `fuse`'s evidence sum —
  /// exactly the class of bug a 2026-09 security review found repeated
  /// throughout this pipeline).
  double call(double distanceM) {
    if (!(distanceM >= 0)) {
      throw ArgumentError.value(distanceM, 'distanceM', 'must be non-negative');
    }
    if (distanceM > cutoffM) return 0;
    return math.exp(-distanceM / bandwidthM);
  }
}
