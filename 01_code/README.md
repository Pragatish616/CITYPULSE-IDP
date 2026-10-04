# 01_code

| Folder | What it is |
|---|---|
| `citypulse-IDP/` | **The real codebase.** It is a clean copy of `Downloads/citypulse-IDP/citypulse-IDP` (the nested, newer repo), made on 2 October 2026. It contains the Dart packages, the Flutter app, the FastAPI server, the Python harness and the pinned data. |
| `citypulse-ai-kotlin-prototype/` | A copy of `Downloads/citypulse-ai`: an AI-generated Android UI mock-up. Use it for reference only. |

Left out of the copy:
- `.git` (history stays in the original folder);
- `.venv`, `.dart_tool`, `build/`, `.pytest_cache`, `.ruff_cache`, `__pycache__`;
- `data/osm/southern-zone-260911.osm.pbf` (557 MB raw Geofabrik extract, used only by the T0.2 timing spike; still in the original folder).

The compiled router CLI `citypulse-IDP/data/bin/pulse_router.exe` is included, so the Python harness runs without a Dart rebuild on Windows.

Build and run commands are in `../CLAUDE.md` §4.2.
