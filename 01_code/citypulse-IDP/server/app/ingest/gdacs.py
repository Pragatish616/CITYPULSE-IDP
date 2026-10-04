"""GDACS RSS ingest worker. No API key required (research/raw/C-data-sources.md C34:
"Verified feed paths": `xml/rss_fl_7d.xml`, 6-minute cadence, plain RSS over HTTPS, JRC/
Copernicus open terms). Real HTTP fetch + real XML parse, not a stub.

**Honesty note carried into this module deliberately (CLAUDE.md §7):** C34 itself says GDACS
is "Country/event level — too coarse for routing." This worker does not claim otherwise: it
is documented in C-data-sources.md as "the ideal 'is the ingest pipeline alive?' heartbeat
feed", and every observation it emits is stamped with a large `accuracy_m` (country/event
scale, not a street-level fix) so nothing downstream can mistake a GDACS point for a precise
hazard location.

**Schema caveat (documented judgement call, not verified against a live fetch — this
sandboxed environment has no outbound network access to gdacs.org to confirm the exact
GeoRSS element names).** research/raw/C-data-sources.md confirms the URL, cadence and "plain
RSS over HTTPS" but does not paste GDACS's item-level XML schema, and CLAUDE.md §"Hard
rules" forbids inventing a schema and presenting it as verified. `_extract_point` therefore
tries the two GeoRSS/W3C-geo conventions GDACS's own feed-reference page documents
(`georss:point` "lat lon", and `geo:Point`/`geo:lat`+`geo:long`) and returns `None` — skipping
that item, not fabricating a location — if neither is present. **Before this feeds a demo,
run it once against the live URL and confirm which convention GDACS actually uses**; this is
flagged here and in server/README.md rather than silently assumed correct.
"""

from __future__ import annotations

from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from xml.etree import ElementTree

import httpx

from app.events import ObservationBroadcaster
from app.models import GeoPoint, HazardObservation
from app.storage.base import ObservationRepository
from app.util import uuid7

FEED_URL = "https://www.gdacs.org/xml/rss_fl_7d.xml"

NAMESPACES = {
    "georss": "http://www.georss.org/georss",
    "geo": "http://www.w3.org/2003/01/geo/wgs84_pos#",
    "gdacs": "http://www.gdacs.org",
}

# GDACS is global; CityPulse is Chennai-only (ADR-009). This is a coarse country-level
# relevance filter, not a bbox clip — GDACS gives country/event granularity, not geometry
# precise enough to clip to a metro-area bbox.
RELEVANT_COUNTRY_SUBSTRINGS = ("india",)

SOURCE_ID = "gdacs.rss_fl_7d"
GDACS_ACCURACY_M = 100_000.0  # country/event-level per C34, not a street-level fix


async def fetch_feed(client: httpx.AsyncClient) -> str:
    """Real HTTP GET of the GDACS 7-day flood RSS feed. Raises on a non-2xx response."""
    response = await client.get(FEED_URL)
    response.raise_for_status()
    return response.text


def _text(
    item: ElementTree.Element, tag: str, ns: dict[str, str] | None = None
) -> str | None:
    el = item.find(tag, ns) if ns else item.find(tag)
    return el.text.strip() if el is not None and el.text else None


def _extract_point(item: ElementTree.Element) -> tuple[float, float] | None:
    """Returns (lon, lat), or None if the item carries no parseable coordinates."""
    georss_point = _text(item, "georss:point", NAMESPACES)
    if georss_point:
        parts = georss_point.split()
        if len(parts) == 2:
            lat, lon = float(parts[0]), float(parts[1])
            return (lon, lat)

    geo_point = item.find("geo:Point", NAMESPACES)
    if geo_point is not None:
        lat_text = _text(geo_point, "geo:lat", NAMESPACES)
        lon_text = _text(geo_point, "geo:long", NAMESPACES)
        if lat_text and lon_text:
            return (float(lon_text), float(lat_text))

    return None


def _is_relevant(item: ElementTree.Element) -> bool:
    country = _text(item, "gdacs:country", NAMESPACES)
    if country is None:
        return True  # can't filter what we can't read; let it through rather than drop silently
    return any(s in country.lower() for s in RELEVANT_COUNTRY_SUBSTRINGS)


def normalize_item(item: ElementTree.Element) -> HazardObservation | None:
    point = _extract_point(item)
    if point is None or not _is_relevant(item):
        return None

    lon, lat = point
    pub_date_text = _text(item, "pubDate")
    observed_at = (
        parsedate_to_datetime(pub_date_text)
        if pub_date_text
        else datetime.now(timezone.utc)
    )
    if observed_at.tzinfo is None:
        observed_at = observed_at.replace(tzinfo=timezone.utc)

    event_id = _text(item, "gdacs:eventid", NAMESPACES) or _text(item, "guid")
    title = _text(item, "title") or ""
    country = _text(item, "gdacs:country", NAMESPACES)

    return HazardObservation(
        id=uuid7(),
        hazard_class="flood",
        polarity=1,
        geometry=GeoPoint(type="Point", coordinates=(lon, lat)),
        accuracy_m=GDACS_ACCURACY_M,
        observed_at=observed_at,
        source_class="official_feed",
        source_id=f"{SOURCE_ID}.{event_id}" if event_id else SOURCE_ID,
        raw={"title": title, "country": country, "event_id": event_id},
    )


def parse_feed(xml_text: str) -> list[HazardObservation]:
    root = ElementTree.fromstring(xml_text)
    items = root.findall(".//item")
    observations: list[HazardObservation] = []
    for item in items:
        obs = normalize_item(item)
        if obs is not None:
            observations.append(obs)
    return observations


async def run_ingest_cycle(
    repository: ObservationRepository,
    broadcaster: ObservationBroadcaster | None = None,
) -> list[HazardObservation]:
    """Fetch, parse, and store India-relevant flood alerts from the GDACS 7-day feed.
    Returns the list of observations newly inserted (dedup via ADR-008 G-Set semantics).

    Scheduler wiring (not built here): GDACS updates every 6 minutes (C34); a cron/background
    task would call this on a matching or coarser interval.
    """
    inserted: list[HazardObservation] = []
    async with httpx.AsyncClient(timeout=10.0) as client:
        xml_text = await fetch_feed(client)
    for obs in parse_feed(xml_text):
        if await repository.add_observation(obs):
            inserted.append(obs)
            if broadcaster is not None:
                await broadcaster.publish(obs)
    return inserted
