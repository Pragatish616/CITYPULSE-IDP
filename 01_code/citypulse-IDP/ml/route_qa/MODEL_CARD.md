# CityPulse route-question model (run1) — model card

**Status: a test model, not adopted.** It is used only in measurement builds (the desktop test app and an APK built with the model). The normal app does not load it. Adoption needs the sealed test set, blind ratings, the faithfulness audit and the phone ceilings (ADR-035, `data/qa/2026-10-13/PREREGISTRATION_QA.md`).

## What it is

A LoRA fine-tune of **Qwen2.5-0.5B-Instruct** (Alibaba Cloud / Qwen team, **Apache-2.0**, revision `7ae557604adf67be50417f59c2c2f167def9a775`), merged into the base weights and converted to GGUF. The Apache-2.0 licence text for the base model is in `data/models/qwen2.5-0.5b-instruct/LICENSE` and applies to these weights too; this model was changed from the original by the fine-tuning described here.

| File | Size | Use |
|---|---|---|
| `route_qa_run1_q4_k_m.gguf` | 397,807,520 bytes | the build for the app (4-bit, `llama.cpp` b11630) |
| `route_qa_run1_q8_0.gguf` | 531,067,808 bytes | 8-bit, same checks |

## What it does

It does **one job**: it reads a traveller's question about a route (English or Tamil) and returns a JSON label, one of 19 intents (for example `time_distance`, `why_route`, `is_safe`) and an optional second intent. The app's rule-based answerer then writes the answer from the route's own data, and the symbolic verifier checks it. The model never sees the route's facts and never writes text the traveller reads. A question that asks whether a road is safe, dry or open is always refused with the risk shown, whatever the model says (ADR-011); the model can add that caution but cannot remove it.

## Training

LoRA r16, alpha 32, dropout 0.05, on all attention and MLP projections; 6,000 labelling and 2,400 answer-writing examples, 1 epoch, 525 steps, seed 20261014, on one GTX 1650. The data is synthetic: questions written from templates and noise, answers from the app's own verified templates; no scraped or third-party text, and none of the licensed flood datasets. One adapter was trained for two tasks; only the labelling task is used in the app. Tamil questions are included; Tamil answers are not, and the Tamil wording is unreviewed by a native speaker (KNOWN_FLAWS F-43).

## What was measured (and what it does not show)

On 300 validation questions that share a question bank with the training questions (so these numbers overstate how it handles unseen phrasings):

| Build / runtime | Intent accuracy | Tamil |
|---|---|---|
| unmerged adapter, PyTorch fp16 (eval) | 0.9967 | 0.9924 |
| GGUF f16, llama.cpp server | 0.9967 | 0.9924 |
| GGUF Q8_0, llama.cpp server | 0.9967 | 0.9924 |
| GGUF Q4_K_M, llama.cpp server | 0.9867 | 0.9848 |
| GGUF Q4_K_M, the app's own labeler class (llamadart), laptop CPU | 0.9900 | 0.9848 |

The untouched base model scores 0 on the same task. The pre-registered bar for a quantised build was at least 0.977. Speed on a laptop CPU: about 0.57 s per question (median). **Nothing is measured on a phone yet.** The same run's answer-writing task missed its pre-registered bar (88.3% against 90%), which is why the model is used for labelling only.

## Limits

- Not tested on questions written by people who did not write the training data (the sealed test set does not exist yet).
- Not tested on a phone: memory, speed, battery and heat are unmeasured.
- Small model: it can mislabel; the ladder falls back to the rule-based answer when it gives nothing usable, and the safety guard keeps every safety question refused.
- CityPulse never states that a road is safe or passable (ADR-011); this model does not change that.
