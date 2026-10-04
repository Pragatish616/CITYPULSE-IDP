"""Repository interface for `HazardObservation` storage.

Two implementations exist: `memory.InMemoryObservationRepository` (default, no external
dependency) and `postgis.PostGISObservationRepository` (real PostGIS SQL, used when
SUPABASE_URL is set — see `factory.get_repository`). Nothing outside `app/storage/` should
care which one is active.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from datetime import datetime
from uuid import UUID

from app.models import HazardObservation

# (min_lon, min_lat, max_lon, max_lat)
BBox = tuple[float, float, float, float]


class ObservationRepository(ABC):
    @abstractmethod
    async def add_observation(self, obs: HazardObservation) -> bool:
        """Append `obs`. G-Set semantics (ADR-008): if `obs.id` already exists, do nothing
        and return False. Otherwise store it and return True. Never raises on a duplicate —
        that is the whole point of `ON CONFLICT DO NOTHING`.
        """

    @abstractmethod
    async def get_observations(
        self,
        bbox: BBox | None = None,
        since: datetime | None = None,
        until: datetime | None = None,
        received_since: datetime | None = None,
    ) -> list[HazardObservation]:
        """Query by bbox and/or time window over `observed_at`, ordered oldest to newest.
        `received_since` filters on the server-assigned `received_at` instead and, when given,
        orders by `received_at` (the sync cursor, F-10).
        All filters are optional and combine with AND; omitting all returns everything.
        """

    @abstractmethod
    async def get_observation(self, observation_id: UUID) -> HazardObservation | None:
        """Fetch a single observation by id, or None if it does not exist."""

    @abstractmethod
    async def count(self) -> int:
        """Total number of stored observations. Used by tests and /health-adjacent tooling."""
