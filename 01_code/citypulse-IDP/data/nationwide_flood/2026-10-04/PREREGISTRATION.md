# Pre-registration: nationwide district flood-event model (ADR-025)

Written and committed **before any model is trained and before rainfall is joined to labels.** Nothing below may be changed
after seeing a result; a change needs a new dated file and a note in the decision record.

## Question

Does a model trained on district-days across India predict IMD-reported flood events better than two simple rules,
and does it carry over to states it never saw?

## Data

- **Label:** a district-day is positive if the district is named in an India Flood Inventory event (IMD) whose start-to-end dates
  include that day. Years 1990 to 2023. Built by `scripts/nw_build_registry.py` (`district_events.csv`).
  Negative means "not reported", not "dry": IMD reports notable events, so recall of small floods is unknowable.
- **Districts:** those the IFI names in 1990 to 2023 events that could be given a point by the geocoding rule in
  `scripts/nw_geocode.py`. Unresolved districts are excluded and their share of events reported.
- **Rainfall:** ERA5 daily precipitation at each district point (Open-Meteo), 1990 to 2023.
- **Features (all computed from rainfall, elevation and the calendar only):**
  rain today; sums over the last 3, 7, 14, 30 and 90 days (ending today); the largest single day in the last 7;
  each of these divided by a district climatology computed **from training years only** (mean annual rain, 95th percentile of
  wet-day rain, 95th percentile of 3-day sums); day-of-year as sine and cosine; elevation.
  **No latitude, longitude, state or district identity**, so that the state-holdout test means something.
  **No IFI-derived district tables** (the severity index and impact tables), which are computed from the same events and would leak labels.

## Splits

- **Train:** 1990 to 2009. **Validation:** 2010 to 2015, used only to pick among the grid below. **Test:** 2016 to 2023, evaluated once.
- **State holdout:** states are sorted by name and assigned to 5 folds in turn. For each fold, train on the other four folds' states
  (training years) and score the held-out fold on validation years.

## Model and grid (fixed)

scikit-learn `HistGradientBoostingClassifier`, class-weight balanced, learning rate in {0.05, 0.1}, max depth in {3, 5},
L2 regularisation in {0, 1}, at most 300 iterations with early stopping on validation log-loss; seed 20261004.
No other models, features or grids are tried.

## Baselines

- **B1:** the district's event-day rate in the same calendar month, from training years.
- **B2:** a rule: score = the district's 3-day rain divided by its training-year 95th percentile of 3-day sums.

## Metrics

- Average precision (area under the precision-recall curve) over all test district-days.
- **Event recall at a 2% alert budget:** a test (event, district) pair is caught if any day from one day before its start to its end
  has a score in the top 2% of all test district-days. Reported alongside the share of district-days alerted.
- Brier score and a reliability table, reported but **not** used to claim calibration.
- Uncertainty: bootstrap over **test years** (8 blocks, 2,000 resamples) for 95% intervals on each metric and on the model-minus-baseline difference.

## Decision rule (fixed now)

The model "adds value" only if, on the test years, it beats **both** baselines on average precision **and** on event recall at the 2% budget,
with the 95% interval of each difference above zero, **and** its state-holdout average precision is not below the better baseline's.
Otherwise the result is reported as: no evidence of added value. No further tuning, features or baselines follow a failed rule.

## Known weaknesses stated in advance

- Labels are reported events, not floods; reporting changed over 34 years.
- ERA5 under-reads extreme local rain; district points are seats, not centroids.
- A district named in a state-wide event gets a positive for every listed day.
- Some districts changed boundaries or names (new districts) between 1990 and 2023; names are matched as written.
