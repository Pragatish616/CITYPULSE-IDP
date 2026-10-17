# C5: conformal flags for flood-reported edges (17 Oct 2026)

Pre-registration: `ml/conformal/PREREGISTRATION.md`, committed (0dd6a7a) before `scripts/c5_conformal_eval.py` was written or run.
One run. Numbers below are copied from `result.json`.

## Data as it came out

- 14,336 edges: 9,336 with a crowd report (both directions of two-way streets, the F-02 fix) and 5,000 with none.
- 226 positives (edges that also carry an official report). The pre-registration expected "about 118"; that figure was from the old
  one-direction pools.
- **Only one group exists.** Every crowd edge's dominant hazard class is `flood` (`choose_dominant_hazard_class` picks the more severe
  class), so the pre-registered `waterlogging` group is empty. Nothing was re-grouped; results are for `flood` only.

## Results (alpha = 0.10, 200 splits each; mean, with 5th to 95th percentile)

| Split | Score | Coverage of positives | False-flag rate (negatives flagged) |
|---|---|---|---|
| Random | S1 C3 p̄ | 0.904 (0.833 to 0.960) | 0.546 (0.483 to 0.641) |
| Random | S2 prior only | 0.907 (0.830 to 0.958) | 0.577 (0.558 to 0.592) |
| Spatial blocks (0.01°) | S1 C3 p̄ | **0.894** (0.778 to 0.976) | 0.544 (0.448 to 0.662) |
| Spatial blocks (0.01°) | S2 prior only | 0.893 (0.773 to 0.978) | 0.572 (0.516 to 0.617) |
| Either | C1, flag if p̄ ≥ 0.5 | 0.000 | 0.000 |

Median thresholds: S1 p̄ ≥ 0.123, S2 p ≥ 0.030.

## Decision (by the pre-registered rule)

- **Not killed.** Spatial-split coverage for S1 is 0.894, above the 0.85 kill line.
- **But the flags are expensive.** To catch 9 in 10 official-report edges, the threshold also flags about 54 % of edges with no official
  report. That matches Study 2's weak discrimination (AUROC about 0.6).
- **The crowd evidence adds almost nothing.** S1 (prior plus crowd) flags 54.4 % of negatives, the prior alone 57.2 %, at the same
  coverage. Consistent with every earlier result on this corpus.
- **The fixed 0.5 rule never fires on these edges** (no edge reaches p̄ = 0.5 at report age 0), so it covers none of the positives.
  A conformal threshold at least states what it covers; a hand-set one can silently cover nothing.

## What this means and what it does not

- Conformal calibration does what it promises here: a threshold with a checkable coverage statement, which held when the test edges
  were in places the calibration had not seen.
- It does not make the underlying score better. With this score, an honest 90 % coverage means flagging most of the network.
- Within one event (2015) and one proxy timestamp; the label is co-location with an official report, not observed flooding.
- No change was made to the router. Routing on conformal thresholds would change the cost model and needs the owner's approval and an ADR.
