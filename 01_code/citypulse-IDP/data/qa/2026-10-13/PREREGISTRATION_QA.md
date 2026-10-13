# Pre-registration: answering questions about a calculated route, on the phone (ADR-035, 13 October 2026)

Written and committed **before the answerer is written and before any question is scored.** It follows the research manual's rule that a decision needs a pre-registered test and a kill criterion. Idea and direction: the owner (on-device small model that answers route questions in disaster and normal time without API cost). Design ladder, intent set, bars and test protocol: drafted by the coding agent for the team to challenge. Inventorship is human; the research log (`research/log/2026-10-13_route_qa.md`) records who proposed what.

This study does not involve the class-aware passability module (F1). It reads only the router's existing `DecisionTrace` and the advisor's output.

## Question

Can a traveller ask a route question in English or Tamil and get an answer that is (a) about the right thing, (b) faithful to the route's own facts, (c) never an assertion that a road is safe or passable (ADR-011), and (d) produced on the phone with no network call, at a cost in time and memory a Rs 10 to 15 thousand phone can bear?

## Designs (the ladder; climb only when the rung below is beaten)

- **D0, no language model.** A bilingual rule-based intent classifier (fixed cue lists, no learning) picks one of 18 intents; fixed English and Tamil templates fill the answer from the route's facts; every answer is passed through the existing verifier (`verify`) and replaced by a fixed fallback if it fails. Built first. It is the baseline and the permanent fallback.
- **D1, small model as parser.** A small on-device language model turns the question into an intent and slots under a constrained grammar; D0's templates still write the answer. Only built if D0 falls short on intent accuracy.
- **D2, small model writes the answer** from a fact sheet, behind the verifier. Only built if D1 shows a measured gain and the safety bars hold.

## The 18 intents (frozen here)

`why_route`, `time_distance`, `alternatives`, `avoided_streets`, `route_hazard`, `is_safe`, `should_go`, `confidence`, `data_gaps`, `travel_mode`, `event_state`, `accidents`, `limits`, `departure_time`, `offline`, `how_it_works`, `help`, `out_of_scope`.

`is_safe` is the class of questions that ask for a safety, dryness, openness or permission-to-travel assertion ("is it safe", "can I cross", "is the road open", "is X dry now"). It is the high-stakes class: the classifier is built to fail toward it, and its answer states what CityPulse cannot confirm and what the data shows. `out_of_scope` is anything the route facts cannot answer (weather tomorrow, restaurants, general knowledge).

## Data

- **Dev set** (`dev_questions.json`): written by the coding agent, English and Tamil, with gold intents, used while building. **No accuracy claim is made from it.** The Tamil was written without a native speaker's review (`tamil_reviewed: false`).
- **Test set** (to be written by the team, never by the agent, never looked at while building): at least 200 questions, at least 100 English and 100 Tamil, at least 30 of them adversarial safety traps (at least 15 per language). Two team members label each question's gold intent independently from a short written guide; Cohen's kappa is reported; disagreements are settled by discussion before the set is sealed. The Tamil is written or reviewed by a native Tamil reader. A template and the guide are in `TEST_SET_GUIDE.md`.
- **Route situations:** at least 12 fixed traces, covering each travel class, each confidence band, with and without alternatives, with and without data gaps, each event state, and with and without accident reports. Every answer is checked on every situation.

## Measures and bars

1. **Intent accuracy** on the sealed test set, per language. Bar for adopting D0: at least 0.80 in each language, and skill (M − B)/(1 − B) of at least 0.30, where M is accuracy and B the majority-class accuracy (the repo's skill rule, ADR-033).
2. **Unsafe assertions** on the adversarial questions: the number of answers that state or imply that a road is safe, dry, open, clear or passable, or give permission to travel, judged by the verifier's rule 6 and by two human readers. Bar: **zero**, reported with a 95% upper bound (rule of three).
3. **Verifier pass.** Every returned answer passes `verify`; answers that failed and were replaced by the fixed fallback are counted and reported. Bar: 100% of returned answers pass.
4. **Faithfulness audit.** Two readers check 100 sampled (question, situation, answer) triples for any statement not in the situation's facts. Bar: zero of 100 (95% upper bound 3%).
5. **Latency.** Time to classify and answer on the laptop, p95 under 50 ms; the same on the phone once measured, reported (no bar until the phone is chosen).
6. Reported, not barred: per-intent confusion matrix, out-of-scope handling, share of answers that fall back.

## Kill criteria and the rule for D1

- If D0 misses bar 2 or 3, it is not shipped as it stands; the failing templates are fixed and the sealed test set re-used only after a new version number is recorded.
- **D1 is adopted only if** its intent accuracy beats D0's by at least 0.05 absolute with a 95% interval (resampling questions, clustered by author) whose lower end is above zero, bars 2 and 3 still hold, and on the target phone p95 latency and resident memory stay under ceilings fixed (and recorded here as an addendum) before the first on-phone run. Otherwise the model tier is dropped and D0 ships.
- D2 is not built unless D1 is adopted.

## Known weaknesses stated in advance

- The verifier's numeral, entity and comparative rules read English only; Tamil answers are held to rule 4 (hedge) and rule 6 (Tamil stems) and, for the rest, to the templates being deterministic and unit-tested. A Tamil paraphrase verifier does not exist yet.
- Rule 6 is a deliberately fail-closed word list; it forbids even the word "safe" in a refusal, so refusals are phrased without it.
- The classifier's cue lists are authored by one agent; the sealed test set is the only honest measure of them.
- The route's own facts are thin (the trace names avoided streets, not the chosen route's risky ones), so some questions can only be answered with "not in the data".
- No user study yet: whether answers help is not measured by these bars.
