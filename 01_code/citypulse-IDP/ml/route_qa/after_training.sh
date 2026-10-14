#!/usr/bin/env bash
# Waits for a training run to finish, then runs the pre-registered automatic checks on it and on the untouched base model, on the same rows.
#   bash ml/route_qa/after_training.sh run1
set -u
RUN="${1:?run name}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PY="${PY:-python}"
RUNS="$ROOT/data/qa/2026-10-13/runs"
until grep -q '"finished": true' "$RUNS/$RUN/state.json" 2>/dev/null; do sleep 30; done
cd "$ROOT"
PYTHONIOENCODING=utf-8 "$PY" -u ml/route_qa/eval_model.py --run "$RUN" --n-u 300 --n-w 60 > "$RUNS/$RUN.eval.out" 2>&1
PYTHONIOENCODING=utf-8 "$PY" -u ml/route_qa/eval_model.py --run "${RUN}_base" --base-only --n-u 300 --n-w 60 > "$RUNS/${RUN}_base.eval.out" 2>&1
echo done > "$RUNS/$RUN.pipeline_done"
