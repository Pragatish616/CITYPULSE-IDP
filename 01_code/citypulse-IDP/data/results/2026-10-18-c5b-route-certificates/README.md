# C5b: route certificates (18 Oct 2026)

Pre-registration: `ml/conformal/PREREGISTRATION.md`, section C5b, committed (4d31f85) before `scripts/c5b_route_certificates.py` was
written or run. One run; numbers from `result.json`.

## Data as it came out

1,000 Study 1 routes per configuration; 449 (C0) and 448 (C3) contain at least one of the 1,877 edges with an official report.
The prior covers every edge, with a floor of p = 0.02; 66 % of all edges sit at that floor.

## Results (alpha = 0.10, 200 random route splits; means)

| Config | Score | Rule | Route coverage | Share of route time flagged |
|---|---|---|---|---|
| C0 | S1 C3 p̄ | **Route certificate** | 1.00 | **1.00** (threshold = 0.02, the prior floor) |
| C0 | S1 C3 p̄ | C5 edge-level rule on routes | 0.885 (0.673 to 1.0) | 0.760 |
| C0 | S2 prior | Route certificate | 1.00 | 1.00 |
| C0 | S2 prior | C5 edge-level rule on routes | 0.957 | 0.912 |
| C3 | S1 / S2 | Route certificate | 1.00 / 1.00 | 1.00 / 1.00 |

## Decision (by the pre-registered rule)

- **Not killed** (route coverage 1.00 ≥ 0.85), but **uninformative**: the certificate holds only by flagging every edge of every route.
- Why: some officially reported edges lie where the GCC hazard map gives the minimum prior (0.02) and no crowd report exists. A route
  certificate must cover those too, so its threshold drops to the floor. No threshold on today's scores separates them.
- The edge-level C5 rule, applied to whole routes, misses at least one reported edge on about 1 route in 9 and still flags three quarters
  of route time.

## What this means

The method works as mathematics (coverage is guaranteed and was met); the scores it is given cannot support a useful route statement.
A route certificate becomes worth showing only with a score that ranks reported edges above the floor: independent, time-stamped
evidence (the project's standing conclusion). No router or app change was made.
