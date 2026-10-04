# Pre-registration: does a learned flood prior route people away from a real flood? (ADR-026, part C)

Written and committed **before the model's routing effect was measured.** Nothing below changes after a result.

## Question

Given the router's cost model, does replacing the per-edge flood prior with one learned from the 2005 flood (and nothing else) reduce how much of
people's routes lies inside the December 2015 flood, compared with other ways of allocating the same prior values, without long detours?

## Design

- **Graph and packs.** The Chennai pack of 2 October 2026 (193,191 nodes, 471,240 edges). Five variants share its graph and differ **only in `meta.bin`'s per-edge prior**, and every variant except "flat" holds exactly the same multiset of prior values as the current pack
  (equal prior mass, different allocation). The check is an assertion in the script.
  - `gcc`: the current prior (built from the Greater Chennai Corporation 2015 hazard zones, so it contains information about the 2015 event; a **reference, not a competitor**).
  - `model05`: prior values given to edges in descending order of the susceptibility model trained on the **2005 flood only** (Part A), scored at the edge midpoint; edges with no score get the lowest values.
  - `base05`: the same allocation using the single feature (lower = riskier) that was the best baseline on the 2005 training event in Part A.
  - `random`: the same values allocated at random (fixed seed).
  - `flat`: every edge at the flat value (no prior information).
- **Routes.** 600 seeded random node pairs (seed 20261015), the commuter and pedestrian traveller classes, flood event state **active** (the only state in which the prior is used), the engine's normal cost. Pairs for which any route is missing are dropped and counted.
- **Truth.** The share of a route's length (sampled every 50 m) whose 90 m grid cell lies inside the NRSC December 2015 flood extent. Neither `model05`, `base05` nor `random` has seen the 2015 event.
- **Detour.** The change in the route's free-flow time against the `flat` route for the same pair.

## Statistics

Paired differences over pairs; 95% intervals by bootstrap over pairs (2,000 resamples, seed fixed in the script).

## Decision rule

`model05` "improves routing" only if **all** hold:
(a) for both traveller classes, its exposure reduction against `flat` has a 95% interval above zero;
(b) for the pedestrian class (the class whose risk weight is large enough for a prior to matter), its exposure is lower than `base05`'s and than `random`'s, each with a 95% interval of the paired difference above zero;
(c) its mean added free-flow time against `flat` is at most 5% of the mean `flat` trip time, for both classes.
Otherwise: no evidence that the learned prior improves routing. `gcc` is reported alongside but is not part of the rule.

## Known weaknesses stated in advance

- One flood event is the truth; flood extent is satellite-mapped and misses street-scale flooding.
- Uniformly random node pairs are not real trips; many are long.
- The commuter class is nearly hazard-blind by construction (its risk weight is 0.3), so a null result there is expected.
- A prior value allocation by rank ignores how large each score gap is.
