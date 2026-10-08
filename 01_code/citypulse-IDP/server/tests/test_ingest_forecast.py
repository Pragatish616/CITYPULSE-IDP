"""Rain forecast context (ADR-029): the numbers, the shared rule vectors, the cached service and the endpoint. No network."""

from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone
from pathlib import Path

import httpx
import pytest
import respx

from app.ingest import forecast
from app.ingest.forecast import (
    FORECAST_URL,
    ForecastContextService,
    ForecastUnavailable,
    ahead,
    area_mean_series,
    level_ahead,
    parse_stamp,
)

NOW = datetime(2026, 10, 8, 12, 0, tzinfo=timezone.utc)
VECTORS = (
    Path(__file__).resolve().parents[2]
    / "services"
    / "router_api"
    / "test"
    / "fixtures"
    / "forecast_rule_vectors.json"
)


def location(
    values: list[float | None], start: datetime = NOW - timedelta(hours=3)
) -> dict:
    return {
        "hourly": {
            "time": [
                (start + timedelta(hours=i)).strftime("%Y-%m-%dT%H:%M")
                for i in range(len(values))
            ],
            "precipitation": values,
        }
    }


def reply(
    per_point: list[list[float | None]] | None = None, hours: int = 28
) -> list[dict]:
    if per_point is None:
        per_point = [[0.0] * hours for _ in range(9)]
    return [location(v) for v in per_point]


# ---------------------------------------------------------------------------------------------- the numbers


def test_area_mean_is_the_mean_over_the_nine_points() -> None:
    per_point = [[float(i)] * 4 for i in range(9)]  # 0..8 -> mean 4
    series = area_mean_series(reply(per_point))
    assert [v for _, v in series] == [4.0] * 4
    assert series[0][0] == NOW - timedelta(hours=3) and series[0][0].tzinfo is not None


def test_an_hour_with_a_missing_value_is_left_out_not_counted_as_zero() -> None:
    per_point = [[1.0, 1.0, 1.0] for _ in range(9)]
    per_point[4][1] = None
    series = area_mean_series(reply(per_point))
    assert [h for h, _ in series] == [
        NOW - timedelta(hours=3),
        NOW - timedelta(hours=1),
    ]


@pytest.mark.parametrize("bad", [-1.0, float("nan"), True, "2"])
def test_a_nonsense_value_is_treated_as_missing(bad) -> None:
    per_point = [[1.0, 1.0] for _ in range(9)]
    per_point[0][0] = bad
    assert len(area_mean_series(reply(per_point))) == 1


def test_a_reply_without_nine_points_or_with_different_hours_is_refused() -> None:
    with pytest.raises(ValueError, match="expected 9"):
        area_mean_series(reply()[:8])
    locs = reply()
    locs[3] = location([0.0] * 28, start=NOW)
    with pytest.raises(ValueError, match="different hours"):
        area_mean_series(locs)
    locs = reply()
    locs[0] = {"hourly": {"time": ["2026-10-08T00:00"]}}
    with pytest.raises(ValueError, match="no usable"):
        area_mean_series(locs)


def test_open_meteo_times_are_read_as_utc() -> None:
    assert parse_stamp("2026-10-08T12:00") == NOW
    assert parse_stamp("2026-10-08T17:30+05:30") == NOW


def test_the_shared_rule_vectors() -> None:
    """The same file is read by the Dart tests (services/router_api/test/event_state_test.dart); both must agree with it."""
    doc = json.loads(VECTORS.read_text(encoding="utf-8"))
    assert doc["watch_accumulation_mm"] == forecast.WATCH_ACCUMULATION_MM
    assert doc["horizon_hours"] == forecast.HORIZON_HOURS
    for v in doc["vectors"]:
        series = [(parse_stamp(x["time"]), x["area_mean_mm"]) for x in v["hourly"]]
        t = parse_stamp(v["t"])
        assert level_ahead(series, t) == v["level"], v["name"]
        got = ahead(series, t)["max_3h_area_mean_mm"]
        if v["max"] is None:
            assert v["level"] is None, v["name"]
        else:
            assert got == pytest.approx(v["max"], abs=1e-9), v["name"]


def test_constants_are_the_ones_fixed_in_adr_029() -> None:
    assert forecast.MODEL == "ecmwf_ifs025"
    assert forecast.LATITUDES == (12.80, 13.00, 13.20)
    assert forecast.LONGITUDES == (80.00, 80.15, 80.30)
    assert forecast.WATCH_ACCUMULATION_MM == 8.0 and forecast.HORIZON_HOURS == 12
    # every point inside the Chennai box (same box as imerg.CHENNAI_BBOX)
    from app.ingest.imerg import CHENNAI_BBOX

    lo_lat, lo_lon, hi_lat, hi_lon = CHENNAI_BBOX
    assert all(lo_lat < a < hi_lat and lo_lon < o < hi_lon for a, o in forecast.POINTS)


# ---------------------------------------------------------------------------------------------- the service


def mock_open_meteo(
    router: respx.MockRouter, body=None, status: int = 200
) -> respx.Route:
    return router.get(FORECAST_URL).mock(
        return_value=httpx.Response(status, json=reply() if body is None else body)
    )


async def test_service_asks_for_the_fixed_model_and_points_and_reports_the_look_ahead() -> (
    None
):
    per_point = [[0.0] * 28 for _ in range(9)]
    for p in per_point:
        p[3 + 5] = p[3 + 6] = p[3 + 7] = (
            3.0  # stamps NOW+5h..NOW+7h: 9 mm in three hours
        )
    with respx.mock() as router:
        route = mock_open_meteo(router, reply(per_point))
        out = await ForecastContextService(clock=lambda: NOW).get()
    params = route.calls.last.request.url.params
    assert params["models"] == "ecmwf_ifs025" and params["hourly"] == "precipitation"
    assert params["timezone"] == "UTC" and len(params["latitude"].split(",")) == 9
    assert (
        out["served"] == "fresh"
        and out["stale"] is False
        and out["fetch_age_minutes"] == 0
    )
    assert out["next_12h"] == {
        "stamps_present": 12,
        "max_3h_area_mean_mm": 9.0,
        "window_end": "2026-10-08T19:00:00Z",
    }
    assert out["model"] == "ecmwf_ifs025" and "Open-Meteo" in out["credit"]
    assert any("not flooding" in n.lower() for n in out["notes"])
    assert len(out["hourly"]) == 28


async def test_the_look_ahead_moves_with_the_clock_while_the_forecast_is_cached() -> (
    None
):
    clock = {"now": NOW}
    per_point = [[0.0] * 28 for _ in range(9)]
    for p in per_point:
        p[3 + 1] = p[3 + 2] = p[3 + 3] = 3.0  # rain at NOW+1h..NOW+3h
    service = ForecastContextService(clock=lambda: clock["now"])
    with respx.mock() as router:
        route = mock_open_meteo(router, reply(per_point))
        first = await service.get()
        clock["now"] = NOW + timedelta(minutes=20) + timedelta(hours=0)
        second = await service.get()
        assert route.call_count == 1
    assert first["next_12h"]["max_3h_area_mean_mm"] == 9.0
    assert second["served"] == "cache" and second["fetch_age_minutes"] == 20


async def test_failed_refresh_serves_the_last_good_result_marked_stale() -> None:
    clock = {"now": NOW}
    service = ForecastContextService(clock=lambda: clock["now"])
    with respx.mock() as router:
        mock_open_meteo(router)
        await service.get()
    clock["now"] = NOW + timedelta(minutes=45)
    with respx.mock() as router:
        mock_open_meteo(router, status=503)
        later = await service.get()
    assert later["served"] == "last-good" and later["stale"] is True
    assert "refresh_error" in later and later["fetch_age_minutes"] == 45


async def test_no_earlier_result_and_a_failure_is_reported_not_invented() -> None:
    with respx.mock() as router:
        mock_open_meteo(router, status=500)
        with pytest.raises(ForecastUnavailable):
            await ForecastContextService(clock=lambda: NOW).get()


async def test_an_error_document_or_an_empty_forecast_is_a_failure() -> None:
    with respx.mock() as router:
        mock_open_meteo(router, body={"error": True, "reason": "bad model"})
        with pytest.raises(ForecastUnavailable, match="bad model"):
            await ForecastContextService(clock=lambda: NOW).get()
    with respx.mock() as router:
        mock_open_meteo(router, body=reply([[None] * 5 for _ in range(9)]))
        with pytest.raises(ForecastUnavailable, match="no complete hour"):
            await ForecastContextService(clock=lambda: NOW).get()


async def test_a_last_good_result_older_than_six_hours_is_stale() -> None:
    clock = {"now": NOW}
    service = ForecastContextService(clock=lambda: clock["now"])
    with respx.mock() as router:
        mock_open_meteo(router)
        await service.get()
    clock["now"] = NOW + timedelta(hours=7)
    with respx.mock() as router:
        mock_open_meteo(router, status=503)
        out = await service.get()
    # The 24-hour forecast still covers the next 12 hours, but it is more than 6 hours old, so it is flagged.
    assert out["stale"] is True and out["next_12h"]["stamps_present"] == 12
    clock["now"] = NOW + timedelta(hours=20)
    with respx.mock() as router:
        mock_open_meteo(router, status=503)
        out = await service.get()
    # Now most of the next 12 hours lie beyond the old forecast: too few hours for an answer.
    assert out["next_12h"]["stamps_present"] == 4


# ---------------------------------------------------------------------------------------------- the endpoint


def test_endpoint_returns_the_forecast(client, app_instance) -> None:
    app_instance.state.forecast_service = ForecastContextService(clock=lambda: NOW)
    with respx.mock(assert_all_called=False, assert_all_mocked=False) as router:
        mock_open_meteo(router)
        router.route(host="testserver").pass_through()
        response = client.get("/context/forecast")
    assert response.status_code == 200
    assert response.json()["next_12h"]["max_3h_area_mean_mm"] == 0.0


def test_endpoint_says_503_when_open_meteo_cannot_be_reached(
    client, app_instance
) -> None:
    app_instance.state.forecast_service = ForecastContextService(clock=lambda: NOW)
    with respx.mock(assert_all_called=False, assert_all_mocked=False) as router:
        mock_open_meteo(router, status=500)
        router.route(host="testserver").pass_through()
        response = client.get("/context/forecast")
    assert response.status_code == 503 and "Open-Meteo" in response.json()["detail"]


def test_a_forecast_is_not_written_to_the_observation_store(
    client, app_instance
) -> None:
    app_instance.state.forecast_service = ForecastContextService(clock=lambda: NOW)
    with respx.mock(assert_all_called=False, assert_all_mocked=False) as router:
        mock_open_meteo(router)
        router.route(host="testserver").pass_through()
        client.get("/context/forecast")
    assert client.get("/observations").json() == []
