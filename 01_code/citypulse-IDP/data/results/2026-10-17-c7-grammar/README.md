# C7: grammar-constrained decoding of the question labeller (17 Oct 2026)

Question: does constraining the run1 model's decoding with the label grammar (`labelGrammar()` in
`packages/pulse_explain/lib/src/question_labeler.dart`) change accuracy or speed?

Set-up (summary numbers in `result.json`; the per-run files stay in the git-ignored run folder): `tools/model_check/bin/check.dart`, the app's own `LlamaQuestionLabeler`, `route_qa_run1_q4_k_m.gguf`, llamadart 0.12.2 on the
laptop CPU (Windows), greedy decoding, the 300 held-out rows of `eval_rows_u.json`. The two runs were made one after the other in the same
background job, so CPU load was similar; it is still one laptop and one run each.

| Run | File | Intent accuracy | Secondary exact | Unparseable | ms p50 | ms p95 |
|---|---|---|---|---|---|---|
| Grammar on | `dart_runtime_check_q4_k_m_grammar.json` | 0.99 | 0.99 | 0.0 | 1504 | 2194 |
| Grammar off | `dart_runtime_check_q4_k_m_free_rerun.json` | 0.99 | 0.99 | 0.0 | 692 | 1154 |

Finding: no accuracy gain (run1 already never produced a malformed label on these rows) and about 2.2 times the median latency. The grammar
stays in the code as an option (`LlamaQuestionLabeler(constrained: true)`, `check.dart ... ` without `free`) and is **off by default**.
It is worth switching on for a smaller or differently trained model that produces malformed replies. Not measured on a phone.
