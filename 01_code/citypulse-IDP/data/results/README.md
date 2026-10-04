# results

One folder per run, named `<date>-<study>`, each with a `result.json` that records its seed, inputs and
router build. Old folders are never edited.

| Folder | What | Router build |
|---|---|---|
| `2026-09-17-*` | T3.1 corpus build, T3.2 replay engine | `data/bin/pulse_router.exe` |
| `2026-09-18-study1-route-quality`, `2026-09-18-study2-calibration` | First Studies 1 and 2 (Wald index, one-direction evidence). Superseded by the 2 Oct re-run; kept as the record | `data/bin/pulse_router.exe` |
| `2026-10-02-verifier-baseline`, `2026-10-02-verifier` | Explanation gate on the authored case set, before and after the fixes | n/a |
| `2026-10-02-study1-route-quality` | Study 1 re-run: 1000 pairs, 9 configurations | `data/bin/2026-10-02/pulse_router.exe` |
| `2026-10-02-study1-rescored` | Study 1 routes scored under one reference belief; paired bootstrap; held-out official check | same |
| `2026-10-02-study2-calibration` | Study 2 on the Beta replica, with prior-only baseline and skill scores | n/a (Python replica, parity-tested) |

`docs/DECISIONS.md` ADR-017 summarises the 2 Oct results and their limits.
