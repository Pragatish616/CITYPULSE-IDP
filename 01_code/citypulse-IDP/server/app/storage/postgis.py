"""PostGIS-backed repository, used when `SUPABASE_URL` is set (see `factory.get_repository`).

No Supabase project exists yet (docs/data-access-log.md — T0.4 is incomplete), so this has
not been run against a live database. It is real, parameterised SQL against a schema this
module also creates (`ensure_schema`), using `ST_MakeEnvelope`/`ST_Intersects` over a GiST
index for bbox queries and `ST_DWithin` for radius queries, per the architecture doc's
"PostGIS with GiST indexes for spatial queries." It is not a stub — every method issues a
real query — but it is unverified against a live Postgres instance, and callers should treat
it that way until it has been.

Connection: uses `psycopg` (async) with a small connection pool, per server/requirements.txt.
`asyncpg` was considered but `psycopg[binary,pool]` was already the pinned dependency in the
original requirements.txt stub, so this keeps one fewer driver in the tree.
"""

from __future__ import annotations

import json
from datetime import datetime
from typing import Any
from uuid import UUID

from psycopg_pool import AsyncConnectionPool

from app.models import GeoPoint, HazardObservation
from app.storage.base import BBox, ObservationRepository

SCHEMA_SQL = """
CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE IF NOT EXISTS hazard_observations (
    id                  UUID PRIMARY KEY,
    hazard_class        TEXT NOT NULL,
    polarity            SMALLINT NOT NULL CHECK (polarity IN (1, -1)),
    geom                geometry(Point, 4326) NOT NULL,
    accuracy_m          DOUBLE PRECISION NOT NULL,
    observed_at         TIMESTAMPTZ NOT NULL,
    received_at         TIMESTAMPTZ NOT NULL,
    source_class        TEXT NOT NULL,
    source_id           TEXT NOT NULL,
    intensity           JSONB,
    raw                 JSONB NOT NULL DEFAULT '{}'::jsonb,
    precision_state     TEXT NOT NULL DEFAULT 'exact',
    coarsened_at        TIMESTAMPTZ,
    watchlist_point_id  TEXT
);

CREATE INDEX IF NOT EXISTS hazard_observations_geom_gist
    ON hazard_observations USING GIST (geom);

CREATE INDEX IF NOT EXISTS hazard_observations_observed_at_idx
    ON hazard_observations (observed_at);
"""

_INSERT_SQL = """
INSERT INTO hazard_observations (
    id, hazard_class, polarity, geom, accuracy_m, observed_at, received_at,
    source_class, source_id, intensity, raw, precision_state, coarsened_at, watchlist_point_id
) VALUES (
    %(id)s, %(hazard_class)s, %(polarity)s, ST_SetSRID(ST_MakePoint(%(lon)s, %(lat)s), 4326),
    %(accuracy_m)s, %(observed_at)s, %(received_at)s, %(source_class)s, %(source_id)s,
    %(intensity)s, %(raw)s, %(precision_state)s, %(coarsened_at)s, %(watchlist_point_id)s
)
ON CONFLICT (id) DO NOTHING
RETURNING id;
"""

_SELECT_COLUMNS = """
    id, hazard_class, polarity, ST_X(geom) AS lon, ST_Y(geom) AS lat, accuracy_m,
    observed_at, received_at, source_class, source_id, intensity, raw, precision_state,
    coarsened_at, watchlist_point_id
"""

_SELECT_BBOX_SQL = f"""
SELECT {_SELECT_COLUMNS}
FROM hazard_observations
WHERE (%(min_lon)s IS NULL OR ST_Intersects(
        geom, ST_MakeEnvelope(%(min_lon)s, %(min_lat)s, %(max_lon)s, %(max_lat)s, 4326)
      ))
  AND (%(since)s IS NULL OR observed_at >= %(since)s)
  AND (%(until)s IS NULL OR observed_at <= %(until)s)
  AND (%(received_since)s IS NULL OR received_at >= %(received_since)s)
ORDER BY CASE WHEN %(received_since)s IS NULL THEN observed_at ELSE received_at END ASC;
"""

_SELECT_RADIUS_SQL = f"""
SELECT {_SELECT_COLUMNS}
FROM hazard_observations
WHERE ST_DWithin(
        geom::geography,
        ST_SetSRID(ST_MakePoint(%(lon)s, %(lat)s), 4326)::geography,
        %(radius_m)s
      )
  AND (%(since)s IS NULL OR observed_at >= %(since)s)
ORDER BY observed_at ASC;
"""

_SELECT_ONE_SQL = f"""
SELECT {_SELECT_COLUMNS}
FROM hazard_observations
WHERE id = %(id)s;
"""

_COUNT_SQL = "SELECT COUNT(*) FROM hazard_observations;"


def _row_to_observation(row: dict[str, Any]) -> HazardObservation:
    return HazardObservation(
        id=row["id"],
        hazard_class=row["hazard_class"],
        polarity=row["polarity"],
        geometry=GeoPoint(type="Point", coordinates=(row["lon"], row["lat"])),
        accuracy_m=row["accuracy_m"],
        observed_at=row["observed_at"],
        received_at=row["received_at"],
        source_class=row["source_class"],
        source_id=row["source_id"],
        intensity=row["intensity"],
        raw=row["raw"] or {},
        precision_state=row["precision_state"],
        coarsened_at=row["coarsened_at"],
        watchlist_point_id=row["watchlist_point_id"],
    )


def _obs_to_params(obs: HazardObservation) -> dict[str, Any]:
    lon, lat = obs.geometry.coordinates
    return {
        "id": str(obs.id),
        "hazard_class": obs.hazard_class.value,
        "polarity": obs.polarity,
        "lon": lon,
        "lat": lat,
        "accuracy_m": obs.accuracy_m,
        "observed_at": obs.observed_at,
        "received_at": obs.received_at,
        "source_class": obs.source_class.value,
        "source_id": obs.source_id,
        "intensity": json.dumps(obs.intensity) if obs.intensity is not None else None,
        "raw": json.dumps(obs.raw),
        "precision_state": obs.precision_state,
        "coarsened_at": obs.coarsened_at,
        "watchlist_point_id": obs.watchlist_point_id,
    }


class PostGISObservationRepository(ObservationRepository):
    def __init__(self, dsn: str) -> None:
        self._dsn = dsn
        self._pool: AsyncConnectionPool | None = None

    async def _get_pool(self) -> AsyncConnectionPool:
        if self._pool is None:
            self._pool = AsyncConnectionPool(self._dsn, open=False)
            await self._pool.open()
        return self._pool

    async def ensure_schema(self) -> None:
        """Create the table/indexes if they don't exist. Call once at startup against a real
        Supabase project; safe to call repeatedly (everything is IF NOT EXISTS)."""
        pool = await self._get_pool()
        async with pool.connection() as conn:
            await conn.execute(SCHEMA_SQL)

    async def add_observation(self, obs: HazardObservation) -> bool:
        pool = await self._get_pool()
        async with pool.connection() as conn:
            cur = await conn.execute(_INSERT_SQL, _obs_to_params(obs))
            row = await cur.fetchone()
            return row is not None

    async def get_observations(
        self,
        bbox: BBox | None = None,
        since: datetime | None = None,
        until: datetime | None = None,
        received_since: datetime | None = None,
    ) -> list[HazardObservation]:
        pool = await self._get_pool()
        params: dict[str, Any] = {
            "min_lon": bbox[0] if bbox else None,
            "min_lat": bbox[1] if bbox else None,
            "max_lon": bbox[2] if bbox else None,
            "max_lat": bbox[3] if bbox else None,
            "since": since,
            "until": until,
            "received_since": received_since,
        }
        async with pool.connection() as conn:
            cur = await conn.execute(_SELECT_BBOX_SQL, params)
            columns = [d.name for d in cur.description]
            rows = await cur.fetchall()
        return [_row_to_observation(dict(zip(columns, r, strict=True))) for r in rows]

    async def get_observations_within_radius(
        self, lon: float, lat: float, radius_m: float, since: datetime | None = None
    ) -> list[HazardObservation]:
        """Point-radius query via ST_DWithin on a geography cast — the PostGIS analogue of
        the architecture doc's Redis `GEOSEARCH` hot lookup, for when Redis isn't configured.
        Not wired to an HTTP endpoint in T5.3 (only the bbox query is); kept as a repository
        method other components (T1.2 fuse(), a future hot-lookup endpoint) can call directly.
        """
        pool = await self._get_pool()
        params = {"lon": lon, "lat": lat, "radius_m": radius_m, "since": since}
        async with pool.connection() as conn:
            cur = await conn.execute(_SELECT_RADIUS_SQL, params)
            columns = [d.name for d in cur.description]
            rows = await cur.fetchall()
        return [_row_to_observation(dict(zip(columns, r, strict=True))) for r in rows]

    async def get_observation(self, observation_id: UUID) -> HazardObservation | None:
        pool = await self._get_pool()
        async with pool.connection() as conn:
            cur = await conn.execute(_SELECT_ONE_SQL, {"id": str(observation_id)})
            columns = [d.name for d in cur.description]
            row = await cur.fetchone()
        if row is None:
            return None
        return _row_to_observation(dict(zip(columns, row, strict=True)))

    async def count(self) -> int:
        pool = await self._get_pool()
        async with pool.connection() as conn:
            cur = await conn.execute(_COUNT_SQL)
            row = await cur.fetchone()
        return row[0] if row else 0

    async def close(self) -> None:
        if self._pool is not None:
            await self._pool.close()
