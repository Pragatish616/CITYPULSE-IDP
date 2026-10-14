"""Automatic checks on a trained route-question adapter (ADR-035; PREREGISTRATION_QA.md addenda 1 and 2).

    python ml/route_qa/eval_model.py --run pilot --n-u 200 --n-w 30

Task U: label accuracy on validation questions from situations the model never trained on, beside the rule-based classifier's agreement on
the same rows. Task W: the model writes answers (given the gold intent, so that writing is measured apart from understanding); every answer
is run through the Dart verifier (`tool/verify_answers.dart`) and checked for the refusal on safety questions and the hedge under low or
stale confidence. These checks are necessary, not sufficient: adoption also needs the blind ratings and the faithfulness audit by people,
and the sealed test set for understanding. The validation questions come from the same question bank as the training ones (with noise), so
the figures here overstate how the model handles questions it has never seen.
"""

from __future__ import annotations

import argparse
import json
import random
import shutil
import subprocess
import sys
import time
from collections import Counter
from pathlib import Path

import torch
from peft import PeftModel
from transformers import AutoModelForCausalLM, AutoTokenizer

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from ml.route_qa import prompts  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
BASE_ID = "Qwen/Qwen2.5-0.5B-Instruct"
REVISION = "7ae557604adf67be50417f59c2c2f167def9a775"  # the pinned revision (data/models/.../fetch_log.json)
_LOCAL = ROOT / "data" / "models" / "qwen2.5-0.5b-instruct"
# the local copy when there is one; otherwise the same pinned revision from the hub (a Colab or Kaggle machine)
BASE = str(_LOCAL) if _LOCAL.exists() else BASE_ID
DATA = ROOT / "data" / "qa" / "2026-10-13" / "generated"
RUNS = ROOT / "data" / "qa" / "2026-10-13" / "runs"
PKG = ROOT / "packages" / "pulse_explain"
DEVICE = "cpu"


def generate(model, tok, messages, max_new: int) -> str:
    text = tok.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)
    ids = tok(text, return_tensors="pt", add_special_tokens=False).to(DEVICE)
    with torch.no_grad():
        out = model.generate(**ids, max_new_tokens=max_new, do_sample=False, pad_token_id=tok.eos_token_id)
    return tok.decode(out[0, ids["input_ids"].shape[1]:], skip_special_tokens=True).strip()


def distinct(texts: list[str], n: int) -> float:
    grams: list[tuple] = []
    for t in texts:
        w = t.split()
        grams += [tuple(w[i:i + n]) for i in range(len(w) - n + 1)]
    return len(set(grams)) / max(1, len(grams))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--run", required=True)
    ap.add_argument("--n-u", type=int, default=200)
    ap.add_argument("--n-w", type=int, default=30)
    ap.add_argument("--seed", type=int, default=20261014)
    ap.add_argument("--threads", type=int, default=8)
    ap.add_argument("--base-only", action="store_true", help="evaluate the untouched base model (the reference)")
    ap.add_argument("--device", default="auto", help="auto, cpu or cuda")
    args = ap.parse_args()
    global DEVICE
    DEVICE = "cuda" if (args.device == "auto" and torch.cuda.is_available()) or args.device == "cuda" else "cpu"
    torch.set_num_threads(args.threads)
    out = RUNS / args.run
    out.mkdir(parents=True, exist_ok=True)
    rev = None if BASE != BASE_ID else REVISION
    tok = AutoTokenizer.from_pretrained(BASE, revision=rev)
    model = AutoModelForCausalLM.from_pretrained(BASE, torch_dtype=torch.float16 if DEVICE == "cuda" else torch.float32, revision=rev)
    if not args.base_only:
        model = PeftModel.from_pretrained(model, out / "adapter")
    model.to(DEVICE).eval()
    rng = random.Random(args.seed)
    val = [json.loads(line) for line in (DATA / "val.jsonl").read_text(encoding="utf-8").splitlines() if line.strip()]
    report: dict = {"run": args.run, "base_only": args.base_only}

    # ---- task U
    t0 = time.time()
    rows = rng.sample(val, min(args.n_u, len(val)))
    ok = sec_ok = bad = d0_ok = 0
    by = {"en": [0, 0], "ta": [0, 0]}
    by_src: dict[str, list[int]] = {}
    wrong: list[dict] = []
    for r in rows:
        reply = generate(model, tok, prompts.messages_u(r["question"]), 40)
        intent, sec = prompts.parse_label(reply)
        hit = intent == r["intent"]
        ok += hit
        sec_ok += sec == r.get("secondary")
        bad += intent is None
        d0_ok += bool(r["classifier_agrees"])
        by[r["locale"]][0] += hit
        by[r["locale"]][1] += 1
        s = by_src.setdefault(r["source"], [0, 0])
        s[0] += hit
        s[1] += 1
        if not hit and len(wrong) < 12:
            wrong.append({"q": r["question"], "gold": r["intent"], "model": intent, "reply": reply[:80]})
    n = len(rows)
    report["task_u"] = {
        "n": n, "intent_accuracy": ok / n, "secondary_exact": sec_ok / n, "unparseable": bad / n, "rule_classifier_agreement_same_rows": d0_ok / n,
        "by_locale": {k: (v[0] / v[1] if v[1] else None) for k, v in by.items()}, "by_source": {k: v[0] / v[1] for k, v in by_src.items()},
        "seconds": round(time.time() - t0), "examples_wrong": wrong,
    }
    print(json.dumps(report["task_u"], ensure_ascii=False, indent=1), flush=True)

    # ---- task W
    t0 = time.time()
    w_rows = [r for r in val if r["locale"] == "en" and r["answers"]]
    w_rows = rng.sample(w_rows, min(args.n_w, len(w_rows)))
    items, texts = [], []
    for r in w_rows:
        text = generate(model, tok, prompts.messages_w(r["fact_sheet"], r["question"], r["intent"], r.get("secondary")), 260)
        items.append({"id": r["id"], "trace": r["trace"], "text": text})
        texts.append(text)
    inp, outp = out / "w_answers.jsonl", out / "w_verified.jsonl"
    inp.write_text("\n".join(json.dumps(i, ensure_ascii=False) for i in items) + "\n", encoding="utf-8")
    if shutil.which("dart") is None:  # a GPU machine without Dart: keep the answers, verify them on the laptop afterwards
        print("dart not found: answers saved to w_answers.jsonl; run tool/verify_answers.dart on the laptop", flush=True)
        report["task_w"] = {"n": len(items), "verification_skipped": True}
        (out / ("eval_base.json" if args.base_only else "eval.json")).write_text(json.dumps(report, ensure_ascii=False, indent=1), encoding="utf-8")
        return 0
    subprocess.run(["dart", "run", "tool/verify_answers.dart", str(inp), str(outp)], cwd=PKG, check=True, capture_output=True, shell=sys.platform == "win32")
    ver = {v["id"]: v for v in (json.loads(line) for line in outp.read_text(encoding="utf-8").splitlines() if line.strip())}
    passed = sum(v["passed"] for v in ver.values())
    claims = Counter(c.split(":")[0] + ":" + c.split(":")[1] for v in ver.values() for c in v["claims"] if ":" in c)
    refusal_rows = [(r, t) for r, t in zip(w_rows, texts) if r["intent"] == "is_safe"]
    refused = sum("I cannot confirm the condition of any road" in t for _, t in refusal_rows)
    low = [(r, t) for r, t in zip(w_rows, texts) if "confidence: low" in r["fact_sheet"] or "confidence: stale" in r["fact_sheet"]]
    hedged = sum("use your own judgement" in t for _, t in low)
    targets = {r["id"]: {a["text"] for a in r["answers"]} for r in w_rows}
    copied = sum(t in targets[r["id"]] for r, t in zip(w_rows, texts))
    report["task_w"] = {
        "n": len(items), "verifier_pass_rate": passed / max(1, len(items)), "rejected_claim_types": dict(claims),
        "safety_questions": len(refusal_rows), "refused": refused, "low_or_stale_rows": len(low), "hedged": hedged,
        "identical_to_a_training_style": copied / max(1, len(items)), "mean_words": sum(len(t.split()) for t in texts) / max(1, len(texts)),
        "distinct_1": distinct(texts, 1), "distinct_2": distinct(texts, 2), "seconds": round(time.time() - t0),
    }
    print(json.dumps(report["task_w"], ensure_ascii=False, indent=1), flush=True)
    lines = ["# Samples (model answers; read them)\n"]
    for r, t in list(zip(w_rows, texts))[:12]:
        lines.append(f"**Q ({r['intent']}):** {r['question']}\n\n**Model:** {t}\n\n**Verifier:** {'passed' if ver[r['id']]['passed'] else ver[r['id']]['claims']}\n\n**D0 style 0:** {r['answers'][0]['text']}\n\n---\n")
    (out / "eval_samples.md").write_text("\n".join(lines), encoding="utf-8")
    (out / ("eval_base.json" if args.base_only else "eval.json")).write_text(json.dumps(report, ensure_ascii=False, indent=1), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
