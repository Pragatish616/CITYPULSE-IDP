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

## Addendum 1 (13 October 2026), written before the sealed test set exists and before any model is trained

The owner asked for the model track to run in parallel with better D0 answers. Nothing about the adoption rules above is relaxed.

1. **The intent set grows from 18 to 19.** New: `summary` (a short briefing on the route: "tell me about this route", "give me the picture"). The test-set guide is updated. This is allowed now because the test set has not been written.
2. **D0 version 2** adds: a two-part question gets one reply covering both parts (up to two intents); a headline (the first sentence); two or three follow-up questions offered after each answer; answers that combine more of the route's facts (for example the other route's time difference together with the reason it was left out); and several phrasings (a style number) for common sentences. D0's bars (1 to 4) are unchanged and apply to version 2.
3. **Training the model (D1 and D2) is pre-committed as follows.**
   - **Data:** generated by a seeded program from random route situations; the dev questions may be used, the sealed test text never; train and validation are split by situation, not by row. **Every training answer must pass `verify`.** Tamil answers are not used as training targets until a native Tamil reader has approved a Tamil answer set; Tamil questions may be used to teach understanding (intent labels).
   - **Run time:** any model-written text that fails `verify` is replaced by D0's answer and counted.
   - **D1 (understanding)** is judged by the rule above (gain of at least 0.05 absolute on the sealed test, interval above zero, safety bars intact, phone ceilings).
   - **D2 (writing)** is adopted only if all of: (a) in blind pairwise ratings by at least 3 team members over at least 100 question-and-situation pairs, D2 beats D0 version 2 in more than 60% of the non-tied pairs with a 95% interval above 50%; (b) a faithfulness audit of 200 sampled D2 answers finds zero unsupported statements (95% upper bound 1.5%); (c) zero unsafe assertions on the adversarial set; (d) the phone ceilings hold. Otherwise D0 version 2 ships.
4. Base model, training settings and the phone ceilings are fixed in a further addendum before the first training run.

## Addendum 2 (14 October 2026), written after the base model was downloaded and before any training step

The owner approved the download and the start of fine-tuning ("download the base model and start fine tuning"). This fixes what was left open in addendum 1, item 4, except the phone ceilings (the phone is still not named).

- **Base model:** `Qwen/Qwen2.5-0.5B-Instruct`, revision `7ae557604adf67be50417f59c2c2f167def9a775`, Apache-2.0, not gated, 988,097,824 bytes of weights (checksums in `data/models/qwen2.5-0.5b-instruct/fetch_log.json`). Chosen over Gemma 3 270M because the latter needs a licence click-through and login that the owner would have to do, and over larger models because of this laptop's 7.4 GB of RAM and the phone target. Its Tamil is weak: it is used for understanding Tamil questions only.
- **Method:** LoRA (rank 16, alpha 32, dropout 0.05, on all attention and MLP projections), one adapter for both tasks (U: question to label; W: facts, question and intents to answer), loss on the reply only, fp32 on CPU, AdamW, learning rate 2e-4 with 5% warm-up and cosine decay, effective batch 16 (one example per step, 16 accumulated), maximum 768 tokens, seed 20261014; data seed 20261013. Prompts are in `ml/route_qa/prompts.py`; the writing prompt gives the model the gold intents so that writing is measured apart from understanding.
- **Runs:** a pilot (200 U and 100 W examples, one epoch) only to measure speed and catch bugs. Then **one** full run whose size is chosen from the pilot's speed alone and written into the run's `args.json`. **No tuning on the validation set**: the settings above are not changed after seeing validation results. A second run is allowed only to fix a bug, and then both runs are reported.
- **Reference:** the untouched base model is evaluated the same way (`--base-only`), so that any gain is the fine-tuning's.
- **Automatic checks** (`ml/route_qa/eval_model.py`): label accuracy on validation questions from unseen situations next to the rule-based classifier's agreement on the same rows; for writing, the Dart verifier's pass rate, the refusal rate on safety questions, the hedge rate under low or stale confidence, and diversity. **Caveat fixed here:** the validation questions come from the same question bank as the training questions (with noise and joins), so these figures overstate how the model handles questions it has never seen. Only the sealed test set measures that.
- **Not decided by these checks:** adoption. It needs the blind ratings, the faithfulness audit and the sealed test set, as in addendum 1.

## Addendum 3 (14 October 2026), written before any measurement on a phone

The owner's phone has **8 GB of RAM** (the phone model and processor are not yet recorded). The ceilings left open in addendum 1 are fixed here, for the 4-bit (Q4_K_M, about 491 MB) build of the fine-tuned Qwen2.5-0.5B-Instruct, measured on that phone by a person with a stopwatch and the system memory screen, three runs each, worst of the three reported:

- **Memory:** the app's resident memory with the model loaded stays under **1.2 GB**, and the app is not killed in the background during a 10-minute session of 10 questions.
- **Speed:** time to the first word of a model answer under **4 s**, and the whole answer (about 100 words) under **12 s**. Phone speed depends on the processor, and these numbers are a first guess that the first measurement may show to be wrong; if they are changed, the change and the reason are written here before the next run.
- **What the user sees regardless:** the rule-based answer (D0 version 2) is shown immediately; the model's answer replaces it only if it passes the verifier and arrives within **8 s**. A slow phone therefore costs wording, never speed or safety.
- **Battery and heat:** reported (percent used over the 10 questions, whether the phone warms up), no bar.
- **If the ceilings are missed,** the model tier is not shipped in the app (D0 version 2 stays), whatever the ratings say.

## Addendum 4 (15 October 2026), written before the full training run

The owner freed disk space, and the GPU build of PyTorch (2.14.1, CUDA 12.6) was installed in its own environment. The GTX 1650 (4 GB) trains at about 108 tokens a second in a smoke test, against 13 on the CPU. This fixes the run, from that speed alone:

- **Precision on the GPU:** base weights in fp16 (so that a 4 GB card is enough), LoRA weights in fp32, a gradient scaler. Everything else in addendum 2 is unchanged (rank 16, alpha 32, learning rate 2e-4, effective batch 16, seed 20261014).
- **Size:** **6,000 labelling examples and 2,400 answer-writing examples, one epoch**, drawn by the seed from the training file; about 1.0 million tokens, about 2.6 hours. (The 4,000 and 1,600 in the GPU guide were a first plan for slower hardware; they are replaced by these before any run.)
- **Run name `run1`.** One run. No tuning on the validation set. A second run only to fix a bug, and then both are reported.
- **After the run:** the automatic checks of addendum 2 on 300 validation questions and 60 validation answers, and the untouched base model as the reference on the same rows. Results are written up whatever they show.


## Addendum 5 (15 October 2026), written before any export, conversion or phone wiring was run

The owner asked for the export and the app wiring of the trained adapter (`run1`). Run1 met the labelling criteria and narrowly missed the answer-writing criterion (ADR-035 addendum 5), so this work is **D1 only**: the model labels the question, D0's templates write the answer, the verifier is unchanged. Nothing here is adoption; the rule for adopting D1 (addendum 1: a gain of at least 0.05 absolute on the sealed test set with the interval above zero, safety bars, phone ceilings) is unchanged and still unmet.

**How the model sits in the app (fixed now):**
- D0 always runs first and is the fallback. The model's reply is read by the same strict rule as `ml/route_qa/prompts.py: parse_label` (first `{...}`, valid JSON, intent from the 19 known, secondary known and different from the intent, otherwise no label). No valid label, an error, or no reply within **8 s** means the D0 answer, silently.
- **Safety guard:** if the rule-based classifier marks the question as a safety question (as the main or the second part) and the model's label does not, the D0 answer is used. The model can add caution, never remove it. The refusal text and the verifier are unchanged, so no model reply can put a verdict on screen.
- **Off by default.** A normal build never loads a model. A measurement build turns it on with a compile-time flag, and only a model file the owner has put on the phone is used. Nothing is downloaded by the app.
- Nothing typed is stored or sent. The reply is read and dropped.

**Export checks (fixed now, run once, reported whatever they show):**
1. **Merge check.** The adapter merged into the fp16 base model must give the same label (intent and secondary) as the unmerged adapter on at least **99%** of the same 300 validation questions that run1 was evaluated on (seed 20261014).
2. **Quantisation check.** A 4-bit or 8-bit build, run through its own runtime, must keep intent accuracy on those 300 questions within **2 points** of the unmerged adapter's 0.9967 (that is, at least 0.977). The order tried is fixed: Q8_0 first, then Q4_K_M. If Q4_K_M misses and Q8_0 passes, Q8_0 is the build measured on the phone and its larger size (about 530 MB) is checked against the 1.2 GB ceiling. If both miss, the result is reported and nothing is shipped.
3. These checks say the export is faithful to the adapter. They say nothing new about how well the model understands questions it has not seen.

**Format and runtime.** The target format is GGUF (addendum 3 already names Q4_K_M). The phone runtime is chosen separately and recorded when chosen; the app side is written against a small `QuestionLabeler` interface so that the choice changes one class.
