"""Labelling accuracy of a GGUF build of the route-question model, through llama.cpp's own runtime (ADR-035; PREREGISTRATION_QA.md addendum 5).

    python ml/route_qa/eval_gguf.py --gguf data/models/route_qa_run1_q4_k_m.gguf --server <path to llama-server> --run run1

Runs `llama-server` on localhost only, asks it the same 300 validation questions that `eval_model.py` used (same file, same seed, same
draw), with greedy decoding and the same two chat messages the model was trained on, and reads each reply with the same strict reader
(`prompts.parse_label`). The result is added to `data/qa/2026-10-13/runs/<run>/gguf_check.json`.

The bar was fixed before this ran: a quantised build must keep intent accuracy within 2 points of the unmerged adapter's 0.9967, that is at
least 0.977. Whatever the number is, it is reported. It says the build is faithful to the adapter; it says nothing new about unseen questions.
"""

from __future__ import annotations

import argparse
import json
import random
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from ml.route_qa import prompts  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "data" / "qa" / "2026-10-13" / "generated"
RUNS = ROOT / "data" / "qa" / "2026-10-13" / "runs"
ADAPTER_INTENT_ACCURACY = 0.9966666666666667  # run1's evaluation (eval.json), the reference the 2-point bar is measured from
BAR = ADAPTER_INTENT_ACCURACY - 0.02  # fixed in addendum 5 before this was run


def post(port: int, messages: list[dict]) -> tuple[str, float]:
    body = json.dumps({"messages": messages, "temperature": 0, "max_tokens": 40, "seed": 1, "stream": False}).encode()
    req = urllib.request.Request(f"http://127.0.0.1:{port}/v1/chat/completions", body, {"Content-Type": "application/json"})
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=120) as r:
        out = json.loads(r.read())
    return out["choices"][0]["message"]["content"], time.time() - t0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--gguf", required=True)
    ap.add_argument("--server", required=True)
    ap.add_argument("--run", required=True)
    ap.add_argument("--n-u", type=int, default=300)
    ap.add_argument("--seed", type=int, default=20261014)
    ap.add_argument("--port", type=int, default=8099)
    ap.add_argument("--threads", type=int, default=8)
    args = ap.parse_args()

    val = [json.loads(x) for x in (DATA / "val.jsonl").read_text(encoding="utf-8").splitlines() if x.strip()]
    rows = random.Random(args.seed).sample(val, min(args.n_u, len(val)))
    proc = subprocess.Popen(
        [args.server, "-m", args.gguf, "--host", "127.0.0.1", "--port", str(args.port), "-c", "1024", "-t", str(args.threads), "--no-webui"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    try:
        for _ in range(120):
            try:
                urllib.request.urlopen(f"http://127.0.0.1:{args.port}/health", timeout=2).read()
                break
            except (urllib.error.URLError, ConnectionError, OSError):
                time.sleep(1)
        else:
            raise SystemExit("llama-server did not start")
        ok = sec_ok = bad = 0
        by = {"en": [0, 0], "ta": [0, 0]}
        secs: list[float] = []
        wrong = []
        for r in rows:
            reply, dt = post(args.port, prompts.messages_u(r["question"]))
            secs.append(dt)
            intent, sec = prompts.parse_label(reply)
            hit = intent == r["intent"]
            ok += hit
            sec_ok += sec == r.get("secondary")
            bad += intent is None
            by[r["locale"]][0] += hit
            by[r["locale"]][1] += 1
            if not hit and len(wrong) < 12:
                wrong.append({"q": r["question"], "gold": r["intent"], "model": intent, "reply": reply[:80]})
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=20)
        except subprocess.TimeoutExpired:
            proc.kill()
    n = len(rows)
    secs.sort()
    res = {
        "gguf": Path(args.gguf).name, "bytes": Path(args.gguf).stat().st_size, "n": n, "seed": args.seed, "runtime": "llama.cpp llama-server (b11630), CPU",
        "intent_accuracy": ok / n, "secondary_exact": sec_ok / n, "unparseable": bad / n,
        "by_locale": {k: v[0] / max(1, v[1]) for k, v in by.items()},
        "bar": BAR, "meets_bar": ok / n >= BAR, "reference_adapter_intent_accuracy": ADAPTER_INTENT_ACCURACY,
        "seconds_per_question_p50": secs[n // 2], "seconds_per_question_p95": secs[int(n * 0.95)], "examples_wrong": wrong,
    }
    path = RUNS / args.run / "gguf_check.json"
    allres = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
    allres[Path(args.gguf).name] = res
    path.write_text(json.dumps(allres, indent=1, ensure_ascii=False), encoding="utf-8")
    print(json.dumps({k: v for k, v in res.items() if k != "examples_wrong"}, indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
