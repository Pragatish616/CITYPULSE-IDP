"""In-process pub/sub used to push newly-ingested observations to connected SSE clients.

This is intentionally simple: one process, one set of `asyncio.Queue` subscribers. It is
enough for local dev, tests, and a single-instance deployment (Render/Koyeb free tier is one
instance). It does not fan out across multiple server processes/instances — a real multi-
instance deployment would need Postgres LISTEN/NOTIFY or Redis pub/sub for that, which is not
built here (out of T5.3's scope; flagged for whoever picks up multi-instance deployment).
"""

from __future__ import annotations

import asyncio
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from app.models import HazardObservation


class ObservationBroadcaster:
    def __init__(self) -> None:
        self._subscribers: set[asyncio.Queue[HazardObservation]] = set()

    @asynccontextmanager
    async def subscribe(self) -> AsyncIterator[asyncio.Queue[HazardObservation]]:
        queue: asyncio.Queue[HazardObservation] = asyncio.Queue()
        self._subscribers.add(queue)
        try:
            yield queue
        finally:
            self._subscribers.discard(queue)

    async def publish(self, obs: HazardObservation) -> None:
        for queue in list(self._subscribers):
            await queue.put(obs)

    @property
    def subscriber_count(self) -> int:
        return len(self._subscribers)
