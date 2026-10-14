"""LoRA fine-tune of a small instruct model on the route-question data (ADR-035; PREREGISTRATION_QA.md addenda 1 and 2).

One adapter learns both tasks: U (question -> intent label) and W (facts + question -> answer). Only verifier-passed answers are in the
data (the generator drops the rest). Loss is on the assistant's reply only. Plain PyTorch loop, fp32, so that it runs on a CPU laptop;
checkpoints are written regularly and the run resumes from the last one.

    python ml/route_qa/train_lora.py --name pilot --n-u 200 --n-w 100 --epochs 1
    python ml/route_qa/train_lora.py --name run1 --n-u 4000 --n-w 1600 --epochs 1

Everything is seeded; the arguments and the data fingerprint are written beside the checkpoints.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import random
import sys
import time
from pathlib import Path

import torch
from peft import LoraConfig, PeftModel, get_peft_model
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
LORA = dict(r=16, lora_alpha=32, lora_dropout=0.05, target_modules=["q_proj", "k_proj", "v_proj", "o_proj", "gate_proj", "up_proj", "down_proj"])


def tokenise(tok, messages: list[dict], max_len: int):
    """Token ids and labels: the loss counts only the final assistant message."""
    full = tok.apply_chat_template(messages, tokenize=False)
    prompt = tok.apply_chat_template(messages[:-1], tokenize=False, add_generation_prompt=True)
    ids = tok(full, add_special_tokens=False)["input_ids"]
    n_prompt = len(tok(prompt, add_special_tokens=False)["input_ids"])
    if len(ids) > max_len:
        return None
    labels = [-100] * n_prompt + ids[n_prompt:]
    return torch.tensor([ids]), torch.tensor([labels])


def build_examples(args, tok) -> list[tuple[torch.Tensor, torch.Tensor, str]]:
    rng = random.Random(args.seed)
    rows = [json.loads(line) for line in (DATA / "train.jsonl").read_text(encoding="utf-8").splitlines() if line.strip()]
    u_rows = rng.sample(rows, min(args.n_u, len(rows)))
    w_rows = [r for r in rows if r["answers"] and r["locale"] == "en"]
    w_rows = rng.sample(w_rows, min(args.n_w, len(w_rows)))
    out = []
    skipped = 0
    for r in u_rows:
        t = tokenise(tok, prompts.messages_u(r["question"], {"intent": r["intent"], "secondary": r.get("secondary")}), args.max_len)
        if t:
            out.append((*t, "U"))
        else:
            skipped += 1
    for r in w_rows:
        a = rng.choice(r["answers"])
        t = tokenise(tok, prompts.messages_w(r["fact_sheet"], r["question"], r["intent"], r.get("secondary"), a["text"]), args.max_len)
        if t:
            out.append((*t, "W"))
        else:
            skipped += 1
    print(f"examples: {sum(1 for x in out if x[2] == 'U')} U + {sum(1 for x in out if x[2] == 'W')} W; skipped (too long): {skipped}", flush=True)
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", required=True)
    ap.add_argument("--n-u", type=int, default=4000)
    ap.add_argument("--n-w", type=int, default=1600)
    ap.add_argument("--epochs", type=int, default=1)
    ap.add_argument("--lr", type=float, default=2e-4)
    ap.add_argument("--accum", type=int, default=16)
    ap.add_argument("--max-len", type=int, default=768)
    ap.add_argument("--seed", type=int, default=20261014)
    ap.add_argument("--save-every", type=int, default=25, help="optimizer steps between checkpoints")
    ap.add_argument("--threads", type=int, default=8)
    ap.add_argument("--device", default="auto", help="auto, cpu or cuda")
    args = ap.parse_args()
    dev = "cuda" if (args.device == "auto" and torch.cuda.is_available()) or args.device == "cuda" else "cpu"
    print(f"device: {dev}" + (f" ({torch.cuda.get_device_name(0)})" if dev == "cuda" else ""), flush=True)

    torch.manual_seed(args.seed)
    torch.set_num_threads(args.threads)
    out = RUNS / args.name
    out.mkdir(parents=True, exist_ok=True)
    rev = None if BASE != BASE_ID else REVISION
    tok = AutoTokenizer.from_pretrained(BASE, revision=rev)
    examples = build_examples(args, tok)
    random.Random(args.seed).shuffle(examples)
    steps_total = math.ceil(len(examples) * args.epochs / args.accum)

    # CPU: fp32 throughout. GPU: base weights in fp16 (1 GB, so a 4 GB card is enough), LoRA weights stay fp32 and a GradScaler guards the fp16 range.
    model = AutoModelForCausalLM.from_pretrained(BASE, torch_dtype=torch.float16 if dev == "cuda" else torch.float32, revision=rev)
    state_file = out / "state.json"
    done = 0
    if state_file.exists() and (out / "adapter").exists():
        model = PeftModel.from_pretrained(model, out / "adapter", is_trainable=True)
        done = json.loads(state_file.read_text())["optimizer_steps"]
        print(f"resuming from optimizer step {done}", flush=True)
    else:
        model = get_peft_model(model, LoraConfig(task_type="CAUSAL_LM", **LORA))
    model.to(dev)
    model.print_trainable_parameters()
    scaler = torch.amp.GradScaler("cuda", enabled=dev == "cuda")
    params = [p for p in model.parameters() if p.requires_grad]
    opt = torch.optim.AdamW(params, lr=args.lr, weight_decay=0.0)

    def lr_at(step: int) -> float:
        warm = max(1, int(0.05 * steps_total))
        if step < warm:
            return args.lr * (step + 1) / warm
        return 0.5 * args.lr * (1 + math.cos(math.pi * (step - warm) / max(1, steps_total - warm)))

    (out / "args.json").write_text(json.dumps({**vars(args), "base": BASE_ID, "base_revision": REVISION, "lora": LORA, "steps_total": steps_total,
                                               "data_sha256": hashlib.sha256((DATA / "train.jsonl").read_bytes()).hexdigest()}, indent=1), encoding="utf-8")
    model.train()
    order = [i for _ in range(args.epochs) for i in range(len(examples))]
    t0 = time.time()
    tokens_seen = 0
    losses: list[float] = []
    log = (out / "log.txt").open("a", encoding="utf-8")
    micro = done * args.accum
    while micro < len(order):
        for g in opt.param_groups:
            g["lr"] = lr_at(done)
        batch_loss = 0.0
        n = 0
        for _ in range(args.accum):
            if micro >= len(order):
                break
            ids, labels, kind = examples[order[micro]]
            ids, labels = ids.to(dev), labels.to(dev)
            with torch.autocast(device_type="cuda", dtype=torch.float16, enabled=dev == "cuda"):
                res = model(input_ids=ids, labels=labels)
            scaler.scale(res.loss / args.accum).backward()
            batch_loss += res.loss.item()
            tokens_seen += ids.shape[1]
            micro += 1
            n += 1
        scaler.unscale_(opt)
        torch.nn.utils.clip_grad_norm_(params, 1.0)
        scaler.step(opt)
        scaler.update()
        opt.zero_grad(set_to_none=True)
        done += 1
        losses.append(batch_loss / max(n, 1))
        el = time.time() - t0
        line = f"step {done}/{steps_total} loss {losses[-1]:.4f} lr {lr_at(done - 1):.2e} tokens/s {tokens_seen / el:.1f} elapsed {el / 60:.1f} min eta {(steps_total - done) * el / max(1, done - (done - len(losses))) / 60:.1f} min"
        print(line, flush=True)
        log.write(line + "\n")
        log.flush()
        if done % args.save_every == 0 or micro >= len(order):
            model.save_pretrained(out / "adapter")
            state_file.write_text(json.dumps({"optimizer_steps": done, "micro_steps": micro, "last_loss": losses[-1]}), encoding="utf-8")
    model.save_pretrained(out / "adapter")
    state_file.write_text(json.dumps({"optimizer_steps": done, "micro_steps": micro, "last_loss": losses[-1], "finished": True,
                                      "minutes": round((time.time() - t0) / 60, 1), "tokens_per_second": round(tokens_seen / (time.time() - t0), 1)}), encoding="utf-8")
    print("finished", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
