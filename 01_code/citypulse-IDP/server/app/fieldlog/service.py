"""Field-log service: sites, volunteer tokens, throttling and the store, bundled so the router stays thin (ADR-028).

Secrets come from the environment and are never logged or returned:
- FIELDLOG_TOKENS       "code:token,code2:token2". One entry per volunteer; the code is the pseudonym kept with each entry. Tokens shorter
                        than 16 characters are refused (counted, not used). Unset or empty: logging is disabled (403), not open.
- FIELDLOG_ADMIN_TOKEN  Lets an operator read and export the log. Unset: reading is disabled.
- FIELDLOG_DIR          Where the log files go. Default: a folder in the system temp directory, which a free host wipes on restart.
- FIELDLOG_DURABLE      "1" only if the operator knows FIELDLOG_DIR is on a persistent disk. It changes what /fieldlog/health says, nothing else.
"""

from __future__ import annotations

import hmac
import json
import os
import tempfile
import threading
import time
from collections import defaultdict, deque
from collections.abc import Callable
from datetime import datetime, timezone
from pathlib import Path

from app.fieldlog.models import ADHOC_SITE, VOLUNTEER
from app.fieldlog.store import FieldLogStore

SITES_FILE = Path(__file__).with_name("sites.json")
MIN_TOKEN_LENGTH = 16


class TokenBook:
    """Volunteer tokens. Lookups compare against every token in constant time so the answer does not leak how much of a token matched."""

    def __init__(self, spec: str | None) -> None:
        self._tokens: list[tuple[str, str]] = []
        self.refused = 0
        for part in (spec or "").split(","):
            part = part.strip()
            if not part:
                continue
            code, sep, token = part.partition(":")
            code, token = code.strip(), token.strip()
            if not sep or not VOLUNTEER.match(code) or len(token) < MIN_TOKEN_LENGTH:
                self.refused += 1
                continue
            self._tokens.append((code, token))

    def __len__(self) -> int:
        return len(self._tokens)

    def identify(self, presented: str | None) -> str | None:
        if not presented:
            return None
        found = None
        for code, token in self._tokens:
            if hmac.compare_digest(presented.encode("utf-8"), token.encode("utf-8")):
                found = code
        return found


class Window:
    """Sliding-window counter per key."""

    def __init__(
        self, limit: int, seconds: float, clock: Callable[[], float] = time.monotonic
    ) -> None:
        self.limit, self.seconds, self._clock = limit, seconds, clock
        self._hits: dict[str, deque[float]] = defaultdict(deque)
        self._lock = threading.Lock()

    def _trim(self, q: deque[float], now: float) -> None:
        while q and now - q[0] > self.seconds:
            q.popleft()

    def allow(self, key: str) -> bool:
        """Count a hit; False if the key is over its limit (the hit is not counted then)."""
        now = self._clock()
        with self._lock:
            q = self._hits[key]
            self._trim(q, now)
            if len(q) >= self.limit:
                return False
            q.append(now)
            return True

    def over(self, key: str) -> bool:
        """Whether the key is already at its limit, without counting."""
        now = self._clock()
        with self._lock:
            q = self._hits[key]
            self._trim(q, now)
            return len(q) >= self.limit

    def hit(self, key: str) -> None:
        with self._lock:
            self._hits[key].append(self._clock())


class FieldLogService:
    def __init__(
        self,
        *,
        directory: Path | str | None = None,
        tokens: str | None = None,
        admin_token: str | None = None,
        durable: bool = False,
        now: Callable[[], datetime] | None = None,
        sites_file: Path = SITES_FILE,
    ) -> None:
        self.now = now or (lambda: datetime.now(timezone.utc))
        self.tokens = TokenBook(tokens)
        self.admin_token = (
            admin_token
            if admin_token and len(admin_token) >= MIN_TOKEN_LENGTH
            else None
        )
        self.admin_token_refused = bool(admin_token) and self.admin_token is None
        self.durable = durable
        self.store = FieldLogStore(
            directory or Path(tempfile.gettempdir()) / "citypulse-fieldlog"
        )
        doc = json.loads(sites_file.read_text(encoding="utf-8"))
        self.sites_doc = doc
        self.site_ids = {s["id"] for s in doc["sites"]}
        # per volunteer: bursts of a queue syncing, but not a script; per address: wrong tokens
        self.by_volunteer_hour = Window(300, 3600)
        self.by_volunteer_day = Window(2000, 86400)
        self.bad_auth = Window(30, 600)

    @classmethod
    def from_env(cls, env: dict[str, str] | None = None) -> FieldLogService:
        e = os.environ if env is None else env
        return cls(
            directory=e.get("FIELDLOG_DIR") or None,
            tokens=e.get("FIELDLOG_TOKENS"),
            admin_token=e.get("FIELDLOG_ADMIN_TOKEN"),
            durable=e.get("FIELDLOG_DURABLE") == "1",
        )

    @property
    def enabled(self) -> bool:
        return len(self.tokens) > 0

    def known_site(self, site_id: str) -> bool:
        return site_id == ADHOC_SITE or site_id in self.site_ids

    def admin_ok(self, presented: str | None) -> bool:
        return bool(
            self.admin_token
            and presented
            and hmac.compare_digest(
                presented.encode("utf-8"), self.admin_token.encode("utf-8")
            )
        )

    def health(self) -> dict:
        return {
            "enabled": self.enabled,
            "volunteers_configured": len(self.tokens),
            "tokens_refused_as_too_weak_or_malformed": self.tokens.refused,
            "admin_token_configured": self.admin_token is not None,
            "sites": len(self.site_ids),
            "entries": len(self.store),
            "corrupt_lines_skipped": self.store.corrupt_lines,
            "durable": self.durable,
            "durability_note": (
                "The operator says the log directory is on a persistent disk."
                if self.durable
                else "The log directory is NOT known to be persistent: on a free host it is wiped by a restart or a deploy. Export regularly."
            ),
        }
