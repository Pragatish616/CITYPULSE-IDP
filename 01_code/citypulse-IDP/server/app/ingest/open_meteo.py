"""Open-Meteo ingest worker. No API key required (docs/APIS_AND_COSTS.md §1, research/raw/
C-data-sources.md C8) — this is a real implementation, not a stub.

Two Open-Meteo products, two different fates, per the task's own escape hatch:

1. **Forecast API** (`api.open-meteo.com/v1/forecast`) — current near-surface temperature.
   This maps cleanly onto `hazard_class: heat` (config/hazard_classes.yaml has a `heat`
   class with its own `T_c`/severity/display_noun) and is ingested as real
   `HazardObservation` records via `run_ingest_cycle`.

2. **Flood API** (`flood-api.open-meteo.com/v1/flood`) — daily GloFAS-derived *river
   discharge* on a ~5 km grid (research/raw/C-data-sources.md C8). This does **not** map
   cleanly onto any `hazard_class`: it is not a presence/absence claim about a point or edge
   (there is no `depth_mm`, no polarity — a discharge number is a magnitude, not a hazard
   observation), and CONTRACTS.md's own `intensity.depth_mm` is documented as flood-specific
   but is depth, not discharge. Forcing it into `hazard_class: flood` would mean either
   inventing a `polarity` (there is none in the source data) or an `intensity` field the
   contract doesn't define. This is exactly the "if none fit cleanly, use context_facts-style
   auxiliary data instead" case the task brief anticipates: `fetch_flood_context` returns a
   normalised dict shaped like a `DecisionTrace.context_facts` entry
   (docs/CONTRACTS.md §3 — `{key, value, label, as_of}`), for a future router-side consumer
   to attach to a trace at query time. It is **not** written to the observation repository by
   this module — `context_facts` are the router's job when building a `DecisionTrace`, not
   the ingest layer's, and T5.3 is ingest only.

Scheduler wiring (not built here): a cron/background task would call
`run_ingest_cycle(repository, broadcaster)` on an interval (Open-Meteo's forecast updates
hourly; polling every 15-30 min is more than enough headroom against the 10k/day free
ceiling for a handful of watchlist points).
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

import httpx

from app.config import hazard_class_params
from app.events import ObservationBroadcaster
from app.models import GeoPoint, HazardObservation
from app.storage.base import ObservationRepository
from app.util import uuid7

FORECAST_URL = "https://api.open-meteo.com/v1/forecast"
FLOOD_URL = "https://flood-api.open-meteo.com/v1/flood"

# A handful of representative Chennai points, not the full ~150-200 point watchlist
# (data/watchlist/2026-09-14/watchlist_candidates.json) — wiring the full watchlist through
# ingest workers is follow-up work (T5.3-cont / data-wrangler territory), not this task.
DEFAULT_POINTS: tuple[tuple[float, float], ...] = (
    (13.0827, 80.2707),  # Chennai city centre
    (
        12.9698,
        80.2200,
    ),  # Velachery (chronic waterlogging corridor, per ADR-009 watchlist)
)

# Heat-wave threshold used to derive polarity from apparent temperature. IMD's Chennai
# heat-wave criterion is coastal-station-specific and not sourced here — this is a
# placeholder threshold (config/hazard_classes.yaml has no numeric heat trigger of its own),
# analogous to the yaml's own T_c "PLACEHOLDER - fit from data" values. Flag before citing.
HEAT_APPARENT_TEMP_C_THRESHOLD = 40.0

SOURCE_ID = "open-meteo.forecast"


async def fetch_forecast(
    client: httpx.AsyncClient, lat: float, lon: float
) -> dict[str, Any]:
    """Real HTTP call to the Open-Meteo forecast API. Raises on a non-2xx response."""
    response = await client.get(
        FORECAST_URL,
        params={
            "latitude": lat,
            "longitude": lon,
            "current": "temperature_2m,apparent_temperature",
            "timezone": "UTC",
        },
    )
    response.raise_for_status()
    return response.json()


async def fetch_flood_context(
    client: httpx.AsyncClient, lat: float, lon: float
) -> dict[str, Any]:
    """Real HTTP call to the Open-Meteo flood API. Returns the raw JSON — normalisation into
    a context_facts-shaped record happens in `normalize_flood_context`.
    """
    response = await client.get(
        FLOOD_URL,
        params={"latitude": lat, "longitude": lon, "daily": "river_discharge"},
    )
    response.raise_for_status()
    return response.json()


def normalize_heat_observation(
    raw: dict[str, Any], lat: float, lon: float
) -> HazardObservation | None:
    """Turn one forecast API response into a `heat` HazardObservation, or None if the
    response has no usable `current` block.
    """
    current = raw.get("current")
    if not current or "apparent_temperature" not in current:
        return None

    apparent_c = float(current["apparent_temperature"])
    observed_at = datetime.fromisoformat(current["time"]).replace(tzinfo=timezone.utc)
    polarity = 1 if apparent_c >= HEAT_APPARENT_TEMP_C_THRESHOLD else -1

    return HazardObservation(
        id=uuid7(),
        hazard_class="heat",
        polarity=polarity,
        geometry=GeoPoint(type="Point", coordinates=(lon, lat)),
        accuracy_m=5000.0,  # forecast grid cell, not a point sensor
        observed_at=observed_at,
        source_class="official_feed",
        source_id=SOURCE_ID,
        intensity={
            "temperature_c": current.get("temperature_2m"),
            "apparent_temperature_c": apparent_c,
        },
        raw=raw,
    )


def normalize_flood_context(
    raw: dict[str, Any], lat: float, lon: float
) -> dict[str, Any] | None:
    """Shape a flood API response as a `DecisionTrace.context_facts`-style entry
    (docs/CONTRACTS.md §3), NOT a HazardObservation. See module docstring for why.
    """
    daily = raw.get("daily")
    if not daily or "river_discharge" not in daily or not daily["river_discharge"]:
        return None
    latest_discharge = daily["river_discharge"][0]
    as_of = daily["time"][0] if daily.get("time") else None
    return {
        "key": "river_discharge_m3s",
        "value": latest_discharge,
        "label": f"Open-Meteo flood forecast ({lat:.3f},{lon:.3f})",
        "as_of": as_of,
    }


async def run_ingest_cycle(
    repository: ObservationRepository,
    broadcaster: ObservationBroadcaster | None = None,
    points: tuple[tuple[float, float], ...] = DEFAULT_POINTS,
) -> list[HazardObservation]:
    """Fetch + normalise + store heat observations for each (lat, lon) in `points`.
    Returns the list of observations that were newly inserted (duplicates, if any, excluded).
    Uses `hazard_class_params("heat")` only to confirm the class exists in the shared config
    (fails loudly if config/hazard_classes.yaml ever drops "heat") rather than to read a
    numeric threshold from it — no such threshold exists there yet.
    """
    hazard_class_params(
        "heat"
    )  # raises KeyError if "heat" is ever removed from the yaml

    inserted: list[HazardObservation] = []
    async with httpx.AsyncClient(timeout=10.0) as client:
        for lat, lon in points:
            raw = await fetch_forecast(client, lat, lon)
            obs = normalize_heat_observation(raw, lat, lon)
            if obs is None:
                continue
            if await repository.add_observation(obs):
                inserted.append(obs)
                if broadcaster is not None:
                    await broadcaster.publish(obs)
    return inserted
