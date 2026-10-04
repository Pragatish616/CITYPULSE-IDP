# Glossary and Notation

Shared vocabulary so agents and teammates mean the same thing. Symbols match
`research/raw/A-routing-algorithms.md` §5 and `CLAUDE.md` §6.

## Symbols
| Symbol | Meaning |
|---|---|
| `ℓ₀(e)` | Static terrain prior in log-odds — elevation, HAND, drainage, historical inundation. Precomputed, shipped to device. |
| `ℓ(e,t)` | Posterior log-odds of hazard on edge `e` at time `t` after fusing observations. |
| `p̄(e,t)` | Posterior mean hazard probability, `σ(ℓ)`. |
| `n_eff` | Effective evidence count — decayed, kernel-weighted sum of contributing observations. |
| `p̃(e,t)` | **Pessimistic** hazard probability actually used for routing: `min{1, p̄ + z·√(p̄(1−p̄)/(n_eff+1))}`. **The clamp is load-bearing** — without it, `p̃` regularly exceeds 1 for the `emergency` class under sparse evidence (verified 2026-09-12; see `docs/DECISIONS.md` ADR-002). |
| `z` | Pessimism level, per user class. `≈0` commuter, `≈2` emergency. |
| `T_c` | Decay time constant, **per hazard class**. Flooding hours; debris minutes. |
| `α_c` | Reliability of a source class; `logit(α_c)` is its evidence weight. |
| `κ(d)` | Spatial kernel attributing a point observation to nearby edges. |
| `τ₀(e,t)` | Baseline (free-flow or time-of-day) travel time in seconds. |
| `δ(e,t)` | Slowdown multiplier from flood depth, per Pregnolato et al. (2017). `δ ≥ 1`. |
| `s(e,t)` | Hazard severity — normalised harm potential, per class. |
| `λ` | Weight on the harm term relative to the time term. Both in seconds, so `λ` is interpretable. |
| `h_max`, `ε` | Chance constraint: `Pr[depth > h_max] ≤ ε`, enforced by removing the edge. |

## Terms
- **Decision trace** — the structured record of a routing decision (`docs/CONTRACTS.md` §3).
  The only permitted input to any explanation.
- **Tier 0 / Tier 1** — deterministic template renderer / SLM rewriter. Tier 0 always runs and
  is always the fallback (ADR-004).
- **Verifier** — the symbolic check that every numeral and entity in an explanation exists in
  the trace. Its pass rate is the paper's headline metric.
- **Traversal-silence** — a traversal producing no hazard report, treated as calibrated
  evidence of absence (improvement I-02).
- **Data gap** — a corridor with no recent observations. Not the same as "clear", and rendered
  differently (improvement I-05).
- **Confidence band** — high / moderate / low / stale, shown to the user.
- **Offline-first** — the client always routes locally; the network only enriches (ADR-005).
  Distinct from "offline fallback", which the pitch described and which is not implementable.
- **Replay corpus / harness** — historical Chennai events replayed at their real timestamps;
  the evaluation works even if no live feed is ever obtained.
- **Appropriate reliance** — agreement-when-right minus agreement-when-wrong. The human study's
  real metric; raw trust is not a success measure.
