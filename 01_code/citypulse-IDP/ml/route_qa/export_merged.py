"""Merges a trained route-question adapter into its base model and checks the merge (ADR-035; PREREGISTRATION_QA.md addendum 5).

    python ml/route_qa/export_merged.py --run run1

Writes the merged fp16 model to `data/models/route_qa_<run>_merged/` (git-ignored, about 1 GB). Then the merge check fixed in advance:
the merged model, with no adapter attached, must give the same label (intent and secondary) as the unmerged adapter on at least 99% of
the same validation questions the run was evaluated on (same file, same seed, same sample). The check is written to
`data/qa/2026-10-13/runs/<run>/export_check.json`. Whatever it shows is reported; nothing is adjusted to pass it.

This says the merge is faithful to the adapter. It says nothing new about how well the model understands unseen questions.
"""

from __future__ import annotations

import argparse
import json
import random
import sys
import time
from pathlib import Path

import torch
from peft import PeftModel
from transformers import AutoModelForCausalLM, AutoTokenizer

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from ml.route_qa import eval_model, prompts  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
THRESHOLD = 0.99  # fixed in addendum 5 before this was run


def labels(model, tok, rows, tag: str) -> list[tuple[str | None, str | None]]:
    out = []
    for i, r in enumerate(rows):
        out.append(prompts.parse_label(eval_model.generate(model, tok, prompts.messages_u(r["question"]), 40)))
        if (i + 1) % 50 == 0:
            print(f"{tag}: {i + 1}/{len(rows)}", flush=True)
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--run", required=True)
    ap.add_argument("--n-u", type=int, default=300)
    ap.add_argument("--seed", type=int, default=20261014)
    ap.add_argument("--device", default="auto")
    ap.add_argument("--stage", choices=["save", "check", "both"], default="both")
    args = ap.parse_args()
    eval_model.DEVICE = "cuda" if (args.device == "auto" and torch.cuda.is_available()) or args.device == "cuda" else "cpu"
    dtype = torch.float16 if eval_model.DEVICE == "cuda" else torch.float32
    run_dir = eval_model.RUNS / args.run
    out_dir = ROOT / "data" / "models" / f"route_qa_{args.run}_merged"
    rev = None if eval_model.BASE != eval_model.BASE_ID else eval_model.REVISION

    val = [json.loads(x) for x in (eval_model.DATA / "val.jsonl").read_text(encoding="utf-8").splitlines() if x.strip()]
    rows = random.Random(args.seed).sample(val, min(args.n_u, len(val)))  # the same draw eval_model.py made for task U

    tok = AutoTokenizer.from_pretrained(eval_model.BASE, revision=rev)
    t0 = time.time()
    # Stage 1: merge and save (fast, so that conversion can start while the slow label check runs).
    if args.stage in ("save", "both") or not (out_dir / "model.safetensors").exists():
        base = AutoModelForCausalLM.from_pretrained(eval_model.BASE, torch_dtype=dtype, revision=rev)
        merged = PeftModel.from_pretrained(base, run_dir / "adapter").merge_and_unload().eval()
        out_dir.mkdir(parents=True, exist_ok=True)
        merged.save_pretrained(out_dir, safe_serialization=True)
        tok.save_pretrained(out_dir)
        del merged, base
        print(f"merged model saved to {out_dir} ({dtype})", flush=True)
    if args.stage == "save":
        return 0

    # Stage 2: the check, on the unmerged adapter and on the files just written (so it covers what was saved).
    base = AutoModelForCausalLM.from_pretrained(eval_model.BASE, torch_dtype=dtype, revision=rev)
    peft_model = PeftModel.from_pretrained(base, run_dir / "adapter").to(eval_model.DEVICE).eval()
    before = labels(peft_model, tok, rows, "adapter")
    del peft_model, base
    if eval_model.DEVICE == "cuda":
        torch.cuda.empty_cache()
    reloaded = AutoModelForCausalLM.from_pretrained(out_dir, torch_dtype=dtype).to(eval_model.DEVICE).eval()
    after = labels(reloaded, tok, rows, "merged")

    same = sum(a == b for a, b in zip(before, after))
    gold = sum(b == (r["intent"], r.get("secondary")) for b, r in zip(after, rows))
    gold_intent = sum(b[0] == r["intent"] for b, r in zip(after, rows))
    report = {
        "run": args.run, "n": len(rows), "seed": args.seed, "device": eval_model.DEVICE, "dtype": str(dtype),
        "same_label_as_unmerged_adapter": same / len(rows), "threshold": THRESHOLD, "passed": same / len(rows) >= THRESHOLD,
        "merged_intent_accuracy": gold_intent / len(rows), "merged_intent_and_secondary_exact": gold / len(rows),
        "disagreements": [
            {"q": r["question"], "adapter": b, "merged": a} for r, b, a in zip(rows, before, after) if b != a
        ][:20],
        "merged_dir": str(out_dir.relative_to(ROOT)), "seconds": round(time.time() - t0),
    }
    (run_dir / "export_check.json").write_text(json.dumps(report, indent=1, ensure_ascii=False), encoding="utf-8")
    print(json.dumps({k: v for k, v in report.items() if k != "disagreements"}, indent=1))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
