# Independent re-analysis of Study 1

**Why it exists.** The team's harness scored each configuration under its own belief and counted penalty seconds as travel time, so configurations could not be compared. `reanalyze.py` fixes both problems:
- it scores every chosen route under one reference belief (C3 p̄ at the replay clock);
- it measures detours in free-flow time.

It also runs a z × λ sweep with a SciPy re-implementation of the edge cost. That implementation reproduced the Dart router's C3 node paths on 100 of 100 pairs.

**Run it:**

```
pip install numpy scipy
python3 reanalyze.py      # reads ../01_code/citypulse-IDP (scripts, graph, corpus, traces) and prior_sub.txt
```

**Inputs and outputs:**
- `prior_sub.txt`: the prior for the 14,534 hazard-config edges (`edge_id prior_logodds prior_p`), extracted from the 152 MB `chennai_prior_ell0.json`.
- Outputs:
  - `reanalysis_result.json`: all metrics, bootstrap intervals and the sweep;
  - `extra.json`;
  - `fig_pareto_common.*`;
  - `run2.log`.

**Not in this script.** The hybrid baseline, the observed/prior-only split and the holdout check were computed by the review's defence agent. See `../04_critique_and_review/deep_review/2_findings_and_defences/D3_evaluation_defense.md`. Porting them into this script is an open task.
