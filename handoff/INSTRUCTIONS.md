# Instructions for the second coding agent

These rules are binding. If anything here conflicts with the root [`CLAUDE.md`](../CLAUDE.md), `CLAUDE.md` wins. If something is unclear,
**stop and ask the owner**; do not guess.

## How your work gets into the project

**You only write files.** You do not run git, push, deploy or change the project folder. The owner copies your files into a drop folder, and
another agent (the "integrator") reviews them, puts them in place, runs every test suite, fixes what breaks, and commits them to `main`.

So your delivery must be complete and unambiguous:

1. **Work against the current code.** Base every file on `main` at commit `8dcbba8` or later. If you can read the repository, read each file you
   change first. If you cannot, ask the owner to paste the current file. Never rewrite a file from memory.
2. **Deliver whole files, not fragments.** For each file you add or change, deliver the **complete file content** under its exact
   repository-relative path, for example `01_code/citypulse-IDP/app/lib/src/ui/widgets/route_question_box.dart`. Fragments like "replace the
   function X with…" are not accepted, because they cannot be applied reliably.
3. **To delete a file**, list it under "Deleted" in the manifest; do not deliver an empty file.
4. **Write a manifest**, `CHANGES.md`, with:
   - the task, in one line;
   - a table with one row per file: path, *added / changed / deleted*, and one line of why;
   - the tests you added or changed (paths), and what each checks;
   - how you checked your work. If you could run tests, give the exact last lines of the output (for example `+221: All tests passed!`). If you
     could not, say **"not run"**; never claim a result you did not see;
   - anything not verified, anything you were unsure about, and any Tamil you added (always unreviewed);
   - any new dependency you would need (you may not add one yourself; see below);
   - questions for the owner.
5. **Package it** as one folder named after the task, for example `agent2-desktop-polish/`, containing `CHANGES.md` and the files under their full
   repository paths:
   ```text
   agent2-desktop-polish/
   ├── CHANGES.md
   └── 01_code/citypulse-IDP/app/lib/main_desktop.dart
   ```
   The owner drops this folder into `handoff/inbox/`.

## Rules that protect the project

- **Never state or imply that a road is safe, dry, clear, open, passable or fine** (ADR-011). Do not use green as "safe" or show percentages as
  certainty. `app/test/core/strings_test.dart` scans every UI string; do not weaken that test, and fix your wording instead.
- **Every UI string goes in `app/lib/src/core/strings.dart`, in English and Tamil**, with a new `Msg` entry. If you add Tamil, mark it in the
  manifest as unreviewed. Do not rewrite existing Tamil.
- **Never invent numbers, results, citations or quotes.** If you did not measure something, say it is not measured.
- **Do not change** any of these unless the task says so and the owner agreed:
  - pinned data (`01_code/citypulse-IDP/data/**`);
  - pre-registrations (`PREREGISTRATION*.md`);
  - past results;
  - `docs/DECISIONS.md`;
  - `docs/CONTRACTS.md`;
  - `config/hazard_classes.yaml`;
  - the evaluation code;
  - GitHub workflows.
- **The model only labels questions.** No model output may reach the screen as text. Do not weaken the safety guard, the verifier, the 8-second
  limit or the fallback in `packages/pulse_explain/lib/src/question_labeler.dart`.
- **One router.** The Dart router is the only routing implementation. Do not port routing to another language.
- **No new dependencies, downloads, accounts or paid services.** If you think one is needed, name it in the manifest (package, source, size, why)
  and write the code without it if you can.
- **Keep existing widget keys** (for example `Key('ask-field')`, `Key('travel-selector')`). Tests find widgets by them.
- **Confidentiality.** Some of the owner's notes outside this repository are confidential. Do not read files outside this repository, and never
  copy text from outside it into what you deliver.
- **Secrets.** Never include `.env` contents, keys or tokens. The repository is public.

## Code conventions

- **Dart and Flutter:** stable channel, `dart format` style, `very_good_analysis` lints. No new analyzer errors or warnings. Doc comments on
  public members, in the same plain style as the surrounding code.
- **Tests:**
  - widget tests use `AppHarness` (`app/test/helpers/harness.dart`) or a plain `MaterialApp` as in `app/test/ui/route_question_box_test.dart`;
  - package tests use `package:test`;
  - for every behaviour you change, deliver a test that fails before your change and passes after it, where that is testable.
- **Python:** 3.11+, type hints, `pytest`.
- **Small changes.** Do not refactor unrelated code or reformat whole files.

## Definition of done

1. The task folder contains `CHANGES.md` and the complete files, under exact repository paths.
2. There is a test for each changed behaviour that can be tested.
3. The manifest says honestly what was and was not run or verified.
4. Then **stop**, and tell the owner the folder is ready. Do not start another task without the owner.

## What the integrator does (for your information)

1. Copies the folder to `handoff/inbox/`.
2. Compares each file with the current `main` and reviews it against these rules.
3. Puts the files in place and runs all suites:
   - `dart test` for the packages and `router_api`;
   - `flutter test` and `flutter analyze` for the app;
   - `pytest` where relevant.
4. Fixes what breaks, or sends questions back through the owner.
5. Commits to `main` under the owner's name. The owner decides when to push and rebuild the apps.
