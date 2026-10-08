# Next steps (gated plan from 2 October 2026)

There are two tracks, with different bars:
- **Research track:** needs honest evidence.
- **Startup track:** needs a live signal and a paying buyer.

## This week (by 8 October): tests before code

| Test | Cost | Pass | Fail |
|---|---|---|---|
| **Data test (10 min).** Open the CFM-DSS public WFS GetCapabilities, then pull one GetFeature from any subway-barrier, flood-meter or sensor layer. | 10 min | Per-location readings carry today's timestamp. | Static polygons or old snapshots only. Email GCC ICCC and GCTP the same day: "Can we poll barrier and sensor state this monsoon?" (Run 8 Oct: the first of two approved requests got HTTP 404, wrong path, so it is **inconclusive**; the layer catalogue has no subway or barrier layer; nothing was sent to GCC or the police; ADR-031.) |
| **Demand test.** Send a one-page offer for a season pilot (the council suggested about Rs 25,000) to 20 named buyers: fleets and dark stores, 5 insurer claims heads, and the two traffic-data vendors that serve GCTP. | Rs 0 | At least 2 signed LOIs naming a rupee figure | Compliments only |
| **Field-label pilot.** Pick 10 GCC subways. On every rain day, log a timestamped photo plus a passable / not passable / unknown flag. (Tool built 6 Oct, not deployed, no photos: `01_code/citypulse-IDP/docs/FIELD_PROTOCOL.md`. 9 Oct: 31 candidate subways from GCC's own table are in the tool, with an internal board and a plan: `01_code/citypulse-IDP/docs/PILOT_PLAN.md`.) | Rs 0 | 3 people can log 10 sites within 24 h of rain | Logging lags by more than a day |

## Gate on 15 October 2026

- **Live feed obtained:** continue the startup track, rescoped to GCC's 22 subways plus its 290 named waterlogging points.
- **No feed:** the startup track is KILLED. Ship the paper, and keep logging field labels as research data.

## Research track (runs whatever happens at the gate)

**Weeks 1–2: fix**, in this order (IDs from `KNOWN_FLAWS.md`):
1. F-02 · bidirectional snapping. **Done 2 Oct.**
2. F-01 and F-12 · Beta-quantile index. **Done 2 Oct** (ADR-015; constants are placeholders).
3. F-04 and F-07 · template fixes. **Done 2 Oct** (ADR-016).
4. F-05 · gate fixes. **Mostly done 2 Oct**; it needs an independent paraphrase set to support any error-rate claim.
5. F-09 · event gate. **Done 2 Oct.**
6. F-10 · sync paging. Open.
7. F-11 · ALT. Wording corrected 2 Oct; ALT is not wired in.
8. F-19 · Makefile. **Done 2 Oct.**
9. F-16 · Groq call moved server-side. Open (the key is still read from a compile-time define in `cloud_rewriter.dart`).

**Weeks 2–4: re-run the studies.** Study 1 and Study 2 were re-run on 2 Oct into `2026-10-02-*` folders. Study 2 still has to split its pools and control for edge length (F-14).
- Study 1: add the hybrid baseline and the observed/prior-only split, and report disconnections.
- Study 2: split the pools, control for coverage and edge length, and report the Brier skill score.
- Write results into new dated folders. Never edit old results.

**Weeks 3–8: labels and device.**
- Collect monsoon labels from the field protocol, any live layer, and timestamped official closure posts.
- Run the first test of the belief that does not reuse the belief itself.
- Run the app on a Rs 10–15k phone. Measure latency, memory, the size of the on-device prior, and the gate's pass and false-reject rates on real Tier 1 output.

**Submission.**
- Update `02_paper/` with the new numbers.
- Target ACM COMPASS, IEEE GHTC or ITSC, ISCRAM, or a SIGSPATIAL short paper. Check deadlines first.

## Startup track (only if the gate passes)

- **Product:** a passability layer for 22 subways and 290 points. Each point carries a timestamp, an age, a confidence and an explicit "unknown". It is delivered as a feed and a public map.
- **First buyers to test, in order:**
  1. a traffic-data vendor already serving the police;
  2. one fleet or dark-store operator;
  3. one insurer's claims team.
- Consumers will not pay, because Google is free.
- **Money:** pursue a CSR grant or a government innovation grant in parallel. The commercial bar is Rs 1 lakh committed in writing by one non-grant buyer before 15 December 2026.
- **Positioning:** sell timestamped evidence, never "safe routes" (ADR-011).
- **DPDP:** saved places stay explicit; no passive tracking.

## Stop doing

- Claiming novelty for flood-aware routing, report decay or ALT correctness.
- Calling explanations "verified" before error rates are measured.
- Using the Kotlin mock-up as evidence.
- Adding hazards or cities before one monsoon of Chennai labels exists. (The pipeline is now city-agnostic, ADR-018, so a second city is cheap when the time comes; it is still not started, and a new city has no flood data unless someone supplies a verified source.)

## Build tasks

The tests and the gate above are tasks M0.5–M0.8 in `../PLAN.md`. The research-track fixes are milestone M1 there, with steps and "Done when" checks for each.
