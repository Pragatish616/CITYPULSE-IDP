"""Zips what a free GPU machine (Colab, Kaggle) needs to train the route-question adapter: the scripts and the generated data, nothing
else. The base model is fetched there from the hub at the pinned revision. About 2 MB; synthetic data only, no user data.

    python ml/route_qa/package_for_gpu.py     ->  data/qa/2026-10-13/gpu_bundle.zip
"""

import hashlib
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "data" / "qa" / "2026-10-13" / "gpu_bundle.zip"
FILES = [
    "ml/__init__.py", "ml/route_qa/__init__.py", "ml/route_qa/prompts.py", "ml/route_qa/train_lora.py", "ml/route_qa/eval_model.py",
    "ml/route_qa/GPU_RUN.md", "data/qa/2026-10-13/generated/train.jsonl", "data/qa/2026-10-13/generated/val.jsonl",
    "data/qa/2026-10-13/generated/stats.json",
]


def main() -> None:
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as z:
        for f in FILES:
            z.write(ROOT / f, f)
    print(f"{OUT} {OUT.stat().st_size / 1e6:.1f} MB sha256 {hashlib.sha256(OUT.read_bytes()).hexdigest()}")


if __name__ == "__main__":
    main()
