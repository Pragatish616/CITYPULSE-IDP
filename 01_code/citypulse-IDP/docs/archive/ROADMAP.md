# Roadmap — 7 weeks, revised

The original deck's plan put the core novelty ("offline-resilient, confidence-aware routing")
in week 5. That is too late: the entire project rests on assumptions that are cheap to test
now and expensive to discover in week 5. This plan front-loads the risk.

## Week 1 — Kill the risks, not the backlog

**Four** de-risking spikes, in parallel, all before any feature work (a fourth was added in
the 2026-09-12 review — the watchlist itself is a fatal-risk assumption exactly like the SLM
and the graph, and previously wasn't tested until week 2):

1. **SLM on cheap hardware.** Get a ₹10–15k Android. Run Gemma 3 270M INT4 via
   `flutter_gemma`. Measure TTFT, decode rate, peak RSS, battery. **If it is unusable, the
   explanation story changes shape and we need to know now.**
2. **Graph + query time.** Geofabrik TN extract → CSR adjacency → bidirectional Dijkstra over
   1 000 random OD pairs. Expect 10–40 ms. Confirm the node count and the graph size on disk.
3. **Ethics application submitted** for the human study (Study 5). Long lead time; cannot be
   compressed later. **A faculty PI must file this, not a student — line that up first.**
4. **Watchlist feasibility (T0.5, added 2026-09-12).** Can ≥100 validated, edge-resolved
   watchlist points actually be sourced from open data, and is the CMWSSB reservoir page
   reachable at all from India? This is ADR-009's own "Reconsider if" test, run now instead of
   discovered mid-week-2.

Also this week: claim the free-tier accounts (`docs/APIS_AND_COSTS.md`), apply for the Tier 2
data sources that need lead time (IMD, SACHET, IIT-M dataset), pin the OSM snapshot date.

**Week 1 exit criteria:** four spike reports in `data/results/`, each with a number and a
go/no-go. Written into `docs/DECISIONS.md` whatever the answer.

## Week 2 — Belief + cost, and the replay harness

`pulse_belief`: log-odds fusion, per-class decay, `n_eff`, pessimistic plug-in.
`pulse_router`: ALT landmarks, the ADR-003 cost function, chance-constraint edge removal, and
the **structured decision trace** (design this carefully — three later components consume it).
Build the static hazard prior `ℓ₀` from OpenCity inundation + elevation/HAND.

Build the **replay harness** now, not later. It is what makes the project survive if no live
feed ever materialises.

## Week 3 — Study 1 and Study 2 run end to end

Yes, in week 3. Run them on whatever quality of data exists, produce ugly first numbers, and
find out what the harness is missing while there is still time to fix it. Configurations
C0–C4 and the oracle. First reliability diagrams.

## Week 4 — Explanation layer

Tier 0 template renderer over the decision trace. The symbolic verifier. Tier 1 SLM rewriter
with the verifier gate and silent fallback. Cloud LLM path (no raw coordinates, ADR-007).
Run Study 3 as soon as 50 explanations exist — do not wait for 300.

## Week 5 — Client

Flutter app: MapLibre + PMTiles offline, SQLite/R*Tree hazard cache, outbox sync, confidence
badges in the UI, one-tap route. Live feed ingest on the server (Open-Meteo, GDACS, TomTom,
CMWSSB scraper) with SSE push.

## Week 6 — Study 4 + Study 5 + hardening

Connectivity ladder experiments. Run the human study (approval should have landed).
Demo insurance: Cloudflare Tunnel fallback, cached demo scenario that works with the venue
wifi switched off — which is, conveniently, the actual feature.

## Week 7 — Write-up

Paper per `paper/OUTLINE.md`. Final figures from `data/results/`. Demo rehearsal with the
network physically disabled.

---

## Standing rules

- **Nothing goes in the paper without a script that reproduces it.**
- **A failed assumption is a result.** Write it up; do not quietly reroute around it.
- Re-run Studies 1–3 after any change to the belief model or cost function. Tag the commit
  `exp:` so results stay traceable.
