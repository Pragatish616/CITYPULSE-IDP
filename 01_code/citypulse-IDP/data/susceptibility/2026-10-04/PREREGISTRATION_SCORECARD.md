# Pre-registration: scorecard and stress test of the trained flood models (11 October 2026)

Written and committed **before** the stress script (`scripts/sus_stress.py`) is run. Requested by the owner: "test the ml model rigorously and give a score; if it is not efficient, say what a better training set or a better regression technique would be."

## What "the ml model" means here

The only trained models in this project are the ones below. The advisor (ADR-021/032), the event miner (ADR-030) and the accident logic are hand-set or unmeasured; nothing was trained for accidents (`docs/ACCIDENT_DATA.md`). They are **not** scored: there are no labels to score them against.

| ID | Model | Source of its numbers |
|---|---|---|
| N | Nationwide district flood-event model (ADR-025) | Existing pre-registered result; its 2016-2023 test years were used once and **are not re-used**. Scored from `result.json`, no re-run. |
| T | Nationwide terrain model (ADR-026 B2), 91 satellite flood maps | Existing result **plus the stress tests below** (new compute). |
| C | Chennai-local terrain models (ADR-026 A, A2) and the routing tests | Existing results, scored, no re-run. |

## The score (fixed now)

For each model: **skill = (M − B) / (1 − B)**, where M is the model's metric and B the best trivial baseline's, on the model's own pre-registered held-out evaluation. Two readings are given: average precision (AP, the harder one, the headline) and AUC. Also the **lift over the base rate** (AP / prevalence).
Bands, fixed before any new number is seen: skill ≥ 0.30 *useful*; 0.10 to 0.30 *modest*; 0 to 0.10 *marginal*; below 0, or a 95% interval that includes 0, *no evidence of skill*. A model's verdict is the lower of "its band" and "no evidence" if its interval for the difference to the baseline includes 0.

## Stress tests on T (new compute; same 2.61 million sampled cells, same features, same weights as `sus_national_train.py`)

All use the M1 settings of ADR-026 unchanged (HistGradientBoosting, lr 0.1, depth 4, 200 iterations, L2 1, seed 20261004) and the same weighting. Nothing is tuned.

1. **Reproduction.** Re-run the registered 2-degree-block five-fold CV; AP and AUC must equal the stored result to 3 decimals. If not, stop and report.
2. **Larger blocks.** Same CV with 5-degree and with 10-degree blocks (blocks assigned to five folds by the same hash rule). Spatial autocorrelation reaches further than 2 degrees; a score that survives large blocks is more credible, one that collapses was optimism.
3. **Negative control.** The same CV with the flood labels shuffled within each event (seed fixed). AUC must come out near 0.5 (within 0.45 to 0.55). Anything else means a leak or a bug and voids the other numbers.
4. **Calibration.** Isotonic regression fitted on the training folds' scores (weights as in evaluation), applied to the test fold; report the weighted Brier skill score against the weighted base rate of the training folds, the calibration slope and the expected calibration error (10 equal-count bins). The raw model is trained with balanced weights, so its scores are rankings, not probabilities (ADR-025 limit); this shows whether they can be made into probabilities at all.
5. **Spread across maps.** From the out-of-fold scores of test 1: the per-event AP and AUC, their median and the share of the 91 events with AUC above 0.5, 0.7 and 0.8.
6. **Slices.** The same out-of-fold scores restricted to: (i) cells with elevation at most 10 m (low coast and delta); (ii) peninsular India (latitude below 16 and longitude 76 to 81); (iii) the Gangetic plain (latitude 23 to 30, longitude 77 to 89). Each with its event count and a block bootstrap interval. The Chennai-relevant one is (ii).
7. **Learning curve.** Train on a fixed random 25%, 50% and 100% of the *events* in the training folds (5-degree blocks), test on the held-out folds. If the curve is flat, more maps of the same kind will not help.
8. **Feature ablation.** Drop each feature in turn (5-degree blocks); report the AP loss.

95% intervals everywhere are bootstrap over spatial blocks (1,000 resamples, paired between model and baseline), as in the earlier studies.

## Alternative techniques (exploratory; selection on the dev blocks only)

The question is whether a different regression technique or training set does better. To keep selection honest:

- Fix, by the same hash, **60% of the 5-degree blocks as dev blocks and 40% as lock blocks.** All comparisons below use dev blocks only (five-fold block CV inside them).
- Candidates (scikit-learn only; nothing is downloaded): (a) M1 as is; (b) HistGradientBoosting with monotone constraints from physics (risk non-increasing in elevation, minimum elevation, relief, TPI, slope, height above water and distance to water and sea; no constraint on elevation range); (c) logistic regression on spline-expanded features (a GAM-like model); (d) random forest (200 trees, minimum leaf 200, trained on a fixed random 400,000-row subsample for speed); (e) the best of (a) to (d) followed by isotonic calibration.
- **Rule for choosing:** the candidate with the highest dev-block AP; if the 95% interval of its AP difference to (a) includes zero, (a) is kept (the simpler model, already the project's).
- **Single lock evaluation:** train the chosen candidate and (a) on all dev-block cells, score the lock-block cells once. Reported whatever it shows. Only this lock result may be called a finding; the dev comparison is exploratory.

## What would count as "inefficient" and what is then proposed

If T's AP skill is below 0.30, or its score drops by more than a third under 5- or 10-degree blocks, or it fails the negative control, or the peninsular slice is weaker than the all-India figure by more than 0.10 in AUC, the report says so and proposes, with the evidence of tests 7 and 8, a better training set (what label, what resolution, what size) and a better technique. Proposals that were not tested here are labelled "not tested".

## Stated in advance as weaknesses

- The 91 maps are MODIS 250 m flood extents: they describe broad river and coastal flooding, not street flooding. A better score here says nothing about streets.
- Events overlap in space; larger blocks reduce but cannot remove that.
- The negatives are "not detected as flooded", not "dry".
- The lock blocks are a spatial hold-out of the same 91 maps, not new floods.
- The nationwide event model N and the Chennai models C are scored from results already on file; their held-out data were used once and are not re-used here.
