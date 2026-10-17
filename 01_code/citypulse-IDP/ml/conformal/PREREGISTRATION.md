# C5 pre-registration: conformal flags for flood-reported edges

Written and committed on 17 Oct 2026 **before** the evaluation script was written or run. Nothing below may be changed after the first run
except by a dated addendum at the end that says what changed and why.

## Question

The router's caution today comes from a hand-set pessimistic index (z per user class), which is non-monotone (KNOWN_FLAWS F-01) and has no
coverage meaning. Can split conformal calibration replace it with a threshold that has a stated, checkable meaning: "of edges like these
that later had an official flood report, at least 90 % were flagged"?

This is a statement about how often an **estimate** covered a **label**. It never says a road is safe or passable (ADR-011).

## Data (existing; no new data)

- The Study 2 edge pools, built exactly as `scripts/study2_calibration.py` builds them (`load_edge_pools`, seed 20260918): every directed
  edge with at least one crowd report in the 2015 corpus (crowd pool), plus 5,000 sampled edges with no report of any kind.
- Report age 0 only (the corpus has one proxy timestamp; other ages are simulated and would repeat each edge six times).
- **Label:** 1 if the edge also has an official report, else 0 (the Study 2 label). It is weak: it measures co-location of official and
  crowd points on the same edge, not flooding.
- **Groups (Mondrian):** the edge's hazard class: `flood` or `waterlogging` (dominant class among its crowd reports; no-report edges are
  `flood`).
- **Scores:** two, each evaluated separately: (S1) C3 fused probability p̄ (`p_mean_c3_ours`), (S2) the static prior alone
  (`p_mean_prior_only`).
- **Coordinates for the spatial split:** the mean position of the edge's crowd reports (crowd pool), or the mean of its geometry points
  in `data/graph/2026-09-14/chennai_prior_ell0.json` (no-report edges).

## Method

Label-conditional split conformal, per group g and score S, with α = 0.10:

1. Split edges into calibration and test (below).
2. Calibration positives of group g, n₁ of them, scores s₁ ≤ … ≤ s_{n₁}. Threshold τ_g = s_(k), k = ⌊α (n₁ + 1)⌋ (if k = 0, τ_g = −∞:
   flag everything in the group).
3. Flag a test edge of group g if S ≥ τ_g.

Under exchangeability of calibration and test positives this guarantees P(flagged | label 1, group g) ≥ 1 − α.

## Splits

- **Primary: random.** 200 random 50/50 splits of edges, `numpy.random.default_rng(20261017)`.
- **Secondary: spatial blocks.** Edges grouped by 0.01° × 0.01° cells (about 1.1 km); 200 random 50/50 splits of cells, same generator
  continued. This probes whether coverage survives when test edges are in places the calibration did not see.

## Outcomes (reported per group, per score, per split type)

- **Coverage:** share of test positives flagged. Mean over splits, and 5th and 95th percentiles.
- **Cost:** share of test negatives flagged (false-flag rate), mean and percentiles.
- **Comparison:** the same two numbers for the fixed rule "flag if p̄ ≥ 0.5" (C1).
- Counts: positives and negatives per group.

## Decision rule (fixed now)

- **Kill** conformal flagging for a group if mean coverage under the **spatial** split is below 0.85 (nominal 0.90 minus 5 points), for
  score S1. The random split is expected to meet nominal by construction; it is reported, but it cannot rescue a spatial failure.
- If coverage holds but the false-flag rate is at least that of flagging every edge in the group, report that conformal flags carry no
  information for that group (the threshold is −∞ or at the bottom of the score range).
- Either result is written up. No re-run with other α, groups, cell sizes or scores before this report is written; any further analysis
  is labelled exploratory.

## Known limits, stated in advance

- One event (2015) and one proxy timestamp: the guarantee is within this corpus, not across monsoons. The research notes' preferred
  test (hold-out events) is not possible with the data we have.
- Few positives (about 118 edges in the crowd pool at age 0; fewer in `waterlogging`), so coverage per split is noisy.
- The label is weak (see above).
- No routing change is made from this study. Using conformal thresholds in the router would change the cost model, which needs the
  owner's approval and an ADR.
