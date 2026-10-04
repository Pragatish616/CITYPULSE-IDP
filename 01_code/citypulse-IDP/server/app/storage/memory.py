"""In-process store. Default backend — no external dependency, used in tests and local dev
whenever SUPABASE_URL is unset (see `factory.get_repository`).
"""

from __future__ import annotations

import asyncio
from datetime import datetime
from uuid import UUID

from app.models import HazardObservation
from app.storage.base import BBox, ObservationRepository


class InMemoryObservationRepository(ObservationRepository):
    def __init__(self) -> None:
        self._store: dict[UUID, HazardObservation] = {}
        self._lock = asyncio.Lock()

    async def add_observation(self, obs: HazardObservation) -> bool:
        async with self._lock:
            if obs.id in self._store:
                return False
            self._store[obs.id] = obs
            return True

    async def get_observations(
        self,
        bbox: BBox | None = None,
        since: datetime | None = None,
        until: datetime | None = None,
        received_since: datetime | None = None,
    ) -> list[HazardObservation]:
        async with self._lock:
            results = list(self._store.values())

        if bbox is not None:
            min_lon, min_lat, max_lon, max_lat = bbox
            results = [
                o
                for o in results
                if min_lon <= o.geometry.coordinates[0] <= max_lon
                and min_lat <= o.geometry.coordinates[1] <= max_lat
            ]
        if since is not None:
            results = [o for o in results if o.observed_at >= since]
        if until is not None:
            results = [o for o in results if o.observed_at <= until]

        if received_since is not None:
            results = [o for o in results if o.received_at >= received_since]
            return sorted(results, key=lambda o: o.received_at)
        return sorted(results, key=lambda o: o.observed_at)

    async def get_observation(self, observation_id: UUID) -> HazardObservation | None:
        async with self._lock:
            return self._store.get(observation_id)

    async def count(self) -> int:
        async with self._lock:
            return len(self._store)
