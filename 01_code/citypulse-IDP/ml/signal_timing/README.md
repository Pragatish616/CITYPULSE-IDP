# Traffic signals (C8)

Two parts.

**1. Signals on the route (built, in the router).** The places layer (`data/places/chennai-poi-2026-10-15/poi.json`, from OpenStreetMap)
has 485 `highway=traffic_signals` points in the Chennai box. `bootstrapRouter` snaps them to graph nodes (within 30 m: 465 distinct nodes)
and every route gets a `route_signals` context fact: the number of distinct signal nodes it passes. The time answer then says, for
example, "It passes 9 traffic signals; waiting at them is not in that time." (T. Nagar to Velachery, real pack,
`services/router_api/test/signals_real_test.dart`). It is a count, not a wait: OpenStreetMap has no timing, and its signal coverage of
Chennai is incomplete, so a route with no counted signal is not described as having none.

**2. Learning waits from traces (`learner.py`, tested on simulated data only).** Given vehicle passes through one approach of one
signal, it estimates per time-of-week bin: the cycle length, the red time, and the median and 85th-percentile delay. Method and
thresholds are in the module docstring. `simulate.py` makes synthetic passes (fixed-time signal, simple kinematics, 1.5 m GPS noise,
1 Hz); results on it:

| Simulated signal (cycle / red) | Cycle found | Red found | Passes |
|---|---|---|---|
| 60 / 30 s | 60.0 s | 27.8 s | 200 |
| 90 / 45 s | 90.0 s | 42.9 s | 200 |
| 120 / 70 s | 120.0 s | 68.4 s | 200 |
| 150 / 90 s | 150.0 s | 86.7 s | 200 |

A signal whose red varies at random (as at a police-controlled junction) is reported as having no fixed cycle. With fewer than 10 usable
passes no delay is given. **These numbers show the method recovers what the simulator put in. They say nothing about any real signal.**

Run the tests from `01_code/citypulse-IDP`: `python -m pytest ml/signal_timing -q`.

## What is not built

- Map matching of raw GPS traces to (time, distance to stop line) series per signal approach.
- Any source of real traces. The app records no trips (DPDP Act: no passive location collection, ADR-006).
- Feeding learned waits into route times. That would change the cost model, which needs the owner's approval and an ADR.

## Study protocol (pre-registered, 17 Oct 2026; not run)

Purpose: find out whether the learner recovers real Chennai signal cycles from volunteer drives. The kill rule is the one set in the
team's research notes before any of this was built.

- **Sites:** 10 signals, listed in the data log before the first drive: main-road junctions with an OpenStreetMap signal node on the
  approach. One of them is driven first as a pilot (to test logging, not to tune anything).
- **Data:** the team drives or rides through each chosen approach with a phone logging GPS at 1 Hz (for example phyphox or any logger
  exporting time, latitude, longitude). No other people's data. Logs stay on the team's machines.
- **Ground truth:** at each site, one person times 10 consecutive cycles with a stopwatch (green start to green start, and red length)
  in the same time-of-week bin as the drives, written down before the traces are processed.
- **Sample:** at least 30 passes per site in one bin, over at least 3 days.
- **Primary outcome:** per site, absolute error of the learned cycle against the stopwatch median. **Kill** the approach if the median
  error over the sites with a fixed cycle is over 15 s. Secondary: the share of sites the learner calls "no fixed cycle", against what
  the stopwatch shows; red within 15 %.
- **No tuning:** `LearnerConfig` stays at its committed values. Any change is re-registered before data is processed.
- **Report either way,** including sites where no cycle was found (the signal may be actuated or police controlled, which is itself a
  finding).
