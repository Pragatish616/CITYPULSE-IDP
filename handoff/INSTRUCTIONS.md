# Instructions for the second coding agent

These rules are binding. If anything here conflicts with the root [`CLAUDE.md`](../CLAUDE.md), `CLAUDE.md` wins. If something is unclear,
**stop and ask the owner**; do not guess. Another agent (the "reviewer") will review your branch, debug it and merge it into `main`.

## Git: work on your own branch, never on `main`

1. Start from an up-to-date, clean `main`:
   ```bash
   git status --short
   git switch main
   git switch -c agent2/<short-topic>
   ```
   If `git status --short` shows anything, stop and tell the owner.
2. Commit only on your branch, in small, focused commits. Use exactly this identity, and **add no `Co-Authored-By` or other trailer lines**:
   ```bash
   git -c user.name="Pragatish" -c user.email="npragatish@gmail.com" commit -m "fix: ..."
   ```
   Commit messages follow conventional commits (`feat:`, `fix:`, `docs:`, `test:`, `perf:`, `ci:`).
3. **Never** do any of these:
   - push;
   - merge;
   - rebase `main`;
   - force anything;
   - delete branches;
   - rewrite history;
   - touch the GitHub releases or workflows' release steps;
   - run `gh release`, `gh workflow run` or any deployment.

   The owner and the reviewer do these.
4. You share this folder with the reviewer. Do not switch branches while you work, and leave the tree clean (everything committed) when you hand
   off.

## Before you change code

1. Read `handoff/CONTEXT.md`, the root `CLAUDE.md` (especially section 6, the wording table), and the files you will touch.
2. Run the tests for the part you will change, and write down the result (the exact last line, for example `+221: All tests passed!`). This is
   your baseline.
3. Keep the change as small as the task allows. Do not refactor unrelated code. Do not reformat whole files.

## Rules that protect the project

- **Never state or imply that a road is safe, dry, clear, open, passable or fine** (ADR-011). Do not use green as "safe" or show percentages as
  certainty. `app/test/core/strings_test.dart` scans every UI string; do not weaken that test, and fix your wording instead.
- **Every UI string goes in `app/lib/src/core/strings.dart`, in English and Tamil.** If you add Tamil, mark it in your report as unreviewed. Do not
  rewrite existing Tamil.
- **Never invent numbers, results, citations or quotes.** A number in a document must come from a file in the repo that produced it. If you did
  not measure something, say it is not measured.
- **Do not edit** any of these unless the task says so and the owner agreed:
  - pinned data (`01_code/citypulse-IDP/data/**`);
  - pre-registrations (`PREREGISTRATION*.md`);
  - past results;
  - `docs/DECISIONS.md` (new ADRs only with the owner);
  - `docs/CONTRACTS.md`;
  - `config/hazard_classes.yaml`;
  - the evaluation code.
- **The model only labels questions.** Do not let any model output reach the screen as text. Do not weaken the safety guard, the verifier, the
  8-second limit or the fallback in `packages/pulse_explain/lib/src/question_labeler.dart`.
- **One router.** The Dart router is the only routing implementation. Do not port routing to another language.
- **No new dependencies, downloads, accounts or paid services** without the owner's explicit approval. When asking, name the item, its source and
  its size. The disk has under 1 GB free.
- **Do not build** Android or Windows apps locally. CI builds them. `flutter test`, `dart test`, `flutter analyze` and `dart analyze` are fine.
- **Confidentiality.** Some of the owner's notes outside this repository are confidential. Do not read files outside this repository folder, and
  never copy text from outside it into the repo, commits or messages.
- **Secrets.** Never commit `.env`, keys or tokens. The repo is public.

## Practical tips for this machine

- Write files with your file-writing tool, not shell heredocs. Heredocs here mangle backslashes, for example `\t` in LaTeX or `\n` in Dart.
- Run one `flutter` command at a time; a second one waits silently on the lock. If a test run prints nothing for minutes, check free disk space
  (`df -h /c`).
- Files use CRLF line endings on checkout. Edit them in place; do not convert whole files.
- Widget tests use `AppHarness` (`app/test/helpers/harness.dart`). Keys such as `Key('ask-field')` are what tests find widgets by, so keep the
  existing keys.

## Definition of done

1. A test that fails before your change and passes after it, for each behaviour you changed, where it is testable.
2. All suites for the parts you touched pass. Before handing off, also run the full `flutter test` for `app/` and `dart test` for any package you
   touched.
3. `flutter analyze` / `dart analyze` shows no new errors or warnings in the files you touched.
4. Everything is committed on your branch, and the tree is clean.
5. You wrote `handoff/REPORT_<your-branch-name-with-dashes>.md` and committed it. It must contain:
   - the task, in one line;
   - the branch name and the list of commits (`git log --oneline main..HEAD`);
   - the files changed, and why;
   - the baseline and the final test results (the exact last lines);
   - anything not verified, anything you were unsure about, and any Tamil you added;
   - any question for the owner.
6. Then **stop**. Do not start another task without the owner.
