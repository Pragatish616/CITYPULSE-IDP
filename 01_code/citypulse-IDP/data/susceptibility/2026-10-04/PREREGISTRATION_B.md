# Pre-registration, Part B: a nationwide terrain model on satellite flood maps of India (ADR-026)

Written and committed **together with the frozen list of maps (`national_events.json`) and before any map is joined to terrain features or any model is trained.**
Part A (Chennai) and its verdict are in `PREREGISTRATION.md` and `data/results/2026-10-04-susceptibility-chennai/`.

## Question

Across India, does a model of terrain, distance to permanent water and rainfall climatology rank flooded cells above dry cells better than the best single terrain feature,
in places it was not trained on?

## Data

- **Flood maps.** The Global Flood Database maps (MODIS, 250 m; Tellman et al. 2021; CC BY-NC-ND 4.0, research use only) whose Dartmouth event id is in our India event list (ADR-023) and that had finished downloading when the list was frozen. The bucket is reached at about 40 KB/s from this machine and was fetched smallest first, so **the list is biased toward events with small map footprints**; the file records the freeze time and each file's size and MD5.
  A map is skipped, and the skip is reported, if it has more than 80 million cells or needs more than 80 DEM tiles.
- **Cells.** A cell is *observed* if its flood value is defined, it had at least 5 clear satellite views, and it is not permanent water (the map's own JRC band). Positive: flooded. Negative: observed and not flooded. Negative means "not detected as flooded".
- **Sampling.** Per event, up to 15,000 positives and 15,000 negatives drawn uniformly at random (seed 20261004), carrying weights that restore the event's true counts of observed positives and negatives.
- **Features (no flood label is used to build any).** From the 90 m Copernicus DEM resampled to the 250 m grid: mean, minimum and range of elevation; slope; elevation minus the 5 km minimum (relief) and minus the 5 km mean (TPI); distance to the sea (cells at or below 0 m); distance to the nearest permanent-water cell of the map and elevation minus that cell's elevation.
  *Rainfall climatology* (second model only): mean annual rainfall and the 95th percentile of wet-day rainfall for 1990 to 2009 at the nearest NASA POWER district point within 150 km (the rainfall data of ADR-025); missing beyond 150 km.
  No coordinates, no event identity.

## Models and baselines (fixed, no tuning)

- **M1:** scikit-learn HistGradientBoostingClassifier on the terrain features: learning rate 0.1, depth 4, 200 iterations, L2 1, seed 20261004, trained with sample weights that give each event total weight 1 and equal class weight within it.
- **M2:** the same with the two rainfall-climatology features added.
- **Baseline:** the single terrain feature (lower value = riskier) with the best weighted average precision on the training folds.

## Evaluation

- **Primary: spatial blocks.** All sampled cells of all events pooled; 2 degree by 2 degree blocks assigned to 5 folds by a fixed hash; out-of-fold scores pooled. Metrics: weighted average precision (AP) and weighted AUC, each event normalised to equal weight and sampled cells re-weighted to the event's true class sizes.
  95% intervals: bootstrap over blocks, 1,000 resamples, shared between models so differences are paired.
- **Secondary: later events.** Train on events up to 2012; test on events from 2013, only in blocks that contained no training cell. Reported with the same metrics if at least 500 test cells, 20 positives and 20 negatives remain; otherwise reported as skipped.
- Per-event AP and AUC are tabulated for M1 and the baseline.

## Decision rule

1. **The terrain model adds value** only if M1's AP **and** AUC beat the best single feature's with the 95% interval of each difference above zero (primary evaluation).
2. **Rainfall climatology adds value** only if M2's AP **and** AUC beat M1's with the 95% interval of each difference above zero.
Otherwise the corresponding statement is: no evidence. No further features, models or tuning follow a failed rule.

## Known weaknesses stated in advance

- 250 m MODIS flood maps catch broad river and coastal flooding and miss street-scale urban flooding; cloud limits observation (the clear-view rule is a partial guard).
- Events overlap in space, so cells are not independent; blocks reduce but do not remove this optimism.
- The event list is whichever small maps arrived; it is not a random sample of Indian floods.
- Terrain tells where water can collect, not when; the model is a prior, not a forecast.
- The maps are non-redistributable: derived samples, results and the model file are kept out of git except the aggregate result file.
