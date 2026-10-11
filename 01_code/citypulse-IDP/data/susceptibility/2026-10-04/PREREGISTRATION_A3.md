# Pre-registration, Part A3: do street-scale OpenStreetMap features fix the city core? (ADR-034, 11 October 2026)

Written and committed **before the OpenStreetMap features are built and before they are joined to any flood label.** It follows the scorecard (ADR-033), which found that the terrain models are marginal inside Chennai's core (2005 to 2015: AUC 0.614 against 0.564 for the best single feature, AP skill 0.08) and show no advantage over one feature where cells are 10 m above sea level or lower.
Part A and A2 and their verdicts stay as reported. **This is the third study on the same two Chennai flood extents and three hotspot lists, so the three are not independent**; if A3 is the only one that passes, the report says three rules were tried.

## Question

Do building cover, built-up and green land use, and distance to mapped waterways and water bodies, taken from the pinned OpenStreetMap extract, make the Chennai model rank flooded cells above dry ones better *than the A2 feature set does*, inside the city core and across held-out blocks?

## Data (all already on disk; nothing is downloaded)

- **OpenStreetMap extract** `southern-zone-260911.osm.pbf` (ODbL 1.0), the pinned snapshot of the project, read by `scripts/extract_osm_chennai.py` for the whole extent of the grid (12.48 to 13.42 N, 79.28 to 80.37 E, the grid plus 0.02 degrees), so that no modelled cell lacks OSM coverage by design.
- **Grid and labels:** `grid.npz` and `grid_a2.npz` exactly as in A2 (1080 by 1260 cells of 90 m; 2015 and 2005 flood extents; hotspot lists).
- Closed ways only. Multipolygon relations (large lakes, some parks) are **not** read; this is a known gap.

## Features (all label-free, built by `scripts/sus_build_a3.py`)

1. `bld_share_90m`: building-footprint area in the cell divided by the cell's area (each building counted in the cell of its centroid), capped at 1. Higher is taken as riskier.
2. `bld_share_1km`: the mean of `bld_share_90m` over an 11 by 11 cell window. Higher = riskier.
3. `built_landuse_1km`: share of cells inside landuse polygons residential, commercial, industrial, retail or construction, mean over the same window. Higher = riskier.
4. `green_landuse_1km`: share of cells inside landuse grass, forest, meadow, farmland, orchard, recreation_ground or leisure park/garden/pitch, same window. **Lower** = riskier.
5. `dist_waterway_km`: distance to the nearest mapped waterway line (river, stream, canal, drain, ditch). **Lower** = riskier.
6. `dist_waterbody_km`: distance to the nearest mapped water polygon (natural=water, landuse reservoir or basin). **Lower** = riskier.

Directions are fixed here. Completeness of OSM buildings differs across the city; the report gives, for each feature, the share of modelled cells with a non-zero value, and the correlation of `bld_share_1km` with the A2 `road_density`.

## Models and evaluation (identical to A2 except the feature set)

- **Model family B (A3):** the 15 A2 features plus the 6 above; the same gradient-boosted classifier, folds, cells, labels, bootstrap (blocks of 0.05 degrees, 1,000 resamples, draws shared and paired) as `scripts/sus_train_a2.py`.
- **Comparator (A2):** the 15 A2 features, trained on exactly the same rows and folds in the same run, so the difference is paired.
- **Baselines:** the single-feature baselines of A2 plus the six new ones, each in its fixed direction; the best is chosen on the training event only.
- Tests: (i) train 2005, test 2015 inside the 2005 box (the city core); (ii) train 2015 (box), test 2005; (iii) five-fold spatial blocks over the whole area for 2015; (iv) the external hotspot points as in A2.

## Decision rule (about the new features, not about the model overall)

**The OSM features add value** only if (a) in **both** core directions, (i) and (ii), the AUC of B exceeds the AUC of A2 with the 95% interval of the paired difference above zero, **and** (b) in the spatial blocks (iii) the AP of B exceeds the AP of A2 with the 95% interval of the paired difference above zero.
Otherwise: no evidence that they help. AUC is the core metric because the core's failure was in AUC (the base rate there is 15%, so AP is high for any model).

Also reported, not part of the rule: the A2 rule (a, b, c) applied to B; each new feature's permutation importance on the held-out fold 0; B's AUC and AP against the best baseline in each test; the same comparison restricted to cells at most 10 m above sea level.

## Known weaknesses stated in advance

- OpenStreetMap completeness in Chennai is uneven; building and land-use coverage may follow mapping effort, not the city.
- Building area is attributed to the centroid's cell; relations are skipped.
- Mapped waterways and drains are far from the full storm-drain network.
- The labels are satellite flood extents (December 2015, 2005) and hotspot lists, not street passability; a gain here would not prove a gain for streets.
- Same labels as A and A2: repeated looks at the same data raise the chance of a false positive; the report counts them.
