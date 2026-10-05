"""NASA IMERG rain-intensity context for Chennai. No API key, no login (read-only public NASA GIBS service).

What this is. IMERG (Integrated Multi-satellitE Retrievals for GPM) is a satellite rain estimate on a ~0.1 degree (~10 km) grid,
published every 30 minutes. NASA GIBS serves it as colour-coded map images. This module asks GIBS for small images of the
Chennai box, decodes the colours back into rain rates with GIBS's own colour legend, and reports how hard it is raining now and how
much fell in the last three hours.

What this is NOT.
- **Not a hazard observation.** Rain is not a statement that a road is flooded or passable (ADR-011), so it is never written to the
  observation repository. Like Open-Meteo's river-discharge feed (see open_meteo.py) it is *context*: served at `GET /context/rain`
  for a consumer that decides how to use it, for example whether to switch the router's event state from `dry` to `watch`.
- **Not street-level.** One cell is about 10 km across; the Chennai box holds only a handful of cells.
- **Not real time.** Measured on 5 Oct 2026 the newest image was about 6 hours old. The age is always reported (`data_age_minutes`).
- **Not validated for flooding.** The intensity bands below are generic descriptive rain-rate bands (the light / moderate / heavy /
  violent hourly bands used by national weather services), NOT IMD warning thresholds and NOT fitted to Chennai floods. Like the
  `T_c` placeholders in config/hazard_classes.yaml, treat them as placeholders until a pre-registered study fits them.

Failure behaviour. Results are cached (15 minutes). If a refresh fails the last good result is served, marked `stale`, with its age.
With no earlier result a failure is reported as 503; nothing is invented.

Verified on 4 to 5 Oct 2026 (see docs/APIS_AND_COSTS.md): the DescribeDomains call returns the layer's time range (1998 to the
newest image); the GetMap image for Chennai on 4 Dec 2023 (cyclone Michaung) decodes to the top rain class on every cell.
"""

from __future__ import annotations

import asyncio
import io
import re
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any

import httpx
from PIL import Image

GIBS = "https://gibs.earthdata.nasa.gov"
LAYER = "IMERG_Precipitation_Rate_30min"
COLORMAP_URL = f"{GIBS}/colormaps/v1.3/GPM_Precipitation_Rate.xml"
DOMAINS_URL = f"{GIBS}/wmts/epsg4326/best/wmts.cgi"
WMS_URL = f"{GIBS}/wms/epsg4326/best/wms.cgi"

SOURCE_ID = "nasa-gibs.imerg-30min"
CREDIT = "NASA GPM IMERG (GSFC), served by NASA GIBS. NASA open data."

# The Chennai box the pack was built for (config/cities.yaml): min_lat, min_lon, max_lat, max_lon. WMS 1.3.0 with EPSG:4326 takes lat,lon.
CHENNAI_BBOX = (12.75, 79.95, 13.25, 80.35)
IMAGE_SIZE = (
    10,
    10,
)  # pixels; the source grid is ~0.1 degree, so this oversamples a little and keeps every cell visible

SLICE_MINUTES = 30
ACCUMULATION_SLICES = 6  # three hours
CACHE_SECONDS = 15 * 60
# Newer than this and the upstream is keeping up; older and the result is flagged stale even though the refresh worked.
UPSTREAM_STALE_AFTER = timedelta(hours=12)
HTTP_TIMEOUT = httpx.Timeout(20.0)
USER_AGENT = "CityPulse-research/1.0 (+https://github.com/Pragatish616/CITYPULSE-IDP)"

# Descriptive hourly rain bands, mm/h: (lower bound, label). Placeholders, see the module docstring.
INTENSITY_BANDS: tuple[tuple[float, str], ...] = (
    (0.0, "none"),
    (0.1, "light"),
    (2.5, "moderate"),
    (7.6, "heavy"),
    (50.0, "violent"),
)
NOTES = (
    "Satellite estimate on a grid of about 10 km over the Chennai box. It is not street-level.",
    "Newest images run hours behind real time; see data_age_minutes.",
    "Rain is not flooding: this is context, never a statement that a road is passable or impassable.",
)


class RainUnavailable(Exception):
    """No rain context can be produced and there is no earlier result to serve."""


@dataclass(frozen=True)
class RateBin:
    low: float
    high: float  # math.inf for the open top bin

    @property
    def mid(self) -> float:
        return self.low if self.high == float("inf") else (self.low + self.high) / 2.0


@dataclass(frozen=True)
class SliceStats:
    time: datetime
    pixels: int
    wet_pixels: int
    unmatched_pixels: int
    mean_mm_h: float
    peak_mm_h: float


# ---------------------------------------------------------------------------------------------- colour legend


def _parse_bound(text: str) -> float:
    text = text.strip()
    if text in ("-INF", "-inf"):
        return float("-inf")
    if text in ("+INF", "INF", "inf", "+inf"):
        return float("inf")
    return float(text)


def parse_colormap(xml_text: str) -> dict[tuple[int, int, int], RateBin]:
    """Map each rain colour in GIBS's legend to its rate range in mm/h. Transparent entries (no data, below 0.1 mm/h) are left out:
    a transparent pixel means "no rain worth drawing".
    """
    out: dict[tuple[int, int, int], RateBin] = {}
    for tag in re.findall(r"<ColorMapEntry[^>]*/?>", xml_text):
        if re.search(r'transparent="true"', tag):
            continue
        rgb = re.search(r'rgb="(\d+),(\d+),(\d+)"', tag)
        rng = re.search(r'value="[\[(]([^,\]\)]+),([^,\]\)]+)[\])]"', tag)
        if not rgb or not rng:
            continue
        low, high = _parse_bound(rng.group(1)), _parse_bound(rng.group(2))
        out[(int(rgb.group(1)), int(rgb.group(2)), int(rgb.group(3)))] = RateBin(
            low, high
        )
    if len(out) < 20:
        raise ValueError(
            f"colour legend has only {len(out)} usable rain entries; the format may have changed"
        )
    return out


def intensity_class(rate_mm_h: float) -> str:
    label = INTENSITY_BANDS[0][1]
    for lower, name in INTENSITY_BANDS:
        if rate_mm_h >= lower:
            label = name
    return label


# ---------------------------------------------------------------------------------------------- image decoding


def decode_slice(
    png: bytes,
    legend: dict[tuple[int, int, int], RateBin],
    when: datetime,
    tolerance: int = 6,
) -> SliceStats:
    """Turn one GetMap image into rain statistics. A pixel colour is looked up exactly; one that is not in the legend is matched to the
    nearest legend colour only if it is within `tolerance` per channel, otherwise it is counted as unmatched (and left out of the rates).
    """
    try:
        image = Image.open(io.BytesIO(png)).convert("RGBA")
    except Exception as exc:  # a ServiceException document or a truncated file
        raise ValueError(f"not a usable image: {exc!r}") from exc
    # Pillow 12 renamed getdata(); support both so older installs keep working.
    pixels = list(
        image.get_flattened_data()
        if hasattr(image, "get_flattened_data")
        else image.getdata()
    )
    wet = unmatched = 0
    total_mid = 0.0
    peak = 0.0
    for r, g, b, a in pixels:
        if a == 0:
            continue
        key = (r, g, b)
        rate = legend.get(key)
        if rate is None:
            best, best_d = None, None
            for k, v in legend.items():
                d = max(abs(k[0] - r), abs(k[1] - g), abs(k[2] - b))
                if best_d is None or d < best_d:
                    best, best_d = v, d
            if best is not None and best_d is not None and best_d <= tolerance:
                rate = best
        if rate is None:
            unmatched += 1
            continue
        wet += 1
        total_mid += rate.mid
        peak = max(peak, rate.mid)
    n = len(pixels)
    return SliceStats(
        time=when,
        pixels=n,
        wet_pixels=wet,
        unmatched_pixels=unmatched,
        mean_mm_h=total_mid / n if n else 0.0,
        peak_mm_h=peak,
    )


# ---------------------------------------------------------------------------------------------- GIBS calls


def parse_latest_time(domains_xml: str) -> datetime:
    """The newest image time from a DescribeDomains reply: the end of the last `start/end/period` range."""
    m = re.search(r"<Domain>([^<]+)</Domain>", domains_xml)
    if not m:
        raise ValueError("DescribeDomains reply has no time domain")
    last_range = m.group(1).split(",")[-1].strip()
    parts = last_range.split("/")
    if len(parts) < 2:
        raise ValueError(f"unexpected time range {last_range!r}")
    latest = datetime.fromisoformat(parts[1].replace("Z", "+00:00"))
    if latest.tzinfo is None:
        latest = latest.replace(tzinfo=timezone.utc)
    return latest


async def fetch_latest_time(client: httpx.AsyncClient) -> datetime:
    response = await client.get(
        DOMAINS_URL,
        params={
            "SERVICE": "WMTS",
            "REQUEST": "DescribeDomains",
            "VERSION": "1.0.0",
            "LAYER": LAYER,
            "TILEMATRIXSET": "2km",
            "TILEMATRIX": "0",
            "TILEROW": "0",
            "TILECOL": "0",
            "DOMAINS": "time",
        },
    )
    response.raise_for_status()
    return parse_latest_time(response.text)


async def fetch_colormap(
    client: httpx.AsyncClient,
) -> dict[tuple[int, int, int], RateBin]:
    response = await client.get(COLORMAP_URL)
    response.raise_for_status()
    return parse_colormap(response.text)


async def fetch_slice_png(
    client: httpx.AsyncClient,
    when: datetime,
    bbox: tuple[float, float, float, float] = CHENNAI_BBOX,
) -> bytes:
    response = await client.get(
        WMS_URL,
        params={
            "SERVICE": "WMS",
            "VERSION": "1.3.0",
            "REQUEST": "GetMap",
            "LAYERS": LAYER,
            "STYLES": "",
            "CRS": "EPSG:4326",
            "BBOX": ",".join(str(v) for v in bbox),
            "WIDTH": str(IMAGE_SIZE[0]),
            "HEIGHT": str(IMAGE_SIZE[1]),
            "FORMAT": "image/png",
            "TRANSPARENT": "TRUE",
            "TIME": when.strftime("%Y-%m-%dT%H:%M:%SZ"),
        },
    )
    response.raise_for_status()
    if "image" not in response.headers.get("content-type", ""):
        raise ValueError("GetMap did not return an image: " + response.text[:200])
    return response.content


# ---------------------------------------------------------------------------------------------- the cached service


def build_payload(
    slices: list[SliceStats],
    latest: datetime,
    now: datetime,
    bbox: tuple[float, float, float, float],
    missing: int,
) -> dict[str, Any]:
    newest = slices[0]
    age_min = max(0.0, (now - latest).total_seconds() / 60.0)
    hours = SLICE_MINUTES / 60.0
    accumulation = sum(s.mean_mm_h for s in slices) * hours
    unmatched = sum(s.unmatched_pixels for s in slices)
    total_px = sum(s.pixels for s in slices)
    return {
        "source_id": SOURCE_ID,
        "credit": CREDIT,
        "as_of": latest.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "fetched_at": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "data_age_minutes": round(age_min),
        "stale": age_min > UPSTREAM_STALE_AFTER.total_seconds() / 60.0,
        "bbox": {
            "min_lat": bbox[0],
            "min_lon": bbox[1],
            "max_lat": bbox[2],
            "max_lon": bbox[3],
        },
        "resolution_km": 10,
        "now": {
            "intensity_class": intensity_class(newest.peak_mm_h),
            "peak_rate_mm_h": round(newest.peak_mm_h, 2),
            "mean_rate_mm_h": round(newest.mean_mm_h, 3),
            "wet_fraction": (
                round(newest.wet_pixels / newest.pixels, 3) if newest.pixels else 0.0
            ),
        },
        "recent": {
            "window_hours": round(len(slices) * hours, 1),
            "slices_used": len(slices),
            "slices_missing": missing,
            "area_mean_accumulation_mm": round(accumulation, 2),
            "peak_rate_mm_h": round(max(s.peak_mm_h for s in slices), 2),
        },
        "decode_quality": {
            "unmatched_pixel_fraction": (
                round(unmatched / total_px, 3) if total_px else 0.0
            )
        },
        "notes": list(NOTES),
    }


class RainContextService:
    """Fetches, decodes and caches the rain context. One instance per app (`app.state.rain_service`)."""

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
        self._legend: dict[tuple[int, int, int], RateBin] | None = None
        self._payload: dict[str, Any] | None = None
        self._fetched: datetime | None = None
        self._lock = asyncio.Lock()

    async def get(self) -> dict[str, Any]:
        now = self._clock()
        if (
            self._payload is not None
            and self._fetched is not None
            and (now - self._fetched).total_seconds() < self._ttl
        ):
            return self._with_age(self._payload, now, served="cache")
        async with self._lock:  # many callers at once share one upstream refresh
            now = self._clock()
            if (
                self._payload is not None
                and self._fetched is not None
                and (now - self._fetched).total_seconds() < self._ttl
            ):
                return self._with_age(self._payload, now, served="cache")
            try:
                payload = await self._refresh(now)
            except Exception as exc:
                if self._payload is None:
                    raise RainUnavailable(
                        f"NASA GIBS did not give a usable answer: {exc!r}"
                    ) from exc
                stale = self._with_age(self._payload, now, served="last-good")
                stale["stale"] = True
                stale["refresh_error"] = repr(exc)[:200]
                return stale
            self._payload, self._fetched = payload, now
            return self._with_age(payload, now, served="fresh")

    @staticmethod
    def _with_age(
        payload: dict[str, Any], now: datetime, served: str
    ) -> dict[str, Any]:
        out = dict(payload)
        as_of = datetime.fromisoformat(payload["as_of"].replace("Z", "+00:00"))
        age = max(0.0, (now - as_of).total_seconds() / 60.0)
        out["data_age_minutes"] = round(age)
        out["stale"] = (
            bool(payload["stale"]) or age > UPSTREAM_STALE_AFTER.total_seconds() / 60.0
        )
        out["served"] = served
        return out

    async def _refresh(self, now: datetime) -> dict[str, Any]:
        async with self._client_factory() as client:
            if self._legend is None:
                self._legend = await fetch_colormap(client)
            latest = await fetch_latest_time(client)
            if latest > now + timedelta(hours=1):
                raise ValueError(
                    f"newest image time {latest.isoformat()} is in the future"
                )
            times = [
                latest - timedelta(minutes=SLICE_MINUTES * i)
                for i in range(ACCUMULATION_SLICES)
            ]
            gate = asyncio.Semaphore(3)

            async def one(when: datetime) -> SliceStats | None:
                async with gate:
                    try:
                        return decode_slice(
                            await fetch_slice_png(client, when),
                            self._legend or {},
                            when,
                        )
                    except Exception:  # noqa: BLE001
                        # An image that fails is counted as missing, not fatal.
                        return None

            results = await asyncio.gather(*(one(t) for t in times))
        if results[0] is None:
            raise ValueError("the newest image could not be fetched or decoded")
        slices = [s for s in results if s is not None]
        return build_payload(
            slices, latest, now, CHENNAI_BBOX, missing=len(results) - len(slices)
        )
