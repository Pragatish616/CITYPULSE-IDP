#!/usr/bin/env bash
# Copies the pinned map pack, the shared hazard-class config and the watchlist
# candidates into app/assets/ so Flutter can bundle them.
#
# Why a copy step and not a second checked-in copy: the pack lives once, under
# data/packs/<date>/, built by scripts/build_packs.py from the pinned
# data/graph/2026-09-14 snapshot (CLAUDE.md §7: snapshots are pinned by date and
# never silently updated). A second physical copy under app/assets/ could drift,
# so app/assets/packs/ and app/assets/data/ are gitignored and re-derived here.
#
# Usage: bash scripts/sync_data_assets.sh [city-id]
# Run after cloning, and again whenever the pack, config/hazard_classes.yaml,
# config/cities.yaml or the watchlist changes. `flutter build` / `flutter test` do NOT run this.
#
# The pack is ~15 MB. PLAN.md M2.6 moves it out of the APK into a downloadable
# pack; until then it is bundled.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_DIR="$REPO_ROOT/app"

# Which city's pack to bundle (ADR-018): the first argument, else $CITY, else the default_city in
# config/cities.yaml. The build must use the same id: flutter build ... --dart-define=CITY=<id>.
PY="python"
[ -x "$REPO_ROOT/.venv/Scripts/python.exe" ] && PY="$REPO_ROOT/.venv/Scripts/python.exe"
[ -x "$REPO_ROOT/.venv/bin/python" ] && PY="$REPO_ROOT/.venv/bin/python"
CITY="${1:-${CITY:-}}"
CITY_CFG="$("$PY" - "$REPO_ROOT/config/cities.yaml" "$CITY" <<'PYCFG'
import shlex, sys, yaml
doc = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
city = sys.argv[2] or doc["default_city"]
if city not in doc["cities"]:
    sys.exit(f"error: unknown city '{city}'; known: {', '.join(sorted(doc['cities']))}")
c = doc["cities"][city]
print(f"CITY={shlex.quote(city)}")
print(f"PACK_REL={shlex.quote(c['pack'])}")
print(f"WATCHLIST_REL={shlex.quote(c.get('watchlist') or '')}")
PYCFG
)"
eval "$CITY_CFG"
PACK_SRC="$REPO_ROOT/$PACK_REL"

for f in graph.bin nodes.bin meta.bin; do
  if [ ! -f "$PACK_SRC/$f" ]; then
    echo "error: $PACK_SRC/$f not found -- build the pack first (Chennai: scripts/build_packs.py; other cities: scripts/city_pipeline.py pack --city $CITY)" >&2
    exit 1
  fi
done

mkdir -p "$APP_DIR/assets/packs" "$APP_DIR/assets/config" "$APP_DIR/assets/data"
rm -f "$APP_DIR"/assets/packs/*
cp "$PACK_SRC"/graph.bin "$PACK_SRC"/nodes.bin "$PACK_SRC"/meta.bin "$APP_DIR/assets/packs/"
[ -f "$PACK_SRC/manifest.json" ] && cp "$PACK_SRC/manifest.json" "$APP_DIR/assets/packs/"
cp "$REPO_ROOT/config/hazard_classes.yaml" "$APP_DIR/assets/config/hazard_classes.yaml"
cp "$REPO_ROOT/config/cities.yaml" "$APP_DIR/assets/config/cities.yaml"

# The watchlist candidates file is 240 KB of fields the app does not need;
# reduce it to what the map draws.
"$PY" - "${WATCHLIST_REL:+$REPO_ROOT/$WATCHLIST_REL}" "$APP_DIR/assets/data/watchlist_candidates.json" <<'PY'
import json, sys
src, dst = sys.argv[1], sys.argv[2]
rows = json.load(open(src, encoding="utf-8")) if src else []
out = [
    {
        "id": r["candidate_id"],
        "lat": round(r["centroid_lat"], 6),
        "lon": round(r["centroid_lon"], 6),
        "category": (r.get("source_categories") or ["Unknown"])[0],
        "zones": r.get("n_source_zones"),
        "street": (r.get("snapped_edge") or {}).get("street_name"),
        "michaung_2023": (r.get("michaung_2023_cross_check") or {}).get("status"),
        "verified": bool(r.get("resident_signoff")),
    }
    for r in rows
]
json.dump(out, open(dst, "w", encoding="utf-8"), separators=(",", ":"))
print(f"watchlist candidates: {len(out)}")
PY

echo "synced city $CITY, pack $PACK_REL: $(du -ch "$APP_DIR"/assets/packs/*.bin | tail -1 | cut -f1)"
