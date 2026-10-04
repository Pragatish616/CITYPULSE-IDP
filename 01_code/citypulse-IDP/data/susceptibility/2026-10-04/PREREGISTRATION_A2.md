# Pre-registration, Part A2: hydrology and street-pattern features for the Chennai region (ADR-026)

Written and committed **before the new features were joined to any flood label and before the model was trained.**
Part A (`PREREGISTRATION.md`) and its verdict (not met: the third rule, the external points) are final and stay as reported; this is a **second study**, started because of what Part A showed:
terrain at 90 m separated flooded from dry ground well over the whole region (AUC 0.92 in held-out blocks) but hardly at all inside the city (AUC 0.61), where the ground is flat and flooding depends on where water ponds and how fast it drains.
Part A's failure on the hotspot points is therefore treated as a reason to add *where water ponds and flows* and *how built-up the place is*, not as something to be tuned away.

## What changes, and what does not

Everything in `PREREGISTRATION.md` stands (area, cells, labels, models, baseline rule, evaluation, intervals, decision rule) **except** that five features are added to the ten of Part A:

1. `fill_depth`: how many metres a depression is filled to drain (priority-flood depression filling with a 1 mm gradient so flats drain; the sea and the grid border are outlets). Higher = water ponds more deeply.
2. `log_upslope`: log10 of the number of cells that drain through the cell after filling (D8 steepest descent). Higher = more water arrives.
3. `twi`: topographic wetness index, ln(upslope cells x cell width / tan(slope)), with tan(slope) at least 0.001. Higher = wetter.
4. `road_density`: length of the Chennai road graph's edges per square kilometre in an 11 by 11 cell window (about 1 km); a built-up proxy. Higher = more built-up.
5. `node_density`: graph nodes (junctions) per square kilometre in the same window.

The hydrology code is `scripts/hydrology.py`, with tests on grids whose answers can be worked out by hand (`scripts/tests/test_hydrology.py`, 6 tests, passing).
**Baselines:** the single-feature baselines of Part A plus these five, each in the direction written above (higher = riskier for the five; lower = riskier for the ten, as before). The *best baseline* is still chosen on the **training event** only.

## Decision rule (unchanged in form)

The model "adds value" only if (a) in both leave-one-event-out directions its AP beats the best baseline's with the 95% interval of the difference above zero, **and** (b) the same holds in the spatial-block evaluation, **and** (c) on the external points its mean percentile is higher than the best baseline's in every one of the four (point set, model) cases.
Otherwise: no evidence of added value. This is the **second** attempt on these data: if it is the only one that passes, the report says so and says that two rules were tried.

## Also reported (not part of the rule)

Feature importance by permutation on the held-out block folds; the AP of the Part A model on the same folds, for a like-for-like comparison.

## Known weaknesses stated in advance

- The 90 m DEM carries building and tree bias; hydrology on a 90 m grid cannot see storm drains, culverts or kerbs.
- The graph-based road density counts only drivable roads; it is a proxy for built-up area, not a measure of impervious surface.
- Chennai-only, two satellite flood maps and three hotspot lists; the same extents are reused from Part A, so the two studies are not independent.
