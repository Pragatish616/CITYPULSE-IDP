# Test baseline, 2 October 2026 (PLAN.md task M0.2)

Recorded before any code change in the October 2026 fix pass. Machine: Windows 11, Dart 3.13.2,
Flutter on `C:\src\flutter`, Python 3.12.2 (uv venv at `.venv/`). Commands are the ones in the
top-level `CLAUDE.md` §4.2, run from `01_code/citypulse-IDP`.

| Suite | Command | Passed | Failed | Skipped |
|---|---|---|---|---|
| `packages/pulse_belief` | `dart test` | 26 | 0 | 0 |
| `packages/pulse_router` | `dart test` | 80 | 0 | 0 |
| `packages/pulse_explain` | `dart test` | 75 | 0 | 0 |
| `app/` | `flutter test` | 41 | 0 | 0 |
| `scripts/tests` | `.venv/Scripts/python.exe -m pytest scripts/tests` | 42 | 0 | 0 |
| `server/` | `cd server && ../.venv/Scripts/python.exe -m pytest` | 33 | 0 | 0 |
| **Total** | | **297** | **0** | **0** |

Notes:
- The README's "250+" and the review's "about 290" are both consistent with 297.
- `pytest scripts/tests` takes about 90 s because one test shells out to the compiled router.
- The app's sync tests start a real FastAPI subprocess, so the venv must exist before `flutter test`.
- `app/assets/graph/` contains a stray 1.3 MB temp file `.chennai_graph_cli.json.DbI465` (an interrupted
  copy from 2 Oct). It is not listed in `pubspec.yaml` assets and is left in place pending owner approval to remove it.
