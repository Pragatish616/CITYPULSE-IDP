"""Append-only files for mined items and review decisions (ADR-030). Nothing is edited or deleted; the latest decision wins.

Lives in data/miner/ (git-ignored): source texts are copyrighted and posts can name people.
"""

from __future__ import annotations

import csv
import io
import json
import os
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Literal

from pydantic import BaseModel, Field

from ml.event_miner.gazetteer import Place
from ml.event_miner.schema import CONDITIONS, MinedItem

# MINER_DIR moves the store (for example for trial runs that must not enter the real review queue).
DEFAULT_DIR = Path(os.environ.get("MINER_DIR") or Path(__file__).resolve().parents[2] / "data" / "miner")
DUPLICATE_WINDOW = timedelta(hours=6)
Action = Literal["accept", "reject", "correct"]


class Decision(BaseModel):
    item_id: str
    index: int
    action: Action
    reviewer: str = Field(pattern=r"^[A-Za-z0-9_-]{2,24}$")
    place_id: str | None = None
    condition: str | None = None
    note: str = Field(default="", max_length=300)
    decided_at: datetime


class MinerStore:
    def __init__(self, directory: Path | str = DEFAULT_DIR) -> None:
        self.dir = Path(directory)
        self.dir.mkdir(parents=True, exist_ok=True)
        self.items_file = self.dir / "items.jsonl"
        self.decisions_file = self.dir / "decisions.jsonl"

    # ---- reading

    def items(self) -> list[MinedItem]:
        if not self.items_file.exists():
            return []
        out = []
        for line in self.items_file.read_text(encoding="utf-8").splitlines():
            if line.strip():
                out.append(MinedItem.model_validate_json(line))
        return out

    def decisions(self) -> dict[tuple[str, int], Decision]:
        """The latest decision per event."""
        latest: dict[tuple[str, int], Decision] = {}
        if self.decisions_file.exists():
            for line in self.decisions_file.read_text(encoding="utf-8").splitlines():
                if line.strip():
                    d = Decision.model_validate_json(line)
                    latest[(d.item_id, d.index)] = d
        return latest

    def has(self, item_id: str) -> bool:
        return any(i.item_id == item_id for i in self.items())

    # ---- writing

    def _append(self, path: Path, line: str) -> None:
        with path.open("a", encoding="utf-8", newline="\n") as f:
            f.write(line + "\n")
            f.flush()
            os.fsync(f.fileno())

    def add(self, item: MinedItem) -> MinedItem:
        """Stores a mined item, marking events that repeat an earlier one (same place, condition and source within 6 hours)."""
        earlier = self.items()
        for ev in item.events:
            if ev.chosen_place_id is None:
                continue
            for old in earlier:
                if old.source.source_name != item.source.source_name:
                    continue
                if abs(old.source.published_at - item.source.published_at) > DUPLICATE_WINDOW:
                    continue
                match = next(
                    (o for o in old.events if o.chosen_place_id == ev.chosen_place_id and o.condition == ev.condition),
                    None,
                )
                if match is not None:
                    ev.duplicate_of = f"{old.item_id}:{match.index}"
                    break
        self._append(self.items_file, item.model_dump_json())
        return item

    def decide(
        self,
        item_id: str,
        index: int,
        action: Action,
        reviewer: str,
        places: dict[str, Place],
        place_id: str | None = None,
        condition: str | None = None,
        note: str = "",
        now: datetime | None = None,
    ) -> Decision:
        item = next((i for i in self.items() if i.item_id == item_id), None)
        if item is None or not any(e.index == index for e in item.events):
            raise KeyError(f"no event {item_id}:{index}")
        if action == "correct":
            if place_id is None and condition is None:
                raise ValueError("a correction needs a place id, a condition, or both")
            if place_id is not None and place_id != "none" and place_id not in places:
                raise ValueError(f"{place_id} is not in the gazetteer")
            if condition is not None and condition not in CONDITIONS:
                raise ValueError(f"condition must be one of {', '.join(CONDITIONS)}")
        elif place_id is not None or condition is not None:
            raise ValueError("only a correction carries a place or a condition")
        d = Decision(
            item_id=item_id, index=index, action=action, reviewer=reviewer, place_id=place_id, condition=condition,
            note=note, decided_at=now or datetime.now(timezone.utc),
        )
        self._append(self.decisions_file, d.model_dump_json())
        return d

    # ---- views

    def pending(self) -> list[tuple[MinedItem, int]]:
        decided = self.decisions()
        return [(i, e.index) for i in self.items() for e in i.events if (i.item_id, e.index) not in decided]

    def export_csv(self, places: dict[str, Place]) -> str:
        """Accepted and corrected events, with the reviewer's place and condition where corrected. Formula-safe."""
        header = [
            "item_id", "index", "source_name", "source_url", "published_at_utc", "language", "place_text", "place_id",
            "place_name", "lat", "lon", "condition", "time_text", "depth_words", "quote", "decision", "reviewer",
            "decided_at_utc", "duplicate_of", "model", "model_digest", "prompt_version",
        ]
        buf = io.StringIO()
        w = csv.writer(buf, lineterminator="\n")
        w.writerow(header)
        decided = self.decisions()
        for item in self.items():
            for ev in item.events:
                d = decided.get((item.item_id, ev.index))
                if d is None or d.action == "reject":
                    continue
                pid = d.place_id if d.action == "correct" and d.place_id is not None else ev.chosen_place_id
                pid = None if pid == "none" else pid
                place = places.get(pid) if pid else None
                cond = d.condition if d.action == "correct" and d.condition else ev.condition
                row = [
                    item.item_id, ev.index, item.source.source_name, item.source.source_url,
                    item.source.published_at.isoformat(), item.language, ev.place_text, pid or "",
                    place.name if place else "", place.lat if place else "", place.lon if place else "", cond,
                    ev.time_text, ev.depth_words, ev.quote, d.action, d.reviewer, d.decided_at.isoformat(),
                    ev.duplicate_of or "", item.model, item.model_digest or "", item.prompt_version,
                ]
                w.writerow([_safe(v) for v in row])
        return buf.getvalue()


def _safe(v: object) -> object:
    if isinstance(v, str) and v[:1] in ("=", "+", "-", "@", "\t", "\r"):
        return "'" + v
    return v


def load_items_jsonl(text: str) -> list[dict]:
    return [json.loads(line) for line in text.splitlines() if line.strip()]
