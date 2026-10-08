"""Rain forecast context for Chennai (ADR-029). No API key (Open-Meteo, model ECMWF IFS 0.25 degree).

What this is. The hourly rain forecast at nine fixed points over the Chennai box, averaged per hour, for the next day. The router reads
it (when `EVENT_FORECAST=1`) and may raise its event state from `dry` to `watch` ahead of rain; the rule itself lives in the router
(`services/router_api/lib/src/event_state.dart`, `EventRule.forecastLevel`), with a Python copy here for the replay script.

What this is NOT.
- **Not a hazard observation.** A forecast is never written to the observation repository and never says a road is flooded or
  passable (ADR-011). Like `imerg.py` it is context, served at `GET /context/forecast`.
- **Not street-level.** The model grid is about 25 km; nine points over the box see two to four model cells.
- **Not validated** until the ADR-029 replay is run; its result is recorded in that ADR.

Licence. Open-Meteo's free API is for non-commercial use; its data is CC BY 4.0, and ECMWF open data is CC BY 4.0
(`docs/LICENCE_AUDIT.md`, row 2). Fine for this research project; a commercial deployment needs another arrangement.

Failure behaviour, as for the rain context: results are cached (30 minutes); a failed refresh serves the last good result marked
`stale`; with no earlier result the failure is reported as 503. Nothing is invented: an hour with a missing value at any point is
left out, never counted as zero.
"""

from __future__ import annotations

import asyncio
import math
from datetime import datetime, timedelta, timezone
from typing import Any

import httpx

FORECAST_URL = "https://api.open-meteo.com/v1/forecast"
MODEL = "ecmwf_ifs025"
SOURCE_ID = f"open-meteo.{MODEL}"
CREDIT = (
    "Weather data by Open-Meteo.com (CC BY 4.0), model ECMWF IFS 0.25 degree (ECMWF open data, CC BY 4.0). "
    "Free API for non-commercial use."
)

# Fixed in ADR-029 before any forecast value was read. Inside the Chennai box of config/cities.yaml.
LATITUDES = (12.80, 13.00, 13.20)
LONGITUDES = (80.00, 80.15, 80.30)
POINTS: tuple[tuple[float, float], ...] = tuple(
    (lat, lon) for lat in LATITUDES for lon in LONGITUDES
)
HORIZON_HOURS = 12
WINDOW_HOURS = 3
# ADR-029: the forecast level is `watch` at or above this three-hour area-mean accumulation (ADR-027's own `watch` number).
WATCH_ACCUMULATION_MM = 8.0

PAST_HOURS = 3
FORECAST_HOURS = 24
CACHE_SECONDS = 30 * 60
# A last-good result older than this is flagged stale (the router ignores a forecast fetched more than 6 h ago anyway).
STALE_AFTER = timedelta(hours=6)
HTTP_TIMEOUT = httpx.Timeout(20.0)
USER_AGENT = "CityPulse-research/1.0 (+https://github.com/Pragatish616/CITYPULSE-IDP)"
NOTES = (
    "Forecast, not an observation: the model's guess of rain, averaged over nine points in the Chennai box.",
    "Model grid of about 25 km; it is not street-level and it smooths out short local downpours.",
    "Rain is not flooding: this is context, never a statement that a road is passable or impassable.",
)


class ForecastUnavailable(Exception):
    """No forecast context can be produced and there is no earlier result to serve."""


# ---------------------------------------------------------------------------------------------- the numbers (pure)


def parse_stamp(text: str) -> datetime:
    """Open-Meteo's hourly time ("2026-10-08T12:00", UTC because `timezone=UTC` is requested)."""
    t = datetime.fromisoformat(text)
    return (
        t.replace(tzinfo=timezone.utc)
        if t.tzinfo is None
        else t.astimezone(timezone.utc)
    )


def area_mean_series(
    locations: list[dict[str, Any]], variable: str = "precipitation"
) -> list[tuple[datetime, float]]:
    """Per hourly stamp, the mean of `variable` over the nine points. A stamp where any point has no value is left out.

    Raises ValueError if the reply does not hold the nine points with the same hours, so a changed feed fails instead of
    quietly averaging fewer points.
    """
    if len(locations) != len(POINTS):
        raise ValueError(f"expected {len(POINTS)} locations, got {len(locations)}")
    times = None
    columns = []
    for loc in locations:
        hourly = loc.get("hourly") or {}
        t, v = hourly.get("time"), hourly.get(variable)
        if not isinstance(t, list) or not isinstance(v, list) or len(t) != len(v):
            raise ValueError(f"location has no usable hourly {variable!r}")
        if times is None:
            times = t
        elif t != times:
            raise ValueError("locations have different hours")
        columns.append(v)
    out: list[tuple[datetime, float]] = []
    for i, stamp in enumerate(times or []):
        values = [col[i] for col in columns]
        if any(
            not isinstance(x, (int, float))
            or isinstance(x, bool)
            or not math.isfinite(x)
            or x < 0
            for x in values
        ):
            continue
        out.append((parse_stamp(stamp), sum(values) / len(values)))
    return out


def window_sums(
    series: list[tuple[datetime, float]], first_end: datetime, last_end: datetime
) -> list[tuple[datetime, float]]:
    """Three-hour sums (stamps H-2h, H-1h, H) for every stamp H in [first_end, last_end] whose three stamps are all present."""
    by_time = dict(series)
    out = []
    for h, _ in series:
        if first_end <= h <= last_end:
            # Oldest hour first, the same order as the Dart copy, so the two sum in the same floating-point order.
            parts = [
                by_time.get(h - timedelta(hours=k))
                for k in range(WINDOW_HOURS - 1, -1, -1)
            ]
            if all(p is not None for p in parts):
                out.append((h, sum(parts)))  # type: ignore[arg-type]
    return out


def ahead(
    series: list[tuple[datetime, float]],
    t: datetime,
    horizon_hours: int = HORIZON_HOURS,
) -> dict[str, Any]:
    """ADR-029's look-ahead: the largest three-hour sum among windows whose three stamps lie in (t, t + horizon]."""
    future = [(h, v) for h, v in series if t < h <= t + timedelta(hours=horizon_hours)]
    if not future:
        return {"stamps_present": 0, "max_3h_area_mean_mm": None, "window_end": None}
    first = min(h for h, _ in future)
    sums = window_sums(
        future,
        first + timedelta(hours=WINDOW_HOURS - 1),
        t + timedelta(hours=horizon_hours),
    )
    best = max(sums, key=lambda x: x[1]) if sums else None
    return {
        "stamps_present": len(future),
        "max_3h_area_mean_mm": round(best[1], 3) if best else None,
        "window_end": best[0].strftime("%Y-%m-%dT%H:%M:%SZ") if best else None,
    }


def level_ahead(
    series: list[tuple[datetime, float]],
    t: datetime,
    horizon_hours: int = HORIZON_HOURS,
) -> str | None:
    """The ADR-029 forecast level at time t: `watch` or `dry`, or None when fewer than 9 of the 12 future stamps exist."""
    a = ahead(series, t, horizon_hours)
    if a["stamps_present"] < 9 or a["max_3h_area_mean_mm"] is None:
        return None
    return "watch" if a["max_3h_area_mean_mm"] >= WATCH_ACCUMULATION_MM else "dry"


# ---------------------------------------------------------------------------------------------- the call and the cache


async def fetch_forecast(client: httpx.AsyncClient) -> list[dict[str, Any]]:
    response = await client.get(
        FORECAST_URL,
        params={
            "latitude": ",".join(str(a) for a, _ in POINTS),
            "longitude": ",".join(str(o) for _, o in POINTS),
            "hourly": "precipitation",
            "models": MODEL,
            "timezone": "UTC",
            "past_hours": PAST_HOURS,
            "forecast_hours": FORECAST_HOURS,
        },
    )
    response.raise_for_status()
    data = response.json()
    if isinstance(data, dict):
        if data.get("error"):
            raise ValueError(f"Open-Meteo error: {str(data.get('reason'))[:200]}")
        data = [data]
    if not isinstance(data, list):
        raise TypeError("Open-Meteo reply is not a list of locations")
    return data


def build_payload(
    series: list[tuple[datetime, float]], now: datetime
) -> dict[str, Any]:
    return {
        "source_id": SOURCE_ID,
        "credit": CREDIT,
        "model": MODEL,
        "points": [{"lat": a, "lon": o} for a, o in POINTS],
        "fetched_at": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "horizon_hours": HORIZON_HOURS,
        "hourly": [
            {"time": h.strftime("%Y-%m-%dT%H:%M:%SZ"), "area_mean_mm": round(v, 3)}
            for h, v in series
        ],
        "next_12h": ahead(series, now),
        "notes": list(NOTES),
    }


class ForecastContextService:
    """Fetches and caches the forecast context. One instance per app (`app.state.forecast_service`)."""

    def __init__(
        self, *, ttl_seconds: float = CACHE_SECONDS, clock=None, client_factory=None
    ) -> None:
        self._ttl = ttl_seconds
        self._clock = clock or (lambda: datetime.now(timezone.utc))
        self._client_factory = client_factory or (
            lambda: httpx.AsyncClient(
                timeout=HTTP_TIMEOUT,
                headers={"User-Agent": USER_AGENT},
                follow_redirects=True,
            )
        )
        self._payload: dict[str, Any] | None = None
        self._series: list[tuple[datetime, float]] = []
        self._fetched: datetime | None = None
        self._lock = asyncio.Lock()

    def _fresh(self, now: datetime) -> bool:
        return (
            self._payload is not None
            and self._fetched is not None
            and (now - self._fetched).total_seconds() < self._ttl
        )

    async def get(self) -> dict[str, Any]:
        now = self._clock()
        if self._fresh(now):
            return self._served(now, "cache")
        async with self._lock:  # many callers at once share one upstream refresh
            now = self._clock()
            if self._fresh(now):
                return self._served(now, "cache")
            try:
                async with self._client_factory() as client:
                    locations = await fetch_forecast(client)
                series = area_mean_series(locations)
                if not series:
                    raise ValueError("the forecast holds no complete hour")
            except Exception as exc:
                if self._payload is None:
                    raise ForecastUnavailable(
                        f"Open-Meteo did not give a usable answer: {exc!r}"
                    ) from exc
                out = self._served(now, "last-good")
                out["stale"] = True
                out["refresh_error"] = repr(exc)[:200]
                return out
            self._series, self._fetched = series, now
            self._payload = build_payload(series, now)
            return self._served(now, "fresh")

    def _served(self, now: datetime, served: str) -> dict[str, Any]:
        out = dict(self._payload or {})
        age = (now - self._fetched).total_seconds() / 60.0 if self._fetched else 0.0
        out["fetch_age_minutes"] = round(max(0.0, age))
        out["stale"] = age > STALE_AFTER.total_seconds() / 60.0
        # The look-ahead is recomputed for the moment of asking, so a cached forecast does not describe a window already past.
        out["next_12h"] = ahead(self._series, now)
        out["served"] = served
        return out
