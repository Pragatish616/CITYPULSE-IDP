"""The pre-registered evaluation of ADR-030. Labels are written by a person BEFORE the miner sees the items.

Label file: JSON Lines, one item per line:
    {"text": "...", "source_name": "...", "source_url": "...", "published_at": "2023-12-04T10:00+05:30",
     "language": "en" | "ta" (optional; otherwise guessed from the script), "labeller": "v01",
     "events": [{"place_id": "place:velachery" | null, "place_text": "...", "condition": "closed", "time_stated": true}],
     "second_labeller": "v02", "second_events": [...]}            (the second pair only on the independently re-labelled fifth)

Writes the aggregate numbers to data/results/<date>-event-miner-eval/result.json (no source text, no quotes) and the per-item
detail, which holds quotes, to data/miner/eval/<date>.jsonl (git-ignored).
"""

from __future__ import annotations

import json
import statistics
import subprocess
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from ml.event_miner.gazetteer import Place, Retriever, distance_m
from ml.event_miner.llm import OllamaClient
from ml.event_miner.miner import mine_item
from ml.event_miner.schema import CONDITIONS, MinedItem, SourceItem
from ml.event_miner.text import name_key

ROOT = Path(__file__).resolve().parents[2]
MIN_ITEMS = 100
BAR_PRECISION, BAR_RECALL = 0.7, 0.6
WITHIN_M = 200.0


def _same_place_text(a: str, b: str) -> bool:
    ka, kb = name_key(a), name_key(b)
    return bool(ka and kb) and (ka in kb or kb in ka)


def match_events(gold: list[dict], mined: list[dict]) -> tuple[int, list[tuple[int, int]]]:
    """One-to-one, greedy in label order. A mined event matches a gold event when the condition is the same and the place is the
    same: the same gazetteer id, or both `none` with one place text contained in the other (an automatic stand-in for the
    labeller's judgement; such pairs are listed for a person to check)."""
    used: set[int] = set()
    pairs: list[tuple[int, int]] = []
    for gi, g in enumerate(gold):
        for mi, m in enumerate(mined):
            if mi in used or m["condition"] != g["condition"]:
                continue
            if g.get("place_id"):
                ok = m.get("place_id") == g["place_id"]
            else:
                ok = m.get("place_id") is None and _same_place_text(g.get("place_text", ""), m.get("place_text", ""))
            if ok:
                used.add(mi)
                pairs.append((gi, mi))
                break
    return len(pairs), pairs


def _share(n: int, d: int) -> float | None:
    return round(n / d, 4) if d else None


def score(rows: list[dict], places: dict[str, Place]) -> dict[str, Any]:
    """rows: one per item with `gold` events, `mined` events ({place_id, place_text, condition}), `dropped` count, `seconds`."""
    tp = sum(r["tp"] for r in rows)
    mined_n = sum(len(r["mined"]) for r in rows)
    gold_n = sum(len(r["gold"]) for r in rows)
    with_id = [(r, g) for r in rows for g in r["gold"] if g.get("place_id")]
    place_hit = place_near = cond_ok = cond_n = 0
    for r, g in with_id:
        same = [m for m in r["mined"] if m.get("place_id") == g["place_id"]]
        if same:
            place_hit += 1
            cond_n += 1
            cond_ok += any(m["condition"] == g["condition"] for m in same)
        gp = places.get(g["place_id"])
        if gp and any(
            m.get("place_id") in places
            and distance_m(gp.lat, gp.lon, places[m["place_id"]].lat, places[m["place_id"]].lon) <= WITHIN_M
            for m in r["mined"]
        ):
            place_near += 1
    dropped = sum(r["dropped"] for r in rows)
    secs = [r["seconds"] for r in rows]
    precision, recall = _share(tp, mined_n), _share(tp, gold_n)
    return {
        "items": len(rows),
        "gold_events": gold_n,
        "mined_events": mined_n,
        "matched_events": tp,
        "precision": precision,
        "recall": recall,
        "gold_events_with_gazetteer_id": len(with_id),
        "place_accuracy": _share(place_hit, len(with_id)),
        "place_within_200m": _share(place_near, len(with_id)),
        "condition_accuracy_when_place_matched": _share(cond_ok, cond_n),
        "events_dropped_by_quote_rule": dropped,
        "share_dropped_by_quote_rule": _share(dropped, dropped + mined_n),
        "share_gold_events_not_in_gazetteer": _share(gold_n - len(with_id), gold_n),
        "items_with_no_gold_event": sum(1 for r in rows if not r["gold"]),
        "items_with_no_gold_event_but_something_mined": sum(1 for r in rows if not r["gold"] and r["mined"]),
        "gold_conditions": dict(Counter(g["condition"] for r in rows for g in r["gold"])),
        "mined_conditions": dict(Counter(m["condition"] for r in rows for m in r["mined"])),
        "seconds_per_item": {
            "mean": round(statistics.fmean(secs), 2) if secs else None,
            "median": round(statistics.median(secs), 2) if secs else None,
            "max": round(max(secs), 2) if secs else None,
        },
        "useful_for_suggestions": (
            None if precision is None or recall is None else precision >= BAR_PRECISION and recall >= BAR_RECALL
        ),
    }


def agreement(labels: list[dict]) -> dict[str, Any]:
    """Between the two labellers on the re-labelled items: identical event sets, and event-level F1."""
    pairs = [lab for lab in labels if lab.get("second_events") is not None]
    identical = 0
    tp = n1 = n2 = 0
    for lab in pairs:
        a = [{"place_id": e.get("place_id"), "place_text": e.get("place_text", ""), "condition": e["condition"]}
             for e in lab["events"]]
        b = [{"place_id": e.get("place_id"), "place_text": e.get("place_text", ""), "condition": e["condition"]}
             for e in lab["second_events"]]
        m, _ = match_events(a, b)
        tp, n1, n2 = tp + m, n1 + len(a), n2 + len(b)
        identical += m == len(a) == len(b)
    f1 = round(2 * tp / (n1 + n2), 4) if (n1 + n2) else None
    return {"items_labelled_twice": len(pairs), "identical_label_sets": identical, "event_f1_between_labellers": f1}


def validate_labels(labels: list[dict], places: dict[str, Place]) -> None:
    for n, lab in enumerate(labels, 1):
        for key in ("events", "second_events"):
            for e in lab.get(key) or []:
                if e.get("condition") not in CONDITIONS:
                    raise ValueError(f"line {n}: condition {e.get('condition')!r} is not one of {CONDITIONS}")
                pid = e.get("place_id")
                if pid and pid not in places:
                    raise ValueError(f"line {n}: place_id {pid!r} is not in the gazetteer")
                if not pid and not e.get("place_text"):
                    raise ValueError(f"line {n}: an event without a place id needs place_text")


def run(
    labels_file: Path,
    client: OllamaClient,
    retriever: Retriever,
    out_dir: Path | None = None,
    detail_dir: Path | None = None,
    today: str | None = None,
) -> dict[str, Any]:
    places = {p.id: p for p in retriever.places}
    labels = [json.loads(line) for line in labels_file.read_text(encoding="utf-8").splitlines() if line.strip()]
    validate_labels(labels, places)
    digest = client.digest(client.model)
    rows, detail = [], []
    for lab in labels:
        item = SourceItem(
            text=lab["text"], source_url=lab.get("source_url", ""), source_name=lab["source_name"],
            published_at=lab["published_at"],
        )
        mined: MinedItem = mine_item(client, retriever, item, digest)
        m = [{"place_id": e.chosen_place_id, "place_text": e.place_text, "condition": e.condition} for e in mined.events]
        tp, pairs = match_events(lab["events"], m)
        rows.append({
            "item_id": item.item_id, "language": lab.get("language") or item.language, "gold": lab["events"],
            "mined": m, "tp": tp, "dropped": len(mined.dropped), "seconds": mined.seconds,
        })
        detail.append({**json.loads(mined.model_dump_json()), "gold": lab["events"], "matched_pairs": pairs})
    by_lang = {lang: score([r for r in rows if r["language"] == lang], places) for lang in sorted({r["language"] for r in rows})}
    today = today or datetime.now(timezone.utc).strftime("%Y-%m-%d")
    result = {
        "task": "ADR-030 evaluation: event miner against hand labels",
        "run_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "code_commit": subprocess.run(["git", "rev-parse", "HEAD"], capture_output=True, text=True, cwd=ROOT,
                                      check=False).stdout.strip(),
        "model": client.model,
        "model_digest": digest,
        "embed_model": client.embed_model if retriever.embed is not None else None,
        "labels_file_items": len(labels),
        "meets_preregistered_size": len(labels) >= MIN_ITEMS,
        "bar": {"precision_at_least": BAR_PRECISION, "recall_at_least": BAR_RECALL},
        "overall": score(rows, places),
        "by_language": by_lang,
        "labeller_agreement": agreement(labels),
        "note": (
            "Matches of events without a gazetteer id use place-text containment as a stand-in for the labeller's judgement; "
            "the pairs are in the local detail file for a person to check."
        ),
    }
    out_dir = out_dir or ROOT / "data" / "results" / f"{today}-event-miner-eval"
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "result.json").write_text(json.dumps(result, indent=1, ensure_ascii=False), encoding="utf-8")
    detail_dir = detail_dir or ROOT / "data" / "miner" / "eval"
    detail_dir.mkdir(parents=True, exist_ok=True)
    (detail_dir / f"{today}.jsonl").write_text(
        "\n".join(json.dumps(d, ensure_ascii=False, default=str) for d in detail) + "\n", encoding="utf-8"
    )
    return result
