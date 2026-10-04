# Pre-registration, Part C3: the nationwide model applied to Chennai, a place it never saw (ADR-026)

Written and committed **before the nationwide model (all 91 maps) was trained and before it was applied to Chennai.**
Context: Parts A and A2 (Chennai-only models) and routing rounds 1 and 2 are finished and reported as found. The nationwide terrain model (Part B) passed on 11 maps; its all-maps run (addendum B2) is in progress.
This part asks whether that nationwide model, trained with **no cell from the Chennai study area**, ranks the December 2015 Chennai flood and routes people around it better than the alternatives.

## Design

- **Training data.** The all-maps samples of Part B2 (`national_samples_all.npz`) with **every sampled cell inside the Chennai study area (lon 79.3 to 80.35, lat 12.5 to 13.4) removed**. Model M1 exactly as in Part B (HistGradientBoosting, terrain features only, same weights, same seed). The best single feature is chosen on these training rows by weighted average precision.
- **Chennai grid at the same scale as the training data.** The 250 m grid of the flood map DFO_4001 (a Tamil Nadu map covering the whole study area), with the identical feature code (`window_features` of `scripts/sus_national_build_v2.py`), including the map's own permanent-water band. A cell is *modelled* if it has an elevation above 0 m, is not permanent water in that band, and its centre is not inside a mapped water body of the Chennai archive.
- **Truth.** A modelled cell is positive if its centre is inside the NRSC December 2015 flood extent (an independent source from the maps used in training).
- **Metrics.** Average precision (AP) and AUC over all modelled cells; 95% intervals by bootstrap over 0.05 degree blocks (1,000 resamples), shared between the model and the baseline so the difference is paired.
  For context, not for the rule: the same two numbers for the Part A local models are 0.2378 (AP) and 0.9208 (AUC) on a 90 m grid with different cells, so they are not directly comparable.

## Routing test (same design as round 2)

- The Chennai graph of 2 October 2026; a new variant `national`: prior values of the current pack allocated to edges in descending order of the nationwide model's score at the edge midpoint on the 250 m grid (equal prior mass, as in round 1; edges with no score get the lowest values).
- Compared with the variants already routed in round 2 on the **same 250 pairs**: `flat`, `gcc`, `model05`, `base05`, `random`, `oracle`; travellers `ped_l5`, `ped_l20`, `car_l5`; truth, detour measure and statistics as in round 2.

## Decision rule

1. **The nationwide model transfers to Chennai** only if its AP **and** AUC beat the best single feature's on the Chennai grid with the 95% interval of each difference above zero.
2. **The nationwide prior improves routing** only if, for **both** `ped_l5` and `ped_l20`: its exposure reduction against `flat` has a 95% interval above zero, its mean added free-flow time is at most 5% of the mean trip time, **and** its exposure is lower than `base05`'s and `random`'s, each with a 95% interval of the paired difference above zero (the D2 rule of round 2, applied to `national`).
Otherwise: no evidence. Nothing is tuned after the result.

## Known weaknesses stated in advance

- The 250 m grid blurs a 90 m street city; 250 m cells cannot represent a street.
- The nationwide model never saw Chennai's drainage or street layout; only terrain and permanent water.
- Training maps from Tamil Nadu outside the study area (2005, 2012 and 2015 floods) remain in training: they are the same state, not the same place.
- One flood event is the truth.
