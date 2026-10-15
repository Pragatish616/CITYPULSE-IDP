# Prompts to give the second agent

Paste **Prompt 0** first, then one task prompt (A to F). Give one task at a time. Each task ends with a folder of complete files plus a
`CHANGES.md`. Copy that folder into `handoff/inbox/`, then tell the integrator agent: *"agent 2's files for <task> are in
handoff/inbox/<folder>, integrate them"*.

If the second agent cannot read this repository, attach the three files it needs to read first (`handoff/CONTEXT.md`,
`handoff/INSTRUCTIONS.md`, root `CLAUDE.md`), plus the current version of every file the task names.

---

## Prompt 0: start (paste first)

> You are joining the CityPulse AI project as a second coding agent. You will only write code files; another agent integrates, tests and commits
> them. Before doing anything else, read these three files completely: `handoff/CONTEXT.md`, `handoff/INSTRUCTIONS.md` and the root `CLAUDE.md`.
> The instructions are binding. In particular:
> - deliver **complete files** under their exact repository paths, plus a `CHANGES.md` manifest, in one folder named after the task;
> - run no git commands and make no deployments;
> - never say a road is safe;
> - never invent numbers or test results ("not run" is fine; a made-up "passed" is not);
> - add no new dependencies;
> - keep existing widget keys;
> - every UI string goes in English and Tamil in `strings.dart`;
> - do not read files outside this repository.
>
> After reading, reply with a five-line summary of the project and the rules you must follow. Then wait for a task.

---

## Task A: Android first launch with the model

> Task: the Android build carries a ~400 MB model that `MainActivity.kt` copies to private storage the first time a question is asked. Today the
> traveller sees only the generic working indicator while that happens. Make the first launch clear and safe:
> 1. Show a one-time message while the model is being prepared, in English and Tamil in `strings.dart`, for example "Preparing the on-device
>    question model (one time)". Do not state a time; nothing has been measured.
> 2. If the model cannot be found or loaded, the box must still answer with the rule-based answerer, as it does now. Add a small, quiet line in the
>    test panel saying the model is unavailable, using `LlamaQuestionLabeler.status`.
> 3. Write widget tests with fake labelers (no real model, no device).
>
> Files you will likely touch:
> - `app/lib/src/ui/widgets/route_question_box.dart`
> - `app/lib/src/explain/llama_question_labeler.dart`
> - `app/lib/src/core/strings.dart`
> - `app/test/ui/route_question_box_test.dart`
>
> Do not change the 8-second limit, the safety guard or the Kotlin copy logic. If you find a real bug there, describe it in `CHANGES.md` instead.
> Folder name: `agent2-android-first-run`.

## Task B: Windows test app polish

> Task: polish the Windows desktop test app (`app/lib/main_desktop.dart`, `app/windows/runner/`).
> 1. Set the window title to "CityPulse - desktop test app" and a sensible default size (for example 1280x800) in the Windows runner
>    (`app/windows/runner/main.cpp`).
> 2. While the model loads on the first question, the indicator text must say that the model is loading, not just "working". Use new strings in
>    both languages.
> 3. Make the "How this question was read" panel easy to find on desktop: open it by default in the desktop app only, through a setting passed
>    from `main_desktop.dart`. Do not change Android or web behaviour.
>
> Folder name: `agent2-desktop-polish`.

## Task C: accessibility pass on the planner and the question box

> Task: an accessibility pass on the planner (`app/lib/src/features/map/map_screen.dart`) and the question box
> (`app/lib/src/ui/widgets/route_question_box.dart`).
> - Every icon-only control (travel-mode icons on narrow screens, swap, clear, erase, copy, report) has a meaningful semantic label in both languages.
> - The selected travel mode's name is visible on narrow screens, not only in a tooltip.
> - Tab order on web and desktop goes Start, Where to, travel mode, then route.
>
> Deliver widget tests that check the semantics labels. Do not break `app/test/features/layout_matrix_test.dart` (every size and text scale must
> lay out without overflow). Folder name: `agent2-a11y`.

## Task D: mobile testing checklist for the model build

> Task: update `01_code/citypulse-IDP/docs/ops/MOBILE_TESTING.md` (deliver the whole file) with a checklist for the Android build that carries the
> model. Record:
> - install size;
> - time to prepare the model on first use;
> - time to the first answer and to later answers;
> - app memory with the model loaded;
> - whether the test panel shows the model's reading being used;
> - behaviour in airplane mode;
> - battery and warmth over 10 questions.
>
> Quote the phone ceilings from `data/qa/2026-10-13/PREREGISTRATION_QA.md` addendum 3; do not invent new ones. Leave the result cells empty for the
> team to fill. Folder name: `agent2-mobile-checklist`.

## Task E: web demo first-impression polish (no infrastructure changes)

> Task: improve what a first-time visitor sees on the web demo, in the Flutter app only.
> - While the free host wakes, the first route or search can take several seconds. Show a clear "waking the server" state instead of a silent
>   wait, in both languages.
> - Make sure the Flood-event banner's text says plainly when the rain reading has not arrived yet (the event-state `source` is `fallback`).
>
> No keep-alive jobs, workflows or new services. Use the existing test harness and fakes. Folder name: `agent2-web-first-impression`.

## Task F: free choice from the gap list (only if the owner says so)

> Task: pick **one** item from `handoff/CONTEXT.md` section 5 that is not already assigned. Explain in two lines why you chose it, then deliver it
> as for any task. Folder name: `agent2-<topic>`.

---

## Prompt for the end of any task (if the agent forgets)

> Stop adding features. Put every file you added or changed, **complete**, under its exact repository path in your task folder. Write `CHANGES.md`
> as described in `handoff/INSTRUCTIONS.md`: say honestly which tests you ran (exact output) and which you did not. Tell me the folder is ready, and
> stop.
