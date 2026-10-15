# Prompts to give the second agent

Paste **Prompt 0** first, then one task prompt (A to F). Give one task at a time; each ends with a report and a stop. When a task is finished,
tell the reviewer agent: *"agent 2 finished on branch `agent2/<topic>`, review and merge it"*.

---

## Prompt 0: start (paste first)

> You are joining the CityPulse AI project as a second coding agent. Before doing anything else, read these three files completely:
> `handoff/CONTEXT.md`, `handoff/INSTRUCTIONS.md` and the root `CLAUDE.md`. The instructions are binding. In particular:
> - work only on your own branch `agent2/<topic>`, created from a clean `main`;
> - commit as `git -c user.name="Pragatish" -c user.email="npragatish@gmail.com"` with no co-author lines;
> - never push, merge or deploy;
> - never say a road is safe;
> - never invent numbers;
> - add no new dependencies or downloads without asking;
> - do not read files outside this repository.
>
> After reading, reply with:
> - a five-line summary of the project;
> - the rules you must follow;
> - the output of `git status --short` and `git log --oneline -3`.
>
> Then wait for a task.

---

## Task A: Android first launch with the model

> Task: the Android build carries a ~400 MB model that `MainActivity.kt` copies to private storage the first time a question is asked. Today the
> traveller sees only the generic working indicator while that happens. Make the first launch clear and safe:
> 1. Show a one-time message while the model is being prepared, in English and Tamil in `strings.dart`, for example "Preparing the on-device
>    question model (one time, about a minute)". Do not state a time you have not measured; prefer wording without a number.
> 2. If the model cannot be found or loaded, the box must still answer with the rule-based answerer, as it does now. Add a small, quiet line in the
>    test panel saying the model is unavailable, using `LlamaQuestionLabeler.status`.
> 3. Test it with fakes in `app/test` (no real model, no device).
>
> Do not change the 8-second limit, the safety guard or the Kotlin copy logic unless you find a real bug; if you do, describe it in the report.
> Branch: `agent2/android-first-run`.

## Task B: Windows test app polish

> Task: polish the Windows desktop test app (`app/lib/main_desktop.dart`, `app/windows/runner/`).
> 1. Set the window title to "CityPulse - desktop test app" and a sensible default size (for example 1280x800) in the Windows runner.
> 2. While the model loads on the first question, the indicator text must say that the model is loading, not just "working".
> 3. Make sure the "How this question was read" panel is easy to find on desktop (for example, open by default in the desktop app only).
>
> Do not build the Windows app locally (CI does). Keep changes out of the Android and web paths, and run `flutter test` for the app.
> Branch: `agent2/desktop-polish`.

## Task C: accessibility pass on the planner and the question box

> Task: an accessibility pass on the planner (`app/lib/src/features/map/map_screen.dart`) and the question box
> (`app/lib/src/ui/widgets/route_question_box.dart`).
> - Every icon-only control (travel-mode icons on narrow screens, swap, clear, erase, copy, report) has a meaningful semantic label in both languages.
> - The selected travel mode's name is visible on narrow screens, not only in a tooltip.
> - Tab order on web and desktop goes Start, Where to, travel mode, then route.
>
> Add widget tests that check the semantics labels, and keep `test/features/layout_matrix_test.dart` passing at every size and text scale.
> Branch: `agent2/a11y`.

## Task D: mobile testing checklist for the model build

> Task: update `01_code/citypulse-IDP/docs/ops/MOBILE_TESTING.md` with a checklist for the Android build that carries the model. Record:
> - install size;
> - time to prepare the model on first use;
> - time to the first answer and to later answers;
> - app memory with the model loaded;
> - whether the test panel shows the model's reading being used;
> - behaviour in airplane mode;
> - battery and warmth over 10 questions.
>
> Use the phone ceilings already fixed in `data/qa/2026-10-13/PREREGISTRATION_QA.md` addendum 3, quoting them, not inventing new ones. Leave the
> result cells empty for the team to fill. Do not touch the pre-registration itself. Branch: `agent2/mobile-checklist`.

## Task E: web demo first-impression polish (no infrastructure changes)

> Task: improve what a first-time visitor sees on the web demo, in the Flutter app only.
> - While the free host wakes, the first route or search can take several seconds. Show a clear "waking the server" state instead of a silent
>   wait, in both languages.
> - Make sure the Flood-event banner's text matches the event-state source: say plainly when the rain reading has not arrived yet.
>
> Do not add keep-alive jobs, scheduled workflows or new services; those need the owner. Test with the existing harness and fakes.
> Branch: `agent2/web-first-impression`.

## Task F: free choice from the gap list (only if the owner says so)

> Task: pick **one** item from `handoff/CONTEXT.md` section 5 that is not already assigned. Explain in two lines why you chose it, then follow the
> instructions as for any task. Branch: `agent2/<topic>`.

---

## Prompt for the end of any task (if the agent forgets)

> Stop adding features. Run the full test suites for everything you touched and `flutter analyze` on the changed files. Commit everything on your
> branch. Write `handoff/REPORT_<branch>.md` as described in `handoff/INSTRUCTIONS.md` ("Definition of done"), commit it, show me
> `git log --oneline main..HEAD` and `git status --short`, and stop.
