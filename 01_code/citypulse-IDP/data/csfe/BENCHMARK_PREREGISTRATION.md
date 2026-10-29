# CSFE benchmark task B1: subway closure from rain (pre-registered 30 Oct 2026)

Written and committed **before** the evaluation script was written or run, and before the v0.2 subway rows were compared with rain.
(The v0 descriptive table in `README.md`, 13 closure rows against 133 crowd "no water" rows, was seen earlier; this task uses a
different unit and adds the v0.2 news rows.) Changes after the first run go in a dated addendum and make the run exploratory.

## Task

Unit: one news report about one subway that is linked to the subway watchlist (`subway_timeline.csv` in the v0.2 build).

- **Label 1:** status `closed`.
- **Label 0:** status `not_waterlogged`, `waterlogged_open` or `open`.
- **Excluded:** `partly_open` (one row), and rows with no rain attached (no gauge data for that date).

Features (all from the build, nothing else): `rain_day_mm_city_median` (the city median of the 24 h gauge reading containing the report),
`rain_prev2d_mm_city_median`, and `rain_day_mm_nearest`.

## Evaluation

Leave one event out: for each event, fit on the other events and predict that event's rows. Pool the out-of-event predictions.

Models, all fitted only on training folds:

1. **Base rate:** the training-fold share of label 1.
2. **Subway history:** the subway's share of label 1 in the training folds (base rate if the subway is unseen).
3. **Rain logistic:** logistic regression on log(1 + rain_day_mm_city_median) and log(1 + rain_prev2d_mm_city_median), with
   scikit-learn defaults (L2, C = 1).
4. **Rain + history:** model 3 plus the history feature of model 2.

Metrics on the pooled out-of-event predictions: Brier score, Brier skill against the base rate, AUROC, and the number of rows and
events used. 95 % intervals by bootstrap over events (2,000 resamples, seed 20261030).

## Reading, fixed now

- **Rain helps** only if model 3's Brier skill against the base rate has an interval above 0.
- **History helps beyond rain** only if model 4 beats model 3 with an interval above 0 on the paired difference in Brier score.
- With so few events, an interval that includes 0 is the expected outcome and is reported as "no evidence", not as "no effect".
- This is a prototype task to show the data supports the question; it is not a result about Chennai subways.

## Addendum 1 (30 Oct 2026, after the first run): rain window corrected; the re-run is exploratory

The first run (`data/results/2026-10-30-csfe-b1/`, input build now kept as `data/csfe/2026-10-30-windowA/`) attached rain under
convention A: a gauge reading dated D was assumed to cover the 24 h ending 08:30 IST on D. Looking at the build's rows afterwards
showed this is wrong for these gauges. Every storm checked has its heavy totals on the readings dated the days of heavy rain and near
zero on the reading dated the day after the rain stopped (Michaung: 195 and 212 mm dated 3 and 4 Dec 2023, then 0.0 dated 5 Dec;
Fengal: 115 mm dated 30 Nov 2024). The readings therefore cover about 08:30 on D to 08:30 on D+1 (convention B). This evidence comes
from the rain series, not from the labels.

- The first run stands as recorded and is **invalid as a test**, because its rain feature was misaligned by a day for most rows.
- The build now uses convention B (`WINDOW = "B"` in `scripts/build_csfe_proto.py`); the task, models, metrics and reading rules
  above are unchanged.
- The re-run (`data/results/2026-10-30-csfe-b1-addendum1/`) is **exploratory**, because the rows had been seen before it.

## Addendum 2 (30 Oct 2026): a build bug fixed; a second exploratory run

The build attached rain only to rows with a position, although the city-median rain needs none. Twelve subway reports linked to
watchlist subways without a position (8 Michaung closures, 4 Fengal "waterlogged but open") therefore had no rain and were left out of
B1. The build now attaches the city median to every timed row (nearest-gauge rain still needs a position). The task and rules are
unchanged; the run on the fixed build (`data/results/2026-10-30-csfe-b1-addendum2/`) is exploratory, like addendum 1.
