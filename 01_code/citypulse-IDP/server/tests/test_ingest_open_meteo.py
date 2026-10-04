"""Open-Meteo worker — mocked HTTP, no real network calls in the test suite."""

from __future__ import annotations

import httpx
import respx
from app.ingest.open_meteo import (
    FORECAST_URL,
    normalize_flood_context,
    normalize_heat_observation,
    run_ingest_cycle,
)
from app.storage.memory import InMemoryObservationRepository

CHENNAI_LAT, CHENNAI_LON = 13.0827, 80.2707


def _forecast_response(apparent_temperature: float) -> dict:
    return {
        "current": {
            "time": "2026-09-17T10:00",
            "temperature_2m": apparent_temperature - 1.5,
            "apparent_temperature": apparent_temperature,
        }
    }


def test_normalize_heat_observation_hot_day_is_positive_polarity() -> None:
    obs = normalize_heat_observation(_forecast_response(42.0), CHENNAI_LAT, CHENNAI_LON)
    assert obs is not None
    assert obs.hazard_class.value == "heat"
    assert obs.polarity == 1
    assert obs.source_class.value == "official_feed"


def test_normalize_heat_observation_mild_day_is_negative_polarity() -> None:
    obs = normalize_heat_observation(_forecast_response(28.0), CHENNAI_LAT, CHENNAI_LON)
    assert obs is not None
    assert obs.polarity == -1


def test_normalize_heat_observation_missing_current_returns_none() -> None:
    assert normalize_heat_observation({}, CHENNAI_LAT, CHENNAI_LON) is None


def test_normalize_flood_context_is_not_a_hazard_observation() -> None:
    raw = {"daily": {"time": ["2026-09-17"], "river_discharge": [123.4]}}
    context = normalize_flood_context(raw, CHENNAI_LAT, CHENNAI_LON)
    assert context is not None
    assert context["key"] == "river_discharge_m3s"
    assert context["value"] == 123.4
    assert "as_of" in context and "label" in context


@respx.mock
async def test_run_ingest_cycle_inserts_observations_from_mocked_api() -> None:
    # run_ingest_cycle only fetches the forecast (heat) endpoint — the flood endpoint is
    # deliberately not wired into ingest (see module docstring); FLOOD_URL is exercised
    # separately in test_normalize_flood_context_is_not_a_hazard_observation.
    respx.get(FORECAST_URL).mock(
        return_value=httpx.Response(200, json=_forecast_response(41.0))
    )

    repository = InMemoryObservationRepository()
    inserted = await run_ingest_cycle(repository, points=((CHENNAI_LAT, CHENNAI_LON),))

    assert len(inserted) == 1
    assert inserted[0].hazard_class.value == "heat"
    assert await repository.count() == 1
