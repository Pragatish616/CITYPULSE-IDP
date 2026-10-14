#!/usr/bin/env bash
# Keeps a dated copy of the adapter every 100 optimizer steps (train_lora.py overwrites `adapter/` every 25), so that an earlier
# checkpoint is still on disk if a later one turns out worse or the run is interrupted.
#   bash ml/route_qa/keep_checkpoints.sh run1
set -u
RUN="${1:?run name}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
D="$ROOT/data/qa/2026-10-13/runs/$RUN"
mkdir -p "$D/checkpoints"
last=0
while true; do
  if [ -f "$D/state.json" ]; then
    step=$(python -c "import json,sys;print(json.load(open(sys.argv[1]))['optimizer_steps'])" "$D/state.json" 2>/dev/null || echo 0)
    mark=$(( step / 100 * 100 ))
    if [ "$mark" -gt "$last" ] && [ "$mark" -gt 0 ] && [ ! -d "$D/checkpoints/step_$mark" ]; then
      # copy only when the saved state is exactly a multiple of 25 steps beyond the mark (adapter and state.json are written together)
      cp -r "$D/adapter" "$D/checkpoints/step_$mark.tmp" && mv "$D/checkpoints/step_$mark.tmp" "$D/checkpoints/step_$mark"
      cp "$D/state.json" "$D/checkpoints/step_$mark/state.json"
      last=$mark
    fi
    if grep -q '"finished": true' "$D/state.json" 2>/dev/null; then
      [ -d "$D/checkpoints/final" ] || cp -r "$D/adapter" "$D/checkpoints/final"
      exit 0
    fi
  fi
  sleep 60
done
