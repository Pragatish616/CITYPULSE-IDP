# pulse_belief

Pure hazard-belief fusion (`docs/IMPLEMENTATION_PLAN.md` T1.2). Implements CLAUDE.md §6's
log-odds fusion model and ADR-002's pessimistic upper-confidence-bound plug-in.

No I/O: geometry (`d(e, x_i)`), config loading (`config/hazard_classes.yaml`), and
`HazardObservation` parsing all stay outside this package — callers resolve a
`HazardObservation` to a `WeightedObservation` per candidate edge first.

- `fuse(...)` — log-odds accumulation with spatial kernel `κ` and per-class exponential decay,
  over `priorLogOdds` (`ℓ₀(e)`, from T1.3). Returns the `z`-independent half of `EdgeBelief`
  (`docs/CONTRACTS.md` §2).
- `pessimistic(...)` — `p̃ = min{1, p̄ + z·√(p̄(1−p̄)/(n_eff+1))}`. The `min{1, …}` clamp is
  load-bearing (ADR-002) and is exercised, not just asserted, in `test/pessimistic_test.dart`.
- `SpatialKernel` — `κ(d)`, exponential decay with a hard cutoff. **Placeholder pending
  calibration** (T3.4) — CLAUDE.md §6 names `κ` but does not pin a shape; see the doc comment
  in `lib/src/kernel.dart`.

Consumed by `packages/pulse_router` (T2.1) for edge cost computation and by the Flutter client
for on-device belief updates — same code, per ADR-001.

## Input validation (2026-09 security review)

`WeightedObservation`, `SpatialKernel.call`, `fuse`, and `pessimistic` all validate with real,
non-strippable checks (`throw ArgumentError`), not `assert` — a review found that `assert()`,
stripped entirely in Dart release builds, let a malformed or adversarial value (out-of-range
`sourceReliability`, a `NaN` distance, a future-dated observation) reach production unchecked
and propagate as `NaN`, always in the *less* cautious direction — the opposite of ADR-002's
design principle. See the doc comments on those symbols and the `regression for a 2026-09
security review finding` tests in `test/`. `WeightedObservation` and `SpatialKernel` are no
longer `const`-constructible for exactly this reason: Dart requires a const constructor's
initializers to be constant expressions, which a validating `throw` cannot be.

## Running the tests

```
dart pub get
dart test
```
