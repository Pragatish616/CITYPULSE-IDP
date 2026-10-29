# CSFE B1, re-run after addendum 1 (exploratory; 30 Oct 2026)

Task, models and reading rules: `data/csfe/BENCHMARK_PREREGISTRATION.md`. The first, pre-registered run is in
`../2026-10-30-csfe-b1/` and is invalid as a test (rain window misaligned by a day; addendum 1). This re-run uses the corrected
window and is exploratory.

## Result

30 usable rows (24 closed), 10 subways, 3 events: Michaung (13 rows, all closed), 15 Oct 2024 (8, all closed), Fengal (9, 3 closed).

| Model | Brier | Skill vs base rate [95 % CI over events] | AUROC |
|---|---|---|---|
| Base rate | 0.274 | 0 | 0.06 |
| Subway history | 0.291 | −0.06 [−0.43, 0.33] | 0.23 |
| Rain logistic | 0.319 | −0.17 [−0.79, 0.00] | 0.06 |
| Rain + history | 0.311 | −0.14 [−0.70, 0.01] | 0.06 |

**Reading (pre-registered rules): no evidence that rain helps, no evidence that history helps beyond rain.**

## Why the data cannot answer the question yet

- Only 3 events have both labels and gauge rain: the gauge mirror has no data for 2020–22 or after Feb 2026, which removes the
  2021 closures, all 15 GCC "no water" rows of 2022 and the 2026 rows.
- Two of the three remaining events are all-closed lists, so leaving one out leaves a training set that is mostly one class.
- News lists record closures far more often than openings; negatives come almost only from one GCC "no water" post (2022) and one
  "waterlogged but open" post (Fengal 2024).
- The Fengal rows show the timing problem in miniature: subways listed as waterlogged but open at 09:58 on 30 Nov (115 mm that day),
  and others listed closed in a report published at 12:45 on 1 Dec (9.8 mm that day), although the closures most likely happened
  during the rain of the 30th; publication time is only an upper bound on when a status applied.

**Design lesson for the dataset:** collect explicit open/not-waterlogged statements during events the gauges cover, and record the
time a status applied, not only the publication time.
