# Training the route-question adapter on a GPU

This laptop trains at about 13 tokens a second on its CPU (measured on 14 October 2026), so the planned run (about 680,000 tokens) would take
about 14 hours. A GPU does it in minutes. Two ways; both use the same scripts and the same pinned base model
(`Qwen/Qwen2.5-0.5B-Instruct`, revision `7ae557604adf67be50417f59c2c2f167def9a775`, Apache-2.0).

## A. A free Colab or Kaggle GPU (you run it)

1. On the laptop: `python ml/route_qa/package_for_gpu.py` makes `data/qa/2026-10-13/gpu_bundle.zip` (about 2 MB; synthetic data only).
2. In Colab (Runtime, then Change runtime type, then T4 GPU) or a Kaggle notebook with a GPU: upload the zip, then run

   ```
   !unzip -q gpu_bundle.zip -d /content/bundle
   %cd /content/bundle
   !pip install -q peft accelerate transformers
   !python ml/route_qa/train_lora.py --name run1 --n-u 4000 --n-w 1600 --epochs 1
   !python ml/route_qa/eval_model.py --run run1 --n-u 300 --n-w 60
   ```

3. Download the folder `data/qa/2026-10-13/runs/run1/` (the `adapter` folder, `args.json`, `log.txt`, `eval.json`, `w_answers.jsonl`) and put it in
   the same place on the laptop. The Dart verifier is not on Colab, so the model's answers are verified on the laptop:

   ```
   cd packages/pulse_explain
   dart run tool/verify_answers.dart ../../data/qa/2026-10-13/runs/run1/w_answers.jsonl ../../data/qa/2026-10-13/runs/run1/w_verified.jsonl
   ```

4. Tell me; I read the results and write them up, whatever they are.

The sizes (4000 and 1600) are the plan for a GPU run. The settings in the pre-registration's addendum 2 are not changed after seeing results.

## B. The laptop's own GTX 1650 (4 GB)

The installed PyTorch is the CPU build. The CUDA build is a download of about 2.5 GB that needs roughly 7 GB free on C: while it installs (this
machine had 2.5 GB free on 14 October). With that space, in a separate environment:

```
python -m venv C:\Users\nprag\AppData\Local\citypulse_trainenv
C:\Users\nprag\AppData\Local\citypulse_trainenv\Scripts\pip install torch --index-url https://download.pytorch.org/whl/cu126
C:\Users\nprag\AppData\Local\citypulse_trainenv\Scripts\pip install transformers peft accelerate
```

then the same two commands. The scripts pick the GPU on their own (`--device auto`) and use fp16 there. The GPU path is untested on this machine.
