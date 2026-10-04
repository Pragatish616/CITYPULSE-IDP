# Contributing to CityPulse AI

Thank you for helping. This is a research artifact: **defensible measurements matter more than a polished
demo.** A change that improves a number while weakening the measurement is a regression.

## Before you start

1. Read [`CLAUDE.md`](CLAUDE.md) (rules and the wording table in section 6) and [`PLAN.md`](PLAN.md).
2. Check [`00_START_HERE/KNOWN_FLAWS.md`](00_START_HERE/KNOWN_FLAWS.md) and the decision records in
   [`01_code/citypulse-IDP/docs/DECISIONS.md`](01_code/citypulse-IDP/docs/DECISIONS.md). Most obvious
   questions are already answered there.
3. Pick a task from `PLAN.md` (or add one first). Open an issue for anything larger than a small fix.

## Ground rules

- **Never fabricate a number, a citation or a quotation.** Every figure traces to a script output in
  `data/results/` or `07_reanalysis/`, or to a verified reference. Mark anything unverified `[UNVERIFIED]`.
- **Do not overclaim.** Use the wording table in `CLAUDE.md` section 6. In particular never write that the
  system runs on a phone, verifies explanations, is calibrated, or says a road is safe or passable.
- **Test first.** Add a test that fails before your change and passes after it. Run the existing tests and note
  the baseline.
- **Smallest change that produces evidence.** Keep the Dart router the single implementation. Python
  re-implementations are for analysis and must be validated against the Dart traces.
- **Experiments are scripts with pinned seeds** that write to a new `data/results/<YYYY-MM-DD>-<name>/`
  folder. Never edit an old result, and never change a threshold after seeing the numbers it produces.
- **Do not overwrite pinned data.** A new build goes in a new dated folder and `data/MANIFEST.md` is updated.
- **Contradicted claims get recorded**, in a new ADR and in `KNOWN_FLAWS.md`, not quietly reworded.
- **Budget is Rs 0.** If a change needs paid infrastructure, stop and ask.
- **Legal:** no Google Maps Platform data, no bulk use of `tile.openstreetmap.org`, no passive location
  inference, and no secrets in the repository (`.env` is ignored; use `.env.example`).

## Development setup

```bash
# Dart packages and the router API
(cd 01_code/citypulse-IDP/packages/pulse_router  && dart pub get && dart test)
(cd 01_code/citypulse-IDP/packages/pulse_belief  && dart pub get && dart test)
(cd 01_code/citypulse-IDP/packages/pulse_explain && dart pub get && dart test)
(cd 01_code/citypulse-IDP/services/router_api    && dart pub get && dart test)

# Flutter app
cd 01_code/citypulse-IDP/app && bash scripts/sync_data_assets.sh && flutter pub get && flutter test

# Python scripts and ingest server
cd 01_code/citypulse-IDP
python -m venv .venv && . .venv/bin/activate        # Windows: .venv\Scripts\activate
pip install -r scripts/requirements.txt -r server/requirements.txt
pytest scripts/tests server
```

Some tests need large files that are not in git (the Chennai graph and the compiled router CLI). They are
skipped, with a message, when those files are missing.

## Commits and pull requests

- Use conventional commit prefixes: `feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `chore:`; use `exp:` for
  anything that affects an experiment so results stay traceable.
- Keep a pull request to one concern. Describe what changed, which files, test results before and after, and
  what remains open. The pull request template lists the checks.
- UI strings must pass the safety-wording tests in both English and Tamil. New Tamil text should be marked as
  a draft until a native speaker has reviewed it.

## Reporting problems

Bugs and feature requests: use the issue templates. Security problems: see [SECURITY.md](SECURITY.md).
Data suggestions (a live, time-stamped passability source) are the most valuable contribution of all; there is
an issue template for them.
