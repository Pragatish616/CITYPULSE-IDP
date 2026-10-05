"""Where field-log entries are kept: an append-only JSON-lines log (ADR-028).

One line per entry, one file per UTC day of `received_at`. Appending is the only write: an entry is never edited or deleted here, the same
rule as the observation log (ADR-008). Each append is flushed and fsynced before the call returns, so an entry the server acknowledged
survives a crash or a restart of the process. The files live in `FIELDLOG_DIR`.

**What this does not give you:** durability beyond the disk. On a free host the disk is wiped on every deploy and restart. For research
ground truth that is not acceptable, so the server says so loudly (`/fieldlog/health`), the phone page keeps its own durable copy until the
server has acknowledged it, and an operator exports the log (admin token) regularly. A persistent disk or a database is the real fix and
needs an account the owner creates.
"""

from __future__ import annotations

import os
import threading
from collections.abc import Iterator
from datetime import datetime, timezone
from pathlib import Path

from app.fieldlog.models import StoredEntry


class Conflict(Exception):
    """The same entry_id arrived again with different content."""


class FieldLogStore:
    """Append-only JSONL store with an in-memory index of entry ids."""

    def __init__(self, directory: Path | str) -> None:
        self.dir = Path(directory)
        self.dir.mkdir(parents=True, exist_ok=True)
        self._lock = threading.Lock()
        self._index: dict[str, tuple] = {}
        self._corrupt_lines = 0
        self._load()

    def _files(self) -> list[Path]:
        return sorted(self.dir.glob("fieldlog-*.jsonl"))

    def _load(self) -> None:
        for path in self._files():
            with path.open("r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        entry = StoredEntry.model_validate_json(line)
                    except ValueError:
                        # A torn last line after a crash: skip it, count it, never fail to start over one bad line.
                        self._corrupt_lines += 1
                        continue
                    self._index[str(entry.entry_id)] = entry.content_key()

    @property
    def corrupt_lines(self) -> int:
        return self._corrupt_lines

    def __len__(self) -> int:
        return len(self._index)

    def add(self, entry: StoredEntry) -> bool:
        """Store `entry`. True if newly stored, False if it was an identical repeat. Raises Conflict on a different entry with the same id."""
        key = str(entry.entry_id)
        with self._lock:
            existing = self._index.get(key)
            if existing is not None:
                if existing == entry.content_key():
                    return False
                raise Conflict(key)
            path = (
                self.dir
                / f"fieldlog-{entry.received_at.astimezone(timezone.utc):%Y-%m-%d}.jsonl"
            )
            line = entry.model_dump_json() + "\n"
            with path.open("a", encoding="utf-8", newline="\n") as f:
                f.write(line)
                f.flush()
                os.fsync(f.fileno())
            self._index[key] = entry.content_key()
            return True

    def iter_entries(self, since: datetime | None = None) -> Iterator[StoredEntry]:
        """All stored entries, oldest file first. `since` filters on received_at."""
        for path in self._files():
            with path.open("r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        entry = StoredEntry.model_validate_json(line)
                    except ValueError:
                        continue
                    if since is None or entry.received_at >= since:
                        yield entry

    def counts_by_volunteer(self) -> dict[str, int]:
        out: dict[str, int] = {}
        for e in self.iter_entries():
            out[e.volunteer] = out.get(e.volunteer, 0) + 1
        return out


def to_csv_row(e: StoredEntry) -> list[str]:
    """One CSV row. Cells that a spreadsheet could read as a formula are prefixed with an apostrophe."""

    def safe(v: object) -> str:
        s = "" if v is None else str(v)
        return "'" + s if s[:1] in ("=", "+", "-", "@", "\t", "\r") else s

    return [
        safe(e.protocol),
        safe(e.entry_id),
        safe(e.site_id),
        safe(e.state.value),
        safe(e.observed_at.isoformat()),
        safe(e.depth_band.value if e.depth_band else ""),
        safe(e.lat),
        safe(e.lon),
        safe(e.volunteer),
        safe(e.received_at.isoformat()),
        safe(e.lag_seconds),
        safe(e.client),
    ]


CSV_HEADER = [
    "protocol",
    "entry_id",
    "site_id",
    "state",
    "observed_at_utc",
    "depth_band",
    "lat",
    "lon",
    "volunteer",
    "received_at_utc",
    "lag_seconds",
    "client",
]
