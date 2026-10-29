# CSFE B1, second exploratory run (addendum 2; 30 Oct 2026)

Same task, models and rules as `data/csfe/BENCHMARK_PREREGISTRATION.md`. Input: the v0.2 build after the fix of addendum 2 (city-median
rain attached to rows without a position). Earlier runs: `../2026-10-30-csfe-b1/` (invalid: rain window misaligned),
`../2026-10-30-csfe-b1-addendum1/` (exploratory, before the fix). This is the run the paper and the datasheet cite.

42 usable rows (32 closed), 3 events: Michaung (21 rows, all closed), 15 Oct 2024 (8, all closed), Fengal (13, 3 closed).

| Model | Brier | Skill vs base rate [95 % CI over events] | AUROC |
|---|---|---|---|
| Base rate | 0.368 | 0 | 0.05 |
| Subway history | 0.459 | −0.25 [−0.86, 0.43] | 0.17 |
| Rain logistic | 0.400 | −0.09 [−0.25, 0.00] | 0.05 |
| Rain + history | 0.390 | −0.06 [−0.20, 0.02] | 0.05 |

**Reading: no evidence that rain helps, no evidence that history helps beyond rain.** The reasons are those of addendum 1: only three
events have both labels and gauge rain, two of them are all-closed lists, and most subway negatives fall in the gauge gap (2022) or
after the gauge record ends (2026). The AUROC near 0 reflects that the only mixed event (Fengal) has its negatives on the heaviest rain
day and its later closure reports on a dry day (publication lag), not a meaningful inverse relation.
