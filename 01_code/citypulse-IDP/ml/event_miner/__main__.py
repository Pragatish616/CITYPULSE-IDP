"""Operator commands for the event miner (ADR-030). Run from 01_code/citypulse-IDP with Ollama running:

    python -m ml.event_miner check
    python -m ml.event_miner mine --text-file post.txt --source "GCC (pasted)" --url https://... --published 2023-12-04T10:00+05:30
    python -m ml.event_miner pending
    python -m ml.event_miner places "ganesapuram"
    python -m ml.event_miner decide ITEM_ID 0 accept --reviewer v01
    python -m ml.event_miner decide ITEM_ID 0 correct --condition closed --place place:perambur --reviewer v01
    python -m ml.event_miner export --out exports/miner.csv
    python -m ml.event_miner evaluate --labels data/miner/labels.jsonl
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from ml.event_miner import evaluate as ev
from ml.event_miner.gazetteer import Retriever, load_places
from ml.event_miner.llm import LLMError, OllamaClient
from ml.event_miner.miner import mine_item
from ml.event_miner.schema import SourceItem
from ml.event_miner.store import DEFAULT_DIR, MinerStore

CACHE = DEFAULT_DIR / "gazetteer_embeddings.npz"


def _retriever(client: OllamaClient, use_embed: bool) -> Retriever:
    return Retriever(load_places(), embed=client.embed if use_embed else None, cache_file=CACHE if use_embed else None)


def cmd_check(args: argparse.Namespace, client: OllamaClient) -> int:
    places = load_places()
    print(f"gazetteer: {len(places)} places ({sum(1 for p in places if p.id.startswith('place:'))} OSM places, "
          f"{sum(1 for p in places if not p.id.startswith('place:'))} named candidate sites)")
    ok = True
    for model in (client.model, client.embed_model):
        d = client.digest(model)
        print(f"{model}: {'present, digest ' + d[:12] if d else 'NOT FOUND (ollama pull ' + model + ')'}")
        ok &= d is not None
    print(f"store: {DEFAULT_DIR} (git-ignored)")
    return 0 if ok else 1


def _print_item(item, places_by_id) -> None:
    print(f"item {item.item_id}  [{item.language}]  {item.source.source_name}  {item.source.published_at.isoformat()}  "
          f"{item.seconds:.1f} s")
    for e in item.events:
        chosen = places_by_id.get(e.chosen_place_id) if e.chosen_place_id else None
        where = f"{chosen.name} ({e.chosen_place_id})" if chosen else "no gazetteer match"
        dup = f"  DUPLICATE of {e.duplicate_of}" if e.duplicate_of else ""
        print(f"  [{e.index}] {e.condition:8s} {e.place_text!r} -> {where}{dup}")
        print(f"      quote: {e.quote!r}")
        if e.time_text or e.depth_words:
            print(f"      time: {e.time_text!r}  depth: {e.depth_words!r}")
        print("      candidates: " + "; ".join(f"{c.name} [{c.id}]" for c in e.candidates))
    for d in item.dropped:
        print(f"  dropped ({d.reason}): {json.dumps(d.event, ensure_ascii=False)[:160]}")
    if not item.events and not item.dropped:
        print("  no street-level event found")


def cmd_mine(args: argparse.Namespace, client: OllamaClient) -> int:
    text = Path(args.text_file).read_text(encoding="utf-8") if args.text_file else args.text
    if not text:
        print("give --text or --text-file")
        return 2
    item = SourceItem(text=text, source_url=args.url or "", source_name=args.source, published_at=args.published)
    store = MinerStore()
    if store.has(item.item_id) and not args.again:
        print(f"item {item.item_id} was mined before; use --again to mine it again")
        return 1
    retriever = _retriever(client, not args.no_embed)
    mined = store.add(mine_item(client, retriever, item, client.digest(client.model)))
    _print_item(mined, {p.id: p for p in retriever.places})
    print("Nothing is used until a person reviews it: python -m ml.event_miner pending")
    return 0


def cmd_pending(args: argparse.Namespace, client: OllamaClient) -> int:
    store = MinerStore()
    places = {p.id: p for p in load_places()}
    pend = store.pending()
    if not pend:
        print("nothing waiting for review")
        return 0
    shown = set()
    for item, _ in pend:
        if item.item_id in shown:
            continue
        shown.add(item.item_id)
        _print_item(item, places)
        print(f"  source text: {item.source.text[:400]!r}")
    print(f"\n{len(pend)} event(s) waiting. decide ITEM INDEX accept|reject|correct --reviewer CODE")
    return 0


def cmd_places(args: argparse.Namespace, client: OllamaClient) -> int:
    for c in Retriever(load_places()).top(args.query, k=args.k):
        print(f"{c.id:40s} {c.name}  ({c.kind}, {c.lat:.5f}, {c.lon:.5f})")
    return 0


def cmd_decide(args: argparse.Namespace, client: OllamaClient) -> int:
    places = {p.id: p for p in load_places()}
    try:
        d = MinerStore().decide(args.item_id, args.index, args.action, args.reviewer, places,
                                place_id=args.place, condition=args.condition, note=args.note or "")
    except (KeyError, ValueError) as exc:
        print(f"refused: {exc}")
        return 1
    print(f"recorded: {d.action} {d.item_id}:{d.index} by {d.reviewer} at {d.decided_at.isoformat()}")
    return 0


def cmd_export(args: argparse.Namespace, client: OllamaClient) -> int:
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    text = MinerStore().export_csv({p.id: p for p in load_places()})
    out.write_text(text, encoding="utf-8")
    print(f"wrote {out} ({len(text.splitlines()) - 1} reviewed event(s)). It holds quotes from the sources: keep it out of Git.")
    return 0


def cmd_evaluate(args: argparse.Namespace, client: OllamaClient) -> int:
    result = ev.run(Path(args.labels), client, _retriever(client, not args.no_embed))
    print(json.dumps({k: result[k] for k in ("meets_preregistered_size", "overall", "by_language")}, indent=1,
                     ensure_ascii=False))
    return 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="python -m ml.event_miner", description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("check", help="is Ollama up, are the models there")
    m = sub.add_parser("mine", help="mine one post or news paragraph")
    m.add_argument("--text")
    m.add_argument("--text-file")
    m.add_argument("--source", required=True, help="who published it, for example 'Greater Chennai Traffic Police (pasted)'")
    m.add_argument("--url", help="link to the original")
    m.add_argument("--published", required=True, help="publication time with zone, for example 2023-12-04T10:00+05:30")
    m.add_argument("--no-embed", action="store_true", help="lexical place matching only")
    m.add_argument("--again", action="store_true", help="mine an item that was mined before")
    sub.add_parser("pending", help="events waiting for review")
    p = sub.add_parser("places", help="search the gazetteer for a place id")
    p.add_argument("query")
    p.add_argument("-k", type=int, default=8)
    d = sub.add_parser("decide", help="accept, reject or correct one event")
    d.add_argument("item_id")
    d.add_argument("index", type=int)
    d.add_argument("action", choices=["accept", "reject", "correct"])
    d.add_argument("--reviewer", required=True)
    d.add_argument("--place", help="corrected place id (see `places`), or none")
    d.add_argument("--condition", choices=["flooded", "closed", "cleared", "unknown"])
    d.add_argument("--note")
    e = sub.add_parser("export", help="reviewed events as CSV")
    e.add_argument("--out", required=True)
    v = sub.add_parser("evaluate", help="the pre-registered evaluation against hand labels")
    v.add_argument("--labels", required=True)
    v.add_argument("--no-embed", action="store_true")
    args = ap.parse_args(argv)
    # Tamil text on a Windows console: print as UTF-8 instead of failing on the code page.
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="replace")
    client = OllamaClient()
    try:
        return {
            "check": cmd_check, "mine": cmd_mine, "pending": cmd_pending, "places": cmd_places, "decide": cmd_decide,
            "export": cmd_export, "evaluate": cmd_evaluate,
        }[args.cmd](args, client)
    except LLMError as exc:
        print(f"model error: {exc}")
        return 3
    finally:
        client.close()


if __name__ == "__main__":
    sys.exit(main())
