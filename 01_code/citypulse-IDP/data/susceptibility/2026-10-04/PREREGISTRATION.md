# Pre-registration: where water collects, from terrain and past floods (ADR-026)

Written and committed **before any feature is joined to a flood label and before any model is trained.** Nothing below changes after a result;
a change needs a new dated file and a note in the decision record.

## Why this study

The nationwide district model (ADR-025) asked "when is a flood event reported" and found no gain over two trivial rules. This study asks the
question the router's prior needs: **where does water collect, given terrain and drainage, judged against floods that really happened?**
Part A is regional (Chennai area), where independent flood maps and hotspot lists for three separate events exist and the fast terrain data is in hand.
Part B repeats the design nationwide on the Global Flood Database events that have finished downloading; it gets its own addendum before it is run.

## Part A: Chennai region

**Area.** Latitude 12.5 to 13.4, longitude 79.3 to 80.35 (the bounds of the 2015 flood extent, rounded outwards).
**Cells.** The 90 m Copernicus DEM grid (3 arc-seconds). A cell is modelled only if its elevation is above 0 m and its centre is not inside a mapped
water body (lakes, reservoirs, tanks, channel polygons, creeks, the Pallikaranai marsh, from the Chennai Flood Monitor archive).

**Labels (events).**
- *E2015:* a cell is positive if its centre is inside any of the 4,001 NRSC flood-extent polygons for December 2015; every other modelled cell in the area is negative.
- *E2005:* the same with the 235 IRS flood-extent polygons for 2005, **restricted to the box those polygons span** (lon 80.00 to 80.33, lat 12.85 to 13.29), the only area that map covers.
- *Points used only for external checks, never for training:* GCC 2015 hotspots (327), GCC 2020 monsoon hotspots (53), IRS 2005 hotspots with depth (200).
Negative means "not mapped as flooded", not "known dry".

**Features** (from the DEM and the drainage and water layers only; no flood data, no coordinates, no place identity):
elevation; slope; elevation minus the mean in an 11 by 11 cell window (about 1 km) and in a 55 by 55 window (about 5 km); elevation minus the minimum in the 55 by 55 window;
distance to the sea (cells at or below 0 m); distance to the nearest drainage line (rivers, streams, channels, canals, macro and micro drains); elevation minus the elevation of the
nearest drainage cell; distance to the nearest water body; elevation minus that of the nearest water-body cell.

**Models (fixed, no tuning).** (M) scikit-learn HistGradientBoostingClassifier: learning rate 0.1, max depth 4, 200 iterations, L2 1, balanced class weights, seed 20261004.
(L) logistic regression on standardised features, balanced class weights.
**Baselines.** Each single feature ranked in its physically sensible direction (lower elevation riskier, closer to drainage riskier, lower height above drainage riskier, flatter riskier, and so on).
The *best baseline* is the single feature with the highest average precision **on the training event**, chosen before looking at the test event.

**Evaluation.**
1. *Leave one event out:* train on E2005, test on E2015 (inside the E2005 box, and over the whole area); train on E2015 restricted to the E2005 box, test on E2005.
2. *Spatial blocks:* within E2015, 5 folds of 0.05 degree blocks (about 5.5 km) assigned by a fixed hash; train on 4 folds, test on the fifth.
3. *External points:* with the model trained on E2005 only, then on E2015 only, take each hotspot point's score and report its percentile among all modelled cells in the Chennai box (the E2005 box), and the share of points in the top 20% of cells.
   A point set is never used by a model that saw its own event: the 2015 hotspots are only scored by the E2005 model, the 2005 hotspots only by the E2015 model, the 2020 hotspots by both.
Metrics: average precision (AP), area under the ROC curve, the share of positive cells inside the top 10% of scores. 95% intervals: bootstrap over **0.05 degree spatial blocks**, 1,000 resamples.

**Decision rule.** The model (M) "adds value" only if (a) in both leave-one-event-out directions its AP beats the best baseline's with the 95% interval of the difference above zero, **and** (b) the same holds in the spatial-block evaluation,
**and** (c) on the external points its mean percentile is higher than the best baseline's in every point set it is allowed to score. Otherwise: no evidence of added value. No further features, models or tuning follow a failed rule.

## Part B: nationwide (to be specified by an addendum)

Same design on Global Flood Database event maps (CC BY-NC-ND 4.0, research use only), restricted to those that finished downloading when Part A's verdict is in; the list, the features available (DEM-derived plus the maps' own permanent-water band instead of the Chennai drainage layers),
the fold assignment and the decision rule will be fixed in an addendum committed before any of those maps is joined to features.

## Known weaknesses stated in advance

- Flood extents are satellite maps: cloud, urban double-bounce and narrow streets hide street-scale flooding; labels favour broad shallow areas.
- Negatives are unlabelled; the 2005 box and the 2015 area differ.
- Two events only for Part A; spatial autocorrelation is strong; block bootstrap reduces but does not remove optimism.
- 90 m DEM carries building and tree bias; Chennai is very flat, so elevation differences are small.
- Susceptibility is not passability and not a prediction of when.
