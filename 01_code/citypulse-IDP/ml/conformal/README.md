# Conformal flags (C5)

`flags.py`: label-conditional (Mondrian) split conformal thresholds. For each group the threshold is the k-th smallest calibration-positive
score, k = floor(alpha (n + 1)), so that under exchangeability at least 1 - alpha of positives score at or above it. Tested on synthetic
scores in `tests/` (`python -m pytest ml/conformal -q` from `01_code/citypulse-IDP`).

The pre-registered evaluation on the 2015 corpus is `scripts/c5_conformal_eval.py` (`PREREGISTRATION.md`), and the result is in
`data/results/2026-10-17-c5-conformal/`: coverage held (0.894 on a spatial split, kill line 0.85), but reaching it flags about half the
edges that have no official report, and crowd reports barely improve on the prior alone.
