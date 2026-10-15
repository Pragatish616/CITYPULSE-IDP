# CityPulse AI: context for a second coding agent

Written 15 October 2026 for an agent joining mid-project. Read this, then [`INSTRUCTIONS.md`](INSTRUCTIONS.md), then the root [`CLAUDE.md`](../CLAUDE.md).
Where they disagree, **`CLAUDE.md` wins**.

## 1. What the project is

CityPulse AI is a research prototype of flood-aware, offline-first navigation for Chennai, with Tamil Nadu main roads for routing only. It is a
credited B.Tech IDP project at VIT Chennai. The team is Pragatish N (owner), Ravi R Kamath and Jyotish N. The budget is Rs 0, so free tiers only.

It routes on a per-street flood belief. The belief fuses Greater Chennai Corporation hazard zones with reports that fade with age. The edge cost
separates slowdown from harm. Explanations come from templates and pass a symbolic verifier. A bilingual question box answers questions about the
route and **never gives a safety verdict**. The repository's purpose is defensible measurement. The negative results (crowd reports added nothing
on the 2015 replay, the belief is uncalibrated) are part of the product. Never hide or soften them.

## 2. Where things are

The git root is this folder (`final_citypulse_ai_idp`). The remote is `https://github.com/Pragatish616/CITYPULSE-IDP`, and the repo is **public**.

| Path | What |
|---|---|
| `01_code/citypulse-IDP/packages/pulse_router` | Dart router: CSR graph, cost model, bidirectional Dijkstra, advisor, decision trace |
| `01_code/citypulse-IDP/packages/pulse_belief` | Dart belief: log-odds fusion, Beta-posterior pessimistic index |
| `01_code/citypulse-IDP/packages/pulse_explain` | Template, verifier, **route question answerer** (`route_qa.dart`), **model ladder** (`question_labeler.dart`) |
| `01_code/citypulse-IDP/app` | Flutter app: Android, web, **Windows test app** (`lib/main_desktop.dart`) |
| `01_code/citypulse-IDP/services/router_api` | Dart HTTP router service (Chennai + Tamil Nadu), event state, rain poller |
| `01_code/citypulse-IDP/server` | FastAPI report ingest and volunteer field log |
| `01_code/citypulse-IDP/ml/route_qa` | Question-model training, export (`export_merged.py`), checks (`eval_model.py`, `eval_gguf.py`), `MODEL_CARD.md` |
| `01_code/citypulse-IDP/tools/model_check` | Runs the GGUF model through the app's own labeler class |
| `01_code/citypulse-IDP/data` | Pinned data, map packs, results, pre-registrations (most large files are git-ignored) |
| `.github/workflows` | `ci.yml` (all tests), `android-apk.yml` (APK, optional model inside), `windows-desktop.yml` (desktop zip with model) |
| `00_START_HERE` | `PROJECT_STATUS.md`, `KNOWN_FLAWS.md`, `KEY_NUMBERS.md`, `NEXT_STEPS.md` |
| `Dockerfile` (root) | The single container the Render web demo runs, generated from `01_code/citypulse-IDP/deploy/single` |

## 3. Current state (15 October 2026)

| App | State | Where |
|---|---|---|
| Web demo | Version 0.1.0+1, manual deploys on Render's free tier; 12/12 smoke checks pass; it sleeps and takes ~12 s on a cold start | https://citypulse-idp.onrender.com |
| Android | First build with the question box and the on-device model (540 MiB, debug-signed). It compiled in CI but has **never been installed** | GitHub release `android-test-app` |
| Windows | Test app with the map (flutter_map + OpenFreeMap) and the model (451 MiB zip) | GitHub release `desktop-test-app` |
| Model | Qwen2.5-0.5B-Instruct LoRA fine-tune, 4-bit GGUF, 398 MB. Labels questions only. **Not adopted** | GitHub release `qa-model-run1` |

Commits on `main` that are not yet pushed: `0bee8d4` was pushed; `79a2f14` (wording "this device") is local only. The owner pushes and rebuilds.

### Recently built (useful to know before you touch them)

- **Question ladder (ADR-035, pre-registration addenda 1 to 5).** D0 is rules: a cue classifier with 19 intents, English and Tamil templates and the
  verifier. D1 is the model, which returns only a JSON label. The parser is `parseModelLabel`, which mirrors `ml/route_qa/prompts.py: parse_label`;
  a test keeps the two in step. Other D1 rules:
  - 8-second limit;
  - fallback to D0;
  - **safety guard**: if the rules see a safety question and the model does not, the D0 answer is used.

  The model never writes text that is shown.
- **Runtime.** `app/lib/src/explain/llama_question_labeler.dart` uses llamadart (llama.cpp) on CPU, greedy decoding, repeat penalty 1, 40 tokens.
  The supporting files are:
  - `qa_model_files.dart`, which finds the file: next to the exe on desktop, or through the Android channel `citypulse/qa_model`
    (`MainActivity.kt` copies the bundled asset to private storage);
  - `question_labeler_provider.dart`, where the model is off unless the build sets `CITYPULSE_QA_MODEL=true`;
  - `main_desktop.dart`, which always attaches the model.
- **Test panel.** "How this question was read" appears under an answer when a model is attached. It shows the rules' label, the model's label, the
  time taken, and which label was used.
- **Desktop map.** `app/lib/src/features/map/flutter_map_surface.dart` implements the same `MapHandle` as `maplibre_surface.dart`. Hazard
  polylines are cached per data set and per whole zoom level.
- **Fixes today.**
  - The rain poller retries after 5 s, doubling up to 1 min (`services/router_api/lib/src/rain_sync.dart`).
  - The travel-mode buttons are no longer shrunk by a `FittedBox`.
  - The wording now says "this device", not "your phone".

## 4. Commands (from `01_code/citypulse-IDP`)

```bash
(cd packages/pulse_router && dart test)
(cd packages/pulse_belief && dart test)
(cd packages/pulse_explain && dart test)      # 754 tests
(cd services/router_api && dart test)
(cd app && flutter test)                      # 221+ tests; first sync assets: bash scripts/sync_data_assets.sh
.venv/Scripts/python.exe -m pytest scripts/tests server ml -q   # 360 passed, 1 skipped
(cd app && flutter analyze lib)               # infos exist already; no errors or warnings allowed
```

A single test file is faster: `flutter test test/ui/route_question_box_test.dart`. CI runs everything on every push.

## 5. Open gaps worth working on (product polish)

1. **Android first launch with the model.** The ~400 MB model is copied on the first question, with no progress shown. It has never run on a device.
2. **Windows test app.** It has no window title, size or icon set (the defaults are `citypulse_app` and the Flutter icon). The first question waits
   for the model to load without saying so.
3. **Travel selector on narrow screens.** It shows icons only, with names as tooltips. Check that each icon has a clear accessible label and that
   the selected mode's name is visible somewhere.
4. **Web demo cold start (~12 s).** The fix is outside the code (a keep-alive or a paid tier). Ask the owner; do not add scheduled jobs.
5. **Tamil text.** It is unreviewed (F-43). Do not "improve" Tamil wording without a native speaker. Flag doubts instead.
6. **Mobile testing doc.** `01_code/citypulse-IDP/docs/ops/MOBILE_TESTING.md` should list what to record for the model build: extraction time,
   first-question time, memory, and whether the model's reading was used.

The research and data gaps (no live passability data, uncalibrated belief, placeholder constants) are in `00_START_HERE/KNOWN_FLAWS.md`. They are
not polish tasks.

## 6. Machine constraints

- **Disk.** C: has under 1 GB free. Do not download anything large, do not build Windows or Android apps locally (CI builds them), and do not
  create big files. A full disk makes `flutter test` hang silently.
- **Power and GPU.** The laptop is often on battery, and then the GTX 1650 is off. No GPU work.
- **Tools.** There is no TeX installed. Flutter 3.47.2, Dart 3.13.2, Python 3.12, Windows 11, Git Bash.
- **Flutter lock.** Only one `flutter` command at a time. A second one waits silently on the lock.
