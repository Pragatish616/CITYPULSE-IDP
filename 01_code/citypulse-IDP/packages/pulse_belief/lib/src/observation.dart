/// A single hazard report's contribution to one candidate edge, already
/// reduced to the numbers `fuse` needs.
///
/// This is deliberately narrower than `HazardObservation`
/// (`docs/CONTRACTS.md` §1): geometry, edge-snapping, and the
/// `source_class -> α_c` lookup (`config/hazard_classes.yaml`) all involve
/// I/O or a config file and stay outside this package (ADR — pulse_belief is
/// pure functions, no I/O, per `docs/IMPLEMENTATION_PLAN.md` T1.2). The
/// caller resolves a `HazardObservation` to a `WeightedObservation` per
/// candidate edge before calling `fuse`.
///
/// **Validated with real, non-strippable checks, not `assert`.** This class
/// is the boundary where untrusted, network-derived data (a crowd-sourced
/// hazard report per `docs/CONTRACTS.md` §1's `source_class: crowd`) first
/// enters this package as numbers. `assert()` is compiled out entirely in
/// Dart release builds, so a malformed or adversarial value here would
/// otherwise reach `fuse()` unchecked in production. A security review
/// (2026-09) traced exactly this: `sourceReliability` outside `(0, 1)`
/// silently produces `NaN` through `logit`, which then propagates through
/// `fuse`, `pessimistic`, and `edgeCost` — always in the *less* cautious
/// direction, the opposite of ADR-002's design principle. Throwing here,
/// unconditionally, closes that off at the source.
class WeightedObservation {
  /// Creates a [WeightedObservation] already resolved to one candidate edge.
  /// Throws [ArgumentError] — not an assertion — for any field outside its
  /// valid range, including `NaN` (every check below is phrased so a `NaN`
  /// argument fails it, since any comparison against `NaN` is `false`).
  /// Not `const`-constructible for exactly that reason: Dart requires a
  /// const constructor's initializers to be constant expressions, which a
  /// validating `throw` cannot be.
  WeightedObservation({
    required this.id,
    required int polarity,
    required double distanceM,
    required this.observedAt,
    required double sourceReliability,
  }) : polarity = polarity == 1 || polarity == -1
           ? polarity
           : throw ArgumentError.value(
               polarity,
               'polarity',
               'must be +1 (present) or -1 (absent/cleared)',
             ),
       distanceM = distanceM >= 0
           ? distanceM
           : throw ArgumentError.value(
               distanceM,
               'distanceM',
               'must be non-negative',
             ),
       sourceReliability = sourceReliability > 0 && sourceReliability < 1
           ? sourceReliability
           : throw ArgumentError.value(
               sourceReliability,
               'sourceReliability',
               'must be in the open interval (0, 1)',
             );

  /// Matches `HazardObservation.id` — carried through to
  /// `EdgeBelief.contributing_observations` for auditability.
  final String id;

  /// `+1` hazard present, `-1` hazard absent/cleared. Negative observations
  /// are first-class evidence (`docs/CONTRACTS.md` §1, improvement I-02).
  final int polarity;

  /// `d(e, x_i)` — the observation's distance to the candidate edge, in
  /// metres. Computed by the caller from geometry; this package never
  /// touches geometry.
  final double distanceM;

  /// `t_i` — when the hazard was observed (not when it was received).
  final DateTime observedAt;

  /// `α_c` for this observation's source class
  /// (`config/hazard_classes.yaml` `source_reliability`), already resolved
  /// by the caller.
  final double sourceReliability;
}
