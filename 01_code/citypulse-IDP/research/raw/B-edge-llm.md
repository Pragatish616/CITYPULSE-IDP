# Strand B — Feasibility of On-Device / Edge LLM Inference for Offline Routing Explanations

**Research Agent B · CityPulse AI · 2026-09-11**
**Scope:** Can a phone generate the "why this route" explanation locally, with zero connectivity, on the kind of Android hardware CityPulse's Chennai pilot users actually own — and *should* it?

**Bottom line up front:** On-device LLM inference is *technically* feasible in 2026 and the tooling has matured enough for a student team to ship it. But for the specific output the brief describes — a one-sentence, fully-determined explanation whose every content word comes from a structured routing decision — an LLM is the **wrong primary generator**. It is 4–6 orders of magnitude slower, costs 0.7–2 GB of resident RAM, and introduces a non-zero probability of misstating a safety-critical fact, in exchange for paraphrase variety the user did not ask for. The defensible design — and, I will argue, the *more* publishable one — is a deterministic NLG core with a verified, optional on-device LLM rewrite layer and a hard template fallback.

---

## 0. Reading guide: source quality

I have graded every source. Do not cite a 🟡 or 🟠 source in the paper as if it were 🟢.

| Grade | Meaning |
|---|---|
| 🟢 | Peer-reviewed paper, or first-party vendor documentation / model card / repo |
| 🟡 | arXiv preprint, not yet peer-reviewed (several are 2026 preprints — treat numbers as indicative) |
| 🟠 | Independent blog with stated measurement methodology — the *only* source I found with real mid-range Android numbers, so it is load-bearing and that is a weakness |

An explicit caveat that runs through this whole report: **essentially nobody publishes on-device LLM benchmarks for mid-range phones.** Google benchmarks on Galaxy S24/S25/S26 Ultra. Meta benchmarks on OnePlus 12 and Galaxy S22/S24. Academic papers benchmark on Snapdragon 8 Gen 3 and Dimensity 9300. The mid-range extrapolations in §4 are *mine*, derived from cross-device ratios in the one paper that tested a mid-tier SoC, and they carry roughly ±50% uncertainty. The project should treat "measure this ourselves on a real ₹15,000 phone" as a *research contribution*, not a chore — because the data genuinely does not exist.

---

## 1. Candidate small language models (as of September 2026)

### 1.1 Comparison table

| Model | Params (total / effective) | Licence | Int4 on-disk | Measured peak RAM | Why it matters here |
|---|---|---|---|---|---|
| **Gemma 3 270M (IT)** | 270M (170M embed / 100M transformer) | Gemma Terms of Use (not OSI) | ~240 MB (INT4 QAT) | well under 500 MB | Google's own framing: "unstructured to structured text processing", built for **task-specific fine-tuning**. INT4 used **0.75% of a Pixel 9 Pro battery for 25 conversations** 🟢 |
| **Gemma 3 1B IT** | 1B | Gemma Terms of Use | **529 MB** (dynamic_int4 QAT) | **982–1,205 MB** | Best-documented on-device model in existence. Full published benchmark grid (§4.1) 🟢 |
| **Gemma 3n E2B** | 5B raw / **1.91B effective** | Gemma Terms of Use | ~1.4–2 GB | ~2 GB target | MatFormer + Per-Layer Embedding caching keeps PLE params out of model memory. Multimodal (text/vision/audio), 32K ctx 🟢 |
| **Gemma 3n E4B** | ~8B raw / ~4B effective | Gemma Terms of Use | ~4.2 GB (.litertlm) | ~3–4 GB | Too big for mid-range Android. Rule out |
| **Gemma 4 E2B / E2B-it** | 5.1B total / **2.3B effective** | **Apache 2.0** ✅ | ~1.5 GB quantized (vendor claim) | **1,733 MB CPU / 676 MB GPU** on S26 Ultra | Released 2026-04-06 (family) / model card 2026-07-02. First Gemma under Apache 2.0 — removes the licence problem. 128K ctx, 512-token sliding window. MMLU-Pro 60.0 🟢 |
| **Gemma 4 E4B** | ~4B effective | Apache 2.0 | ~2.5–3 GB | >3 GB | Flagship-only |
| **Llama 3.2 1B** | 1.24B | Llama 3.2 Community Licence (⚠️ not OSI: 700M-MAU clause, "Built with Llama" attribution, AUP, regional carve-outs) | 1,083 MB (SpinQuant) | **1,921 MB** (ExecuTorch, OnePlus 12) | 50.2 tok/s decode / 260.5 prefill on a *flagship*. Note RAM is 2× Gemma 3 1B for similar capability 🟢 |
| **Llama 3.2 3B** | 3.2B | Llama 3.2 Community Licence | 2,435 MB (SpinQuant) | **3,726 MB** | Rule out for mid-range |
| **Qwen3 0.6B** | 0.6B total / 0.44B non-embed | **Apache 2.0** ✅ | ~400 MB | ~1.5–2.0 GB observed | 32K ctx. Cleanest licence + smallest credible instruct model. Measured 3.3–4.9 tok/s decode on mid-range 🟠 |
| **Qwen3 1.7B / 4B** | 1.7B / 4B | Apache 2.0 | ~1.0 / ~2.4 GB | ~2 / ~3.5 GB | Qwen3-4B has the **lowest hallucination rate of any small model on the Vectara leaderboard at 5.7%** — best-in-class grounding, but too heavy for mid-range 🟢 |
| **Phi-4-mini** | 3.8B | **MIT** ✅ | ~2.3 GB | ~3.5 GB | Best licence in the set; too heavy. Supported by LiteRT-LM and flutter_gemma |
| **SmolLM3 3B** | 3B | Apache 2.0 | ~1.8 GB | ~3 GB | HuggingFace; fully open training recipe (good for an academic paper); too heavy for mid-range |
| **LFM2 / LFM2.5** | 350M – 2.6B | LFM Open Licence (restricted above a revenue threshold) | 0.25–1.6 GB | — | Liquid AI, explicitly edge-designed hybrid-conv architecture. 2026 entrant; least mature tooling |
| **MobileLLM-Pro / -Flash / -R1.5** (Meta) | 140M – 1.4B | FAIR NC licence in most variants (⚠️ **non-commercial** — academic OK, productisation not) | small | — | 2025–26 entrants, research-grade tooling |
| **Apple on-device foundation model** | ~3B, **2 bits/weight QAT** (4-bit embeddings, 8-bit KV) | Apple platform API — not downloadable, not portable | n/a | n/a | Ships free with iOS; has first-class **guided generation / constrained decoding**. iOS-only, so irrelevant to a Chennai Android pilot but a useful comparison point in the paper |

### 1.2 Licence assessment for a credited university project

- **Apache 2.0 (Gemma 4, Qwen3, SmolLM3):** unambiguous. Use these.
- **Gemma Terms of Use (Gemma 3 / 3n / 270M):** permits "responsible commercial use" but is a bespoke licence with a Prohibited Use Policy that Google can update, and it propagates to derivatives (fine-tunes inherit it — this is the point the HuggingFace community repeatedly litigates). Fine for an academic demo; a footnote-worthy risk for the "civic infrastructure" positioning.
- **Llama 3.2 Community Licence:** the 700M-MAU clause is irrelevant at student scale, but the mandatory "Built with Llama" attribution and naming requirement is a real deliverable, and the licence is not OSI-approved. There is no capability reason to accept this friction when Qwen3 and Gemma 4 are Apache 2.0.
- **Meta MobileLLM family:** several variants are FAIR non-commercial. Academic use fine, but it kills any "deployable civic infrastructure" claim. Avoid.

**Recommendation on model:** **Gemma 3 270M (fine-tuned) as first choice, Gemma 4 E2B (Apache 2.0) as the "full LLM" arm, Qwen3 0.6B as the licence-clean small baseline.** Reasoning in §6.

---

## 2. Quantization

### 2.1 What the numbers actually say

The best controlled study of llama.cpp quantization (Kurt, Jan 2026 🟡) evaluated every GGUF type on Llama-3.1-8B across GSM8K / HellaSwag / IFEval / MMLU / TruthfulQA:

| Format | Size reduction | Aggregate score (FP16 = 69.47) | Loss |
|---|---|---|---|
| FP16 | — | 69.47 | baseline |
| Q8_0 | ~47% | 69.41 | **0.09%** |
| Q5_0 | 65.19% | slightly **above** baseline | ~0% |
| Q4_K_M | 69.41% | 69.15 | **0.46%** |
| Q4_K_S | 70.83% | — | 0.43% |
| Q3_K_S | ~74% | — | GSM8K drops **9.32 points** |

**Task sensitivity is the important finding, not the average.** HellaSwag (pattern completion) varies by <2 points across every format. GSM8K (multi-step reasoning) collapses below Q4. Our task — surface-realise a fully-specified fact set — is far closer to HellaSwag than to GSM8K. That is good news: **Q4_K_M is safe for this workload in a way it would not be for a reasoning workload.**

### 2.2 The caveat that matters most, and that most write-ups miss

The study above is on an **8B** model. Our candidates are 0.27B–2.3B. **Quantization damage is not scale-invariant.** Ouyang et al., *Low-Bit Quantization Favors Undertrained LLMs* (ACL 2025 🟢), establish scaling laws showing quantization-induced degradation grows with training-token-count per parameter — i.e. **the heavily-over-trained small models we want are exactly the models that suffer most from low-bit PTQ.** Gemma 3 1B and Qwen3 0.6B are trained on trillions of tokens for their size; they are the opposite of undertrained.

**Practical consequence:** do not naively assume "Q4_K_M costs 0.5%" transfers from 8B to 0.6B. Two mitigations, both available:
1. **Prefer QAT checkpoints over post-training quantization.** Google ships INT4 **Quantization-Aware-Trained** checkpoints for Gemma 3 270M and Gemma 3 1B. The measured difference is visible in the vendor's own table: QAT int4 hits **322 tok/s prefill** where post-training dynamic_int4 hits 138, at a *smaller* file size (529 MB vs 657 MB) 🟢.
2. **Use Q8 if you have the RAM.** At 0.27B–0.6B, Q8_0 is ~270–600 MB — cheap enough that the 4-bit gamble is unnecessary.

### 2.3 Realistic memory footprints (measured, not estimated)

| Model + quant | Runtime | File size | **Peak process RAM** | Source |
|---|---|---|---|---|
| Gemma 3 1B, dynamic_int4 (blk 128), 1280 ctx | MediaPipe, S24U | 657 MB | **982 MB** | 🟢 |
| Gemma 3 1B, dynamic_int4 (blk 128), 4096 ctx | MediaPipe, S24U | 657 MB | **1,145 MB** | 🟢 |
| Gemma 3 1B, int4 QAT, 2048 ctx, CPU | LiteRT-LM, S24U | 529 MB | **1,009 MB** | 🟢 |
| Gemma 3 1B, int4 QAT, 2048 ctx, GPU | LiteRT-LM, S24U | 529 MB | **1,205 MB** | 🟢 |
| Gemma 3 1B, dynamic_int8, 4096 ctx | MediaPipe, S24U | 1,005 MB | **1,504 MB** | 🟢 |
| Gemma 3 1B, **fp32** | MediaPipe, S24U | 3,824 MB | **4,123 MB** | 🟢 |
| Gemma 4 E2B, CPU | LiteRT-LM, S26U | — | **1,733 MB** | 🟢 |
| Gemma 4 E2B, GPU | LiteRT-LM, S26U | — | **676 MB** | 🟢 |
| Llama 3.2 1B, SpinQuant | ExecuTorch, OnePlus 12 | 1,083 MB | **1,921 MB** | 🟢 |
| Llama 3.2 3B, SpinQuant | ExecuTorch, OnePlus 12 | 2,435 MB | **3,726 MB** | 🟢 |
| Llama-2 7B, 4-bit | llama.cpp, various | — | **~3.8 GB** | 🟡 |
| Llama-2 7B, 4-bit | MLC-LLM (GPU) | — | **4.2–4.4 GB** | 🟡 |

**Two observations the brief needs to absorb:**

1. **Context length is a first-class memory cost.** Gemma 3 1B goes 982 → 1,145 MB purely by moving 1,280 → 4,096 context. The KV cache is not free. A routing-explanation prompt needs perhaps 300–600 tokens; **cap the context at 1024 and save ~200 MB**.
2. **The "1–3 GB model" in the brief is real, and it is a problem on the target hardware.** A typical Indian mid-range phone in the pilot demographic has 6–8 GB total RAM, of which ~3–3.5 GB is realistically available to a foreground app. A navigation app is *constantly backgrounded* — the user switches to WhatsApp, takes a call, locks the screen. An app holding 1.5–2 GB resident is a prime candidate for Android's low-memory killer, and the reload cost is a cold model load (multi-second). **A 1.9 GB Llama 3.2 1B and a 1.7 GB Gemma 4 E2B are both at meaningful risk of being killed mid-drive. A 500 MB Gemma 3 1B int4-QAT, or a ~250 MB Gemma 3 270M, is not.** This alone argues strongly down-model.

---

## 3. Mobile runtimes

### 3.1 Comparison table

| Runtime | Android backends | Production-viable on mid-range? | Constrained decoding | Flutter path | Verdict for CityPulse |
|---|---|---|---|---|---|
| **LiteRT-LM** (Google) | **CPU ✅, GPU ✅, NPU ✅** | **Yes — best option.** Google calls it "production-ready"; ships in Chrome, Chromebook Plus, Pixel Watch. Kotlin/C++/Python APIs marked **Stable** | ✅ **Function calling with constrained decoding**, explicitly for accuracy | ⚠️ Flutter listed as **"Community"** status, *not* production-ready — but `flutter_gemma` is that community binding and is healthy (§5) | **Recommended primary** |
| **MediaPipe LLM Inference API** | CPU, GPU | ⚠️ **Maintenance-only mode.** Google's own docs say "We recommend migrating your Android projects to LiteRT-LM Android (Kotlin) API" | Not documented | via `flutter_gemma` MediaPipe engine | **Do not start new work here.** Legacy |
| **llama.cpp** | CPU ✅; GPU via OpenCL **only on Adreno 750/830/X85** — docs state "A6x GPUs in phones are likely not supported due to the outdated driver and compiler"; backend still **experimental** | CPU-only on mid-range. Works, but slow | ✅ **GBNF grammars + JSON-Schema→GBNF** — the most mature constrained-decoding stack on mobile | `fllama` (git dep) / `llama_cpp_dart` (§5) | **Recommended as the constrained-generation arm / research baseline** |
| **ExecuTorch** (PyTorch) | CPU (XNNPACK+KleidiAI), Qualcomm HTP, MediaTek NPU | Beta. Excellent published numbers on *flagships*; toolchain (export → .pte → delegate) is a multi-week learning curve | Partial | No maintained Flutter binding | **Out of scope for 7 weeks** |
| **MLC-LLM** | Vulkan/OpenCL GPU | ❌ Measured **1.1–1.8 tok/s decode** for a 7B on flagship GPUs, with **<3% arithmetic-unit utilisation on Mali** and 4.2–4.4 GB RAM. Mid-range Mali is catastrophic | via grammar (XGrammar) | No maintained Flutter binding | **Rule out** |
| **ONNX Runtime Mobile / onnxruntime-genai** | CPU, NNAPI/QNN EPs | Works; smallest ecosystem of mobile LLM examples; model conversion friction | Via genai search API | Supported as an engine inside `flutter_gemma` | Fallback only |
| **Apple Foundation Models / Core ML** | — | iOS only. ~3B model at **2 bits/weight QAT**, free, with first-class **guided generation** | ✅ Excellent (Swift macro-based constrained decoding) | LiteRT-LM v0.15.0 added Apple Foundation Framework integration | **Irrelevant to the Chennai Android pilot**, but the *right* comparison point in the paper: Apple solved this by shipping the model with the OS |

### 3.2 NPU/GPU delegation — the honest picture

This is the single most over-claimed area in on-device LLM marketing, and the 2026 literature is now clear.

**Prefill on an NPU is genuinely transformative.** Google measures **5,836 tok/s prefill** for Gemma 3 1B on a Galaxy S25 Ultra NPU vs 379 tok/s on the same phone's CPU — a 15× speedup, at *lower* RAM (626 MB) 🟢. Cai et al. (*Is Your NPU Ready for LLMs?*, arXiv 2607.05475 🟡) measure >1,400 tok/s prefill on Hexagon NPUs.

**Decode on an NPU is not, and costs more energy.** The same paper measures NPU decode at only **20–70 tok/s — comparable to CPU — while consuming 3–4× more energy per token (≈320–430 mJ/token on NPU vs ≈100–140 mJ/token on CPU backends).** The cause is architectural: static-graph NPU designs mismatch decode's dynamic, memory-bound nature, and CPU polling overhead during NPU execution wastes up to 40% of energy. They also find **up to 15× performance variance across frameworks on the same NPU** — i.e. NPU results are a property of your software stack, not your silicon.

**And none of this is available on mid-range hardware anyway.** Qualcomm's Hexagon LLM path (GENIE/QNN) targets SM8650/SM8750/SM8850 — 8-series flagships. llama.cpp's Adreno OpenCL backend explicitly excludes the A6x GPUs found in mid-range phones. **For CityPulse's actual target device, the honest assumption is: CPU-only, big cores, INT8 SIMD (`smmla`/`sdot`) if the SoC has it.** Xiao et al. 🟡 measure that those INT8 matmul instructions alone give up to **4× prefill speedup**, and that scheduling onto big cores only (excluding efficiency cores) matters by up to **60%** — those are the optimisations actually available to us.

---

## 4. Realistic performance on mid-range Android

### 4.1 Flagship reference points (Google's own measurements, Gemma 3 1B, Galaxy S24 Ultra) 🟢

| Backend | Quant | Ctx | Prefill tok/s | Decode tok/s | **TTFT** | RAM |
|---|---|---|---|---|---|---|
| CPU | fp32 | 1280 | 49 | 10 | **5.59 s** | 4,123 MB |
| CPU | dyn_int4 b128 | 1280 | 138 | 50 | **2.33 s** | 982 MB |
| CPU | dyn_int4 b128 | 4096 | 87 | 37 | **3.40 s** | 1,145 MB |
| CPU | **int4 QAT** | 2048 | **322** | 47 | **3.10 s** | 1,138 MB |
| CPU | dyn_int8 | 1280 | 177 | 33 | **1.69 s** | 1,341 MB |
| GPU | int4 QAT | 2048 | **2,585** | 56 | 4.50 s | 1,205 MB |
| GPU | dyn_int8 | 4096 | 814 | 24 | 4.99 s | 2,167 MB |
| **NPU (S25U)** | a16w4 QAT | 1280 | **5,836** | **85** | — | 626 MB |

Note the counter-intuitive result: **GPU has *worse* TTFT than CPU** (4.50 s vs 3.10 s) despite 8× the prefill throughput, because of context-setup and memory-transfer overhead. For short prompts, CPU wins on latency.

### 4.2 The only real mid-range measurements I could find 🟠

Urja Labs (June 2026) ran a CPU-only in-app harness, 3 runs at temperature 0, on **Galaxy M55s (Snapdragon 7 Gen 1, 8 GB)** and **Xiaomi Pad 6 (Snapdragon 870, 8 GB)**:

| Model | Device | Decode tok/s | Long-context TTFT | Peak RAM |
|---|---|---|---|---|
| Qwen3 0.6B | Galaxy M55s (SD 7 Gen 1) | **3.3** | ~10–11 s | ≤2.0 GB |
| Gemma 4 E2B | Galaxy M55s (SD 7 Gen 1) | **5.8–7.0** (varies with thermal load) | ~10–11 s | ≤2.0 GB |
| Qwen3 0.6B | Xiaomi Pad 6 (SD 870) | **4.9** | ~10–11 s | ≤2.2 GB |
| DeepSeek-R1 1.5B | Xiaomi Pad 6 (SD 870) | **7.0** | ~10–11 s | ≤2.2 GB |

The author's own headline conclusion: *"Prefill latency dominates user experience, not decode speed."* Energy-per-1000-tokens and sustained thermal behaviour are explicitly **not measured** — that gap is an opportunity for our paper.

⚠️ **Caveat:** single blog, one author, devices plugged in, no peer review. It is the best available and I am using it, but the project must re-measure.

### 4.3 Cross-device scaling factor (my derivation — treat as ±50%)

Xiao et al. 🟡 give the cleanest mid-tier vs flagship ratio, same model, same runtime (llama.cpp, Llama-2 7B Q4):

| SoC | Tier | Prefill tok/s | Decode tok/s |
|---|---|---|---|
| Dimensity 9300 | flagship | 12.7 | 8.2 |
| Snapdragon 8 Gen 3 | flagship | 10.2 | 6.3 |
| Snapdragon 8+ Gen 1 | flagship (older) | 6.4 | 3.5 |
| Kirin 9000E | high-tier | 5.5 | 2.9 |
| **Snapdragon 870** | **mid-tier** | **3.8** | **1.7** |
| **Kirin 985** | **mid-tier** | — | — |

**Mid-tier is ~3.7× slower on decode and ~2.7× slower on prefill than a same-generation flagship, on the same software.**

Applying that to Google's Gemma 3 1B int4-QAT CPU numbers:

| | S24 Ultra (measured 🟢) | **Mid-range estimate (derived)** |
|---|---|---|
| Prefill | 322 tok/s | **~90–120 tok/s** |
| Decode | 47 tok/s | **~12–15 tok/s** |
| TTFT (2048 ctx) | 3.10 s | **~6–9 s** |
| Model load (cold) | — | **~1.5–4 s** |

**What this means for the actual product.** The target explanation — *"Route A is 4 minutes slower; it avoids a flooded underpass reported 3 minutes ago"* — is ~20 tokens. With a 400-token prompt (route summary + hazard list + instruction):

- **Prefill:** 400 / ~100 tok/s ≈ **4 s**
- **Decode:** 20 / ~13 tok/s ≈ **1.5 s**
- **Total ≈ 5.5 s**, plus cold-load if the model was evicted (+2–4 s)
- **Template NLG:** **< 1 ms**, no load, no RAM

That is the central quantitative fact of this strand. The LLM is roughly **5,000× slower** at producing the same twenty words, on a device the user is holding while driving toward a flooded underpass.

### 4.4 Battery and thermal

| Finding | Number | Source |
|---|---|---|
| Sustained-load throughput loss, flagship Android (S24 Ultra, 20 iterations) | **15%** (12.21 → 10.38 tok/s) via DVFS; CPU 59.7–64.0 °C, GPU 61.1–68.5 °C | 🟡 Tummalapalli et al. 2026 |
| Sustained-load throughput loss, iPhone 16 Pro | **41.5%** (40.49 → 23.67 tok/s), Normal→Warm→Hot, **no recovery** | 🟡 same |
| Battery drain, 20 long generations | **7% (S24 Ultra)**, 5% (iPhone 16 Pro) | 🟡 same |
| Energy per token, S24 Ultra | **146.4 mJ** (avg 1.59 W, peak 2.075 W) | 🟡 same |
| Throughput degradation across repeated rounds, SD 8 Gen 3 | **up to 30%** | 🟡 Xiao et al. |
| Device temperature during sustained inference | **42.6 °C → 66.8 °C** | 🟡 Xiao et al. |
| Energy per inference round | **4.54–8.28 mAh** | 🟡 Xiao et al. |
| Default on-device inference vs cloud offloading (power) | On-device consumed **138%** of the power of offloading in a text-polish task | 🟡 EnerInfer 2026 |
| Total prompts before phone shutdown at peak frequency | **~500** | 🟡 EnerInfer 2026 |
| Gemma 3 270M INT4, 25 conversations | **0.75% of a Pixel 9 Pro battery** | 🟢 Google |

**Read these two rows together:** a ~2B-class model drains ~7% of battery for 20 generations; a 270M model drains 0.75% for 25. **That is a ~10× energy difference for a task where the 270M model is fully capable, because the task is surface realisation, not reasoning.**

And note the thermal result is *worse* than it looks for us: those tests were bursty benchmarks. A navigation session is a **sustained** workload on a phone that is *also* running GPS, screen-on at high brightness, mobile data, and often charging in a hot car in Chennai. All the flagship throttling numbers above should be treated as **optimistic upper bounds** for our deployment context.

---

## 5. Flutter integration — maturity assessment

| Package | Version / activity | Engine | Constrained output | Assessment |
|---|---|---|---|---|
| **`flutter_gemma`** | **v1.8.0, published within 30 h of writing; 431 likes; verified publisher** | **LiteRT-LM** (`.litertlm`) + MediaPipe (`.task`/`.bin`) + ONNX Runtime | ✅ **Function calling** on Gemma 4, Gemma 3n, Gemma 3 1B, Qwen3, Qwen2.5, Phi-4 | **The clear winner.** Actively maintained, multi-engine, Android arm64-v8a fully supported, GPU via OpenCL declaration, foreground-service support for model download. Also ships on-device RAG (qdrant-edge / sqlite-vec) and EmbeddingGemma — directly useful for Haven Mode |
| **`fllama`** (Telosnex) | 208★, 523 commits, **git dependency only, no pub.dev release, last substantive update noted Feb 2024** | llama.cpp | ✅ JSON-schema-constrained function calling | Feature-rich but **stale and unversioned**. Dual-licensed GPLv2 + commercial — a GPL dependency is a live concern for a "civic infrastructure" project |
| **`fllama`** (pub.dev, xuegao-tzx) | v0.0.1, Nov 2024, **4 likes** | llama.cpp via platform channels | ❌ none documented | Different package, same name. **No Android GPU.** Avoid |
| **`llama_cpp_dart`** | v0.2.2 (Jan 2026), 82 likes, MIT, prerelease 0.9.0-dev.12 in flight | llama.cpp FFI | Via raw llama.cpp params | **Best llama.cpp path.** Three abstraction levels including a non-blocking **managed isolate** — essential, because inference must not block the Flutter UI thread |
| Raw platform channels / `dart:ffi` | — | anything | — | Only if the team has a specific need the packages don't cover. **Do not do this in 7 weeks** |

**Critical architectural note for Flutter:** all inference must run in a Dart **isolate** (or on a native background thread). A 5-second synchronous generate on the platform thread will freeze the map, drop the GPS stream, and trigger an ANR. `llama_cpp_dart`'s managed isolate and `flutter_gemma`'s async streaming API both handle this; hand-rolled FFI will not.

**Also note:** Google's own LiteRT-LM support matrix lists **Flutter as "Community", not production-ready** — while listing Kotlin as Stable. If the team hits a wall, the escape hatch is a thin Kotlin/`MethodChannel` shim over the stable LiteRT-LM Kotlin API. Budget for that possibility.

---

## 6. THE CRITICAL QUESTION — is an LLM the right tool?

### 6.1 Characterising the task precisely

Target output: *"Route A is 4 minutes slower; it avoids a flooded underpass reported 3 minutes ago."*

Decompose it. Every content-bearing element is a field in the routing engine's output:

| Surface element | Source | Free-form? |
|---|---|---|
| "Route A" | route ID | ❌ enumerable |
| "4 minutes slower" | `eta_delta_s` | ❌ arithmetic |
| "avoids" | route-vs-hazard geometric relation | ❌ boolean |
| "flooded underpass" | `hazard.type` × `hazard.road_class` | ❌ closed vocabulary |
| "reported 3 minutes ago" | `now − hazard.timestamp` | ❌ arithmetic |

**There is no element of this sentence that is not fully determined by structured input.** In NLG terms, the content-determination and document-planning stages are *done by the routing engine*. What remains is **sentence aggregation, lexicalisation, referring-expression generation and surface realisation over a closed domain** — the textbook case where, per Gatt & Krahmer's JAIR survey 🟢 and van Deemter, Krahmer & Theune's *Real versus Template-Based NLG: A False Opposition?* 🟢, a template/slot system and a "real" NLG system are not meaningfully different in output quality, and the opposition between them is largely illusory.

### 6.2 Four-way comparison

| | (a) Full local LLM | (b) Grammar/JSON-constrained LLM | (c) Templated / slot-filled NLG | (d) Small fine-tuned seq2seq |
|---|---|---|---|---|
| **Semantic accuracy on facts** | Probabilistic. Best small models hallucinate **5.7–7.4%** of the time on *grounded summarisation* (Qwen3-4B 5.7%, Gemma-3-4B 6.4%) 🟢 — and those are 4B models, above our RAM budget. Our 0.6–2B candidates will be worse | High but not guaranteed — grammar constrains **form**, not **truth**. A grammar can force `{"eta_delta_min": <int>}` but cannot force the int to be 4 | **100% by construction** | Better than (a); still a neural model, still hallucinates. No training data exists for our domain |
| **Latency, mid-range** | ~5.5 s (§4.3) | ~5.5 s + grammar sampling overhead | **<1 ms** | ~1–3 s |
| **RAM** | 0.7–2.0 GB resident | same | **~0 (kilobytes of strings)** | ~200–600 MB |
| **Battery** | ~7% / 20 generations (2B class) 🟡 | same | **0** | ~0.75% / 25 (270M class) 🟢 |
| **Determinism / reproducibility** | None at T>0; weak even at T=0 across quantizations | Structure deterministic, content not | **Total** | None |
| **Offline** | ✅ | ✅ | ✅ (trivially — it's a function) | ✅ |
| **Multilingual (ta/hi/en)** | ✅ native | ✅ | Needs a translated template set per language (real work, but bounded and *auditable* — a civic-safety asset) | Needs per-language training data (we have none) |
| **Long-tail compositionality** | ✅ genuine strength | ✅ | ❌ combinatorics grow with #hazard-types × #relations × #severities | ✅ |
| **Auditability for a safety claim** | ❌ | ⚠️ partial | ✅ every possible output enumerable and reviewable | ❌ |
| **Buildable in 7 weeks by 3 students** | ⚠️ integration yes, evaluation no | ⚠️ | ✅ 2–3 days | ❌ no dataset, no time |

### 6.3 What the NLG literature actually supports

I want to be careful not to overstate the pro-template case, because the empirical record is genuinely mixed.

**Against templates:** In the E2E NLG Challenge (Dušek, Novikova & Rieser, INLG 2018 🟢) — the canonical structured-data→sentence shared task, whose input MRs look almost exactly like our slot dict — the human evaluation put the template systems in the **bottom cluster for quality**, and TUDA/FORGE3/TR2 in the bottom cluster for naturalness. Neural seq2seq beat templates on automatic metrics "significantly." **Templates do produce stiffer, more repetitive prose, and users notice.** That is a real cost and we should not pretend otherwise.

**For templates:** the same paper concedes the broader field pattern — *"while rule-based approaches are not able to beat data-driven systems in terms of automatic metrics, they often perform comparably or better in human evaluations."* And the systematic review of data-to-text NLG (Osuji, Castro Ferreira & Davis, 2024 🟡, 90 papers) states the trade-off plainly: template systems *"provide built-in faithfulness to input, a carefully regulated style, and quick response times,"* while neural approaches suffer *"hallucinations, repetitions, omissions, inconsistencies, and a lack of coherence,"* and the review finds **no universally effective hallucination-mitigation method** — all are task-specific.

Dušek & Kasner (INLG 2020 🟢) had to invent an NLI-based metric *specifically because* neural D2T systems routinely produce omissions and hallucinations that BLEU cannot see. That metric — bidirectional entailment between input-as-text and output — is directly reusable as our verifier (§7).

**Synthesis:** the E2E result says neural wins on *fluency*. The review says templates win on *faithfulness*. **For a restaurant recommendation, fluency is the product. For "there is a flooded underpass ahead," faithfulness is the product and fluency is a nice-to-have.** The literature does not tell us templates are better in general; it tells us the trade-off axis, and our position on that axis is unambiguous.

### 6.4 Verdict

**An LLM does not justify 1–3 GB of on-device model as the *generator* of the primary routing explanation.** Stated bluntly for the team: if the demo is "we shipped a 1.5 GB quantized model to a phone so it could say a sentence that a 40-line Dart function says instantly, correctly, and for free," that is not novelty — it is a negative result dressed as a feature, and a competent examiner will say so.

**But the correct response is not to delete the LLM. It is to move it.** There are three places where an on-device SLM earns its RAM, and none of them is the primary explanation string:

1. **Conversational follow-up.** *"Why not the highway?"* / *"How long until it clears?"* — user-initiated, latency-tolerant (the user has stopped to ask), open-ended, and genuinely not enumerable. This is a real capability templates cannot provide.
2. **Long-tail composition.** Three simultaneous hazards of different types with conflicting severities and staleness — template combinatorics blow up; an LLM aggregates gracefully.
3. **Haven Mode advisory prose.** *"Air quality at home is worse than at your office for the next six hours; consider staying"* — inherently softer, less safety-critical, more genuinely generative.

### 6.5 Recommended hybrid design

```
                     ROUTING ENGINE
                           │
                  ┌────────▼─────────┐
                  │  FACT SET (JSON) │   route_id, eta_delta_s, hazard[],
                  │  single source   │   hazard.type, .age_s, .confidence,
                  │  of truth        │   avoidance_relation, geometry_ref
                  └────────┬─────────┘
                           │
      ┌────────────────────┼────────────────────┐
      │                    │                    │
┌─────▼──────┐    ┌────────▼────────┐   ┌───────▼────────┐
│  TIER 0    │    │     TIER 1      │   │    TIER 2      │
│ Template   │    │ On-device SLM   │   │  Cloud LLM     │
│ NLG        │    │ rewrite layer   │   │  (online only) │
│            │    │                 │   │                │
│ ALWAYS runs│    │ OPTIONAL        │   │ conversational │
│ <1 ms      │    │ grammar-        │   │ + rich Q&A     │
│ 0 RAM      │    │ constrained     │   │                │
│ 100% faith │    │ ~5 s, 0.5-1.7GB │   │                │
└─────┬──────┘    └────────┬────────┘   └───────┬────────┘
      │                    │                    │
      │            ┌───────▼────────┐           │
      │            │   VERIFIER     │◄──────────┘
      │            │ every number & │
      │            │ entity in the  │
      │            │ output must    │
      │            │ appear in the  │
      │            │ FACT SET       │
      │            └───────┬────────┘
      │                    │ FAIL
      └────────────────────┴──────────► emit TIER 0 string
```

**Design rules, stated as invariants:**

- **R1.** Tier 0 output is computed *first, always*, and is the displayed string unless a higher tier's output passes verification. There is no code path in which the user sees an unverified sentence.
- **R2.** The SLM is a **rewriter, not a generator.** Its prompt contains the fact set *and the Tier-0 sentence*. Its job is fluency and aggregation, never fact introduction. This is a much easier task than open generation and is exactly where a 270M model is adequate.
- **R3.** Output is grammar-constrained (GBNF via llama.cpp, or LiteRT-LM function calling) to a schema, so parse failures are impossible.
- **R4.** A **symbolic verifier** runs on every LLM output: extract all numerals, units, hazard nouns and road references; assert each is present in the fact set; assert no numeral in the output is absent from it. Any mismatch → silent fallback to Tier 0, logged.
- **R5.** The **fallback rate is a headline metric of the project**, not a hidden failure. "Our on-device rewrite layer passed verification on X% of 500 held-out routing decisions; the remaining Y% fell back to deterministic text with no user-visible failure" is a genuine, quantitative, novel result about small-model reliability in a safety context. *That* is the paper.

**Why this is more novel than "we ran a quantized LLM on a phone."** Running Gemma on Android is a tutorial. **A verified-generation architecture with a measured fallback rate, deployed offline on commodity mid-range hardware for a safety-critical civic application, is a contribution** — it sits precisely in the gap the data-to-text review identifies (no general hallucination-mitigation method exists; solutions are task-specific) and it produces a number nobody has published.

### 6.6 Model choice, revisited in light of §6.5

Under R2, the SLM's job is *constrained rewriting of a supplied sentence*, not reasoning. That collapses the model-size requirement:

**Primary recommendation: Gemma 3 270M IT, INT4 QAT, fine-tuned on ~1–2k synthetic (fact-set → sentence) pairs generated from the template engine itself + a cloud LLM as paraphraser.** Google built and marketed this model for exactly this ("unstructured to structured text processing", task-specific fine-tuning), it costs **0.75% battery per 25 conversations**, it is ~250 MB (survives backgrounding), and QAT checkpoints exist. Fine-tuning it is a LoRA job on free Colab.

**Secondary / "full LLM" arm for the comparison: Gemma 4 E2B (Apache 2.0)** via LiteRT-LM + `flutter_gemma`. Use it to demonstrate the capability ceiling and to measure the cost — 1,733 MB CPU RAM, ~5.8–7.0 tok/s decode on a Snapdragon 7 Gen 1 🟠 — which is itself the evidence for choosing the 270M.

**Licence-clean small baseline: Qwen3 0.6B (Apache 2.0)** via llama.cpp + GBNF, for the grammar-constrained arm.

---

## 7. Faithfulness: risk and mitigation

### 7.1 The risk, quantified

A local quantized model asserting *"the underpass is clear"* when the fact set says flooded, or *"reported 3 minutes ago"* when it was 3 hours ago, is a potential-harm event in a system whose stated purpose is emergency routing. Four compounding sources of risk:

1. **Base hallucination rate.** On grounded summarisation — a task *easier* than free generation — the best small models on the Vectara leaderboard (HHEM-2.1/2.3 🟢) hallucinate **5.7% (Qwen3-4B)** to **7.4% (Gemma-3-27B, Ministral-8B)**, with one 3B model at **24.2%**. **Our candidates are smaller than all of these.** A 5% per-explanation error rate over a driving session with dozens of re-routes is not acceptable for safety content.
2. **Quantization degrades explanations specifically.** Wang et al. (2026 🟡) measure that quantization causes up to **4.4% decline in self-explanation quality and 2.38% in faithfulness**, that natural-language explanations are *more* sensitive than other explanation types, and that human raters found quantized models up to **8.5% less trustworthy and coherent**. Critically, they find **LLM-as-a-judge evaluation fails to detect this** — so we cannot evaluate our own quantized model with another LLM.
3. **Small models are format-fragile.** Hamilton & Mimno (2025 🟡) show grammar-constrained decoding *"appears to degrade task accuracy,"* that leading-whitespace tokenisation changes results by **5–10%**, and that this sensitivity is **"strongest for smaller models."** Constrained decoding is a safety net with its own failure mode.
4. **PalmBench (🟡, ICLR'25 submission)** explicitly flags *"hallucinations and toxic content generated by compressed LLMs"* as a finding, not an aside.

### 7.2 Mitigation stack (defence in depth, cheapest first)

| Layer | Mechanism | Guarantees | Cost |
|---|---|---|---|
| **0. Never generate facts** | R2: LLM rewrites a correct sentence, given the fact set. It has nothing to invent | Removes most of the risk surface | free |
| **1. Grammar constraint** | GBNF / JSON-Schema→GBNF (llama.cpp) or LiteRT-LM constrained function calling. Set `additionalProperties: false` (llama.cpp docs note this is the default *"for performance and hallucination reduction"*) | Output is always parseable; hazard type restricted to a closed enum in the grammar itself | small sampling overhead; avoid `x? x? x?` patterns which cause pathological slowdown |
| **2. Symbolic verifier (R4)** | Regex/NER extraction of numerals, units, hazard nouns, road names; set-membership check against the fact set, both directions (nothing invented, nothing critical omitted) | **Catches every numeric and entity hallucination.** This is the load-bearing layer | <1 ms; ~150 lines |
| **3. NLI verifier (optional, research arm)** | Dušek & Kasner's bidirectional-entailment method 🟢: verbalise the fact set with trivial templates, run a small NLI model both ways to detect omissions *and* hallucinations | Catches semantic (non-lexical) errors the regex misses | needs a ~100 MB NLI model on device; nice paper contribution, cut if time-pressed |
| **4. Template fallback (R1)** | Any failure at layers 1–3 → emit Tier 0 | **The user never sees an unverified safety claim.** This is what makes the whole design defensible | free |
| **5. Confidence surfacing** | The brief already requires confidence-decay indicators. Extend: mark which sentences were machine-rewritten vs deterministic | Honest UI; also an HCI evaluation angle | free |
| **6. Numbers stay numbers** | Never let the model render `eta_delta_s` → prose. Inject rendered numerals as literal tokens the grammar must reproduce verbatim | Eliminates the highest-severity error class (wrong number) | free |

**One-line statement of the safety property the architecture guarantees:** *no string containing a hazard assertion or a numeric quantity reaches the user unless every such assertion and quantity was present in the routing engine's structured output.* That property holds regardless of how badly the quantized model misbehaves — which is exactly the property you want when you cannot bound a neural model's behaviour.

---

## 8. Seven-week feasibility verdict — 3-person student team

Assuming this strand is roughly one-fifth of the project's effort (ingest, routing, backend, UI and Haven Mode are the others), and that **no one on the team has shipped on-device ML before**:

### 8.1 Realistically buildable ✅

| # | Deliverable | Effort | Week |
|---|---|---|---|
| 1 | **Deterministic template NLG engine** in Dart — fact-set schema, ~20–40 templates covering hazard types × relations × severity × staleness, with `intl` pluralisation and ta/hi/en variants | **2–3 days** | 1–2 |
| 2 | **`flutter_gemma` integration**, model download + foreground service + isolate-based streaming, Gemma 3 1B int4-QAT `.litertlm` on-device, end-to-end offline | 4–6 days | 2–3 |
| 3 | **Grammar/function-calling constrained output** + symbolic verifier (R4) + fallback (R1) | 3–4 days | 3–4 |
| 4 | **Benchmark harness**: prefill/decode tok/s, TTFT, peak RSS, battery delta, thermal (via `BatteryManager` + thermal-status API), on **≥2 real mid-range phones** — this is the data that does not exist publicly | 4–5 days | 4–5 |
| 5 | **Head-to-head evaluation**: template vs constrained-SLM vs unconstrained-SLM on ~300–500 synthetic routing decisions; metrics = semantic accuracy (automatic, via the verifier), latency, RAM, energy, plus a small human fluency rating (n≈20, 5-point, the E2E protocol) | 4–5 days | 5–6 |
| 6 | **Gemma 3 270M LoRA fine-tune** on template-generated + cloud-paraphrased pairs, deployed and re-benchmarked | 3–4 days | 5–6 (stretch) |
| 7 | Demo hardening, offline airplane-mode demo path, writeup | — | 7 |

### 8.2 Not realistically buildable ❌

- **Training a seq2seq from scratch.** No dataset exists; building one is itself a semester.
- **NPU delegation (QNN/Hexagon, MediaTek NEURON).** Flagship-only, framework variance up to 15×, and the toolchain alone is multi-week.
- **Custom ExecuTorch export/delegate pipeline.** Excellent technology, wrong time budget, no Flutter binding.
- **llama.cpp GPU on mid-range Android.** The OpenCL backend does not support the GPUs in question.
- **Gemma 3n E4B / Gemma 4 E4B / Llama 3.2 3B / Phi-4-mini on mid-range.** 3–4 GB peak RAM. They will be OOM-killed.
- **Rigorous power measurement.** Software APIs (`BatteryManager`) are, per Tummalapalli et al. 🟡, of *"lower absolute accuracy than hardware instrumentation."* Report relative deltas and state the limitation; do not claim absolute joules.
- **Any claim that the LLM "generates the route."** The brief's step 4 says the on-device model generates *"route geometry AND natural-language explanations."* **An LLM must not generate route geometry.** That is a graph search over a pre-cached OSM extract. Fix this in the brief — it is the single most technically indefensible sentence in it.

### 8.3 Recommended de-risking order

**Build item 1 in week 1 and ship the demo on it.** The offline-explanation demo then works, guaranteed, from week 2 onward, on any phone, with zero download. Every subsequent week of LLM work is then pure upside against a working baseline rather than a dependency on an unproven integration. If the LLM strand fails entirely in week 5, the project still demos — and the writeup becomes *"we measured the cost of on-device generation for this task and found it unjustified," which is a legitimate, honest, publishable negative result* rather than a missing feature.

### 8.4 Risk register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Model evicted by Android LMK when app is backgrounded mid-drive | **High** for ≥1.5 GB models | High (multi-second cold reload) | Choose ≤600 MB model; foreground service; keep Tier 0 always live |
| Team's own test devices are flagships → benchmarks are unrepresentative | **High** | High (invalidates the core claim) | Acquire/borrow ≥2 genuinely mid-range phones in week 1. Non-negotiable |
| TTFT of 5–9 s makes the feature unusable while driving | **High** | High | Tier 0 renders instantly; LLM rewrite streams in and replaces it only after verification |
| `flutter_gemma` breaking change (v1.8.0 ships frequently) | Medium | Medium | Pin the version; keep the Kotlin `MethodChannel` + LiteRT-LM Stable API as the escape hatch |
| Thermal throttling in a hot Chennai car far exceeds benchmark conditions | Medium–High | Medium | Measure it — this is a contribution. Add a thermal-status guard that disables Tier 1 above `THERMAL_STATUS_MODERATE` |
| Gemma licence (if using 3.x) constrains the "civic infrastructure" framing | Low | Medium | Use Apache-2.0 Gemma 4 E2B or Qwen3 for anything claimed as deployable |
| Human evaluation (item 5) is underpowered at n≈20 | High | Low | Report as indicative; lead with the automatic semantic-accuracy metric, which is objective |

---

## 9. Verified sources

All URLs were fetched or returned by search during this session on 2026-09-11.

**Peer-reviewed / archival 🟢**

1. Dušek, Novikova & Rieser (2018), *Findings of the E2E NLG Challenge*, INLG — https://aclanthology.org/W18-6539/ (PDF: https://aclanthology.org/W18-6539.pdf)
2. Dušek & Kasner (2020), *Evaluating Semantic Accuracy of Data-to-Text Generation with Natural Language Inference*, INLG — https://aclanthology.org/2020.inlg-1.19/
3. van Deemter, Krahmer & Theune (2005), *Real versus Template-Based Natural Language Generation: A False Opposition?*, Computational Linguistics 31(1):15–24 — https://aclanthology.org/J05-1002/
4. Gatt & Krahmer (2018), *Survey of the State of the Art in Natural Language Generation*, JAIR 61:65–170 — https://www.jair.org/index.php/jair/article/view/11173
5. Ouyang et al. (2025), *Low-Bit Quantization Favors Undertrained LLMs*, ACL 2025 — https://aclanthology.org/2025.acl-long.1555/ (preprint: https://arxiv.org/html/2411.17691v2)

**First-party vendor documentation / model cards / repos 🟢**

6. Google AI Edge, *LiteRT-LM Overview* (backend matrix, API stability, constrained decoding) — https://developers.google.com/edge/litert-lm/overview
7. google-ai-edge/LiteRT-LM (GitHub, v0.16.0, production-readiness statements) — https://github.com/google-ai-edge/LiteRT-LM
8. Google, *LLM Inference guide for Android* (MediaPipe **maintenance-only** notice) — https://developers.google.com/edge/mediapipe/solutions/genai/llm_inference/android
9. `litert-community/Gemma3-1B-IT` model card — full prefill/decode/TTFT/RAM benchmark grid — https://huggingface.co/litert-community/Gemma3-1B-IT
10. Google, *Gemma 3n model overview* (E2B/E4B, MatFormer, PLE caching) — https://ai.google.dev/gemma/docs/gemma-3n
11. Google Developers Blog, *Introducing Gemma 3 270M* (0.75% battery / 25 conversations, QAT, specialist-model argument) — https://developers.googleblog.com/en/introducing-gemma-3-270m/
12. `google/gemma-4-E2B-it` model card (Apache 2.0, 2.3B effective / 5.1B total, 128K ctx) — https://huggingface.co/google/gemma-4-E2B-it
13. Google DeepMind, *Gemma 4* — https://deepmind.google/models/gemma/gemma-4/
14. Gemma Terms of Use — https://ai.google.dev/gemma/terms
15. `Qwen/Qwen3-0.6B` model card (Apache 2.0, 0.44B non-embedding, 32K ctx) — https://huggingface.co/Qwen/Qwen3-0.6B
16. PyTorch ExecuTorch, Llama example README (Llama 3.2 1B/3B SpinQuant & QAT+LoRA benchmarks, OnePlus 12) — https://github.com/pytorch/executorch/blob/main/examples/models/llama/README.md
17. llama.cpp, *GBNF Grammars* README (JSON-Schema→GBNF, performance gotchas) — https://github.com/ggml-org/llama.cpp/blob/master/grammars/README.md
18. llama.cpp, *OpenCL backend* docs (Adreno 750/830/X85 only; A6x phone GPUs unsupported; experimental) — https://github.com/ggml-org/llama.cpp/blob/master/docs/backend/OPENCL.md
19. Apple Machine Learning Research, *Updates to Apple's On-Device and Server Foundation Language Models* (~3B, 2 bpw QAT, guided generation) — https://machinelearning.apple.com/research/apple-foundation-models-2025-updates
20. Vectara Hallucination Leaderboard (HHEM-2.1/2.3; small-model hallucination rates) — https://github.com/vectara/hallucination-leaderboard/
21. `flutter_gemma` on pub.dev (v1.8.0, engines, function calling, platform support) — https://pub.dev/packages/flutter_gemma
22. `llama_cpp_dart` on pub.dev (v0.2.2, MIT, managed isolate) — https://pub.dev/packages/llama_cpp_dart
23. Telosnex/fllama (GitHub; JSON-schema-constrained function calling; GPLv2 + commercial) — https://github.com/Telosnex/fllama
24. `fllama` on pub.dev (v0.0.1 — the *other*, stale package) — https://pub.dev/packages/fllama
25. stevelaskaridis/awesome-mobile-llm (2025–26 model & framework index) — https://github.com/stevelaskaridis/awesome-mobile-llm

**arXiv preprints — indicative, not peer-reviewed 🟡**

26. Xiao, Huang, Chen & Tian, *Large Language Model Performance Benchmarking on Mobile Platforms: A Thorough Evaluation* — mid-tier vs flagship SoC ratios, thermal, energy — https://arxiv.org/html/2410.03613v1
27. Tummalapalli et al. (2026), *LLM Inference at the Edge: Mobile, NPU, and GPU Performance Efficiency Trade-offs Under Sustained Load* — throttling curves, battery %, mJ/token — https://arxiv.org/html/2603.23640v2
28. Cai et al. (2026), *Is Your NPU Ready for LLMs? Dissecting the Hidden Efficiency Bottlenecks in Mobile LLM Inference* — NPU decode energy paradox, 15× framework variance — https://arxiv.org/html/2607.05475v1
29. Zou et al. (2026), *EnerInfer: Energy-Aware On-Device LLM Inference* — 138%-of-cloud power finding, ~500 prompts per charge — https://arxiv.org/html/2606.23001v1
30. Li et al., *PalmBench: A Comprehensive Benchmark of Compressed LLMs on Mobile Platforms* — https://arxiv.org/abs/2410.05315
31. Kurt (2026), *Which Quantization Should I Use? A Unified Evaluation of llama.cpp Quantization on Llama-3.1-8B-Instruct* — https://arxiv.org/html/2601.14277v1
32. Wang, Feldhus, Atanasova et al. (2026), *Can Large Language Models Still Explain Themselves? Investigating the Impact of Quantization on Self-Explanations* — https://arxiv.org/html/2601.00282
33. Hamilton & Mimno (2025), *Lost in Space: Optimizing Tokens for Grammar-Constrained Decoding* — https://arxiv.org/html/2502.14969v1
34. Osuji, Castro Ferreira & Davis (2024), *A Systematic Review of Data-to-Text NLG* (90 papers) — https://arxiv.org/pdf/2402.08496
35. Liquid AI, *LFM2 Technical Report* — https://arxiv.org/html/2511.23404v1

**Independent measurement blog — load-bearing but unreplicated 🟠**

36. Urja Labs (2026-06-23), *What on-device LLMs actually cost on mid-range Android* — the only mid-range (Snapdragon 7 Gen 1 / 870) measurements located — https://urjalabs.in/blog/on-device-llm-benchmarks-mid-range-android/
37. TheElec (2026-04), *Google Unveils Gemma 4 With Apache 2.0 License* — release date and licence corroboration — https://www.thelec.net/news/articleView.html?idxno=6355

---

## 10. Open questions the team must resolve empirically

1. **What phone do Chennai pilot users actually have?** Every number in §4 is conditional on this. Get the device distribution before choosing a model.
2. **What is the verification pass rate for Gemma 3 270M fine-tuned vs Gemma 4 E2B zero-shot?** Nobody knows. This is the project's best shot at a real result.
3. **Does Tier 1 survive a 45-minute navigation session in a hot car?** Thermal data for sustained (not bursty) mobile LLM load on mid-range silicon does not exist in the literature I surveyed.
4. **Do users actually prefer the LLM-rewritten sentence?** Run the E2E human-evaluation protocol. If they do not, the negative result is the finding and it strengthens the paper.
