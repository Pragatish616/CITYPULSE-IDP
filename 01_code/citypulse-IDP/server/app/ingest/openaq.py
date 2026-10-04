"""OpenAQ v3 (air quality) ingest worker — interface shape only, NOT implemented.

TODO(T5.3-cont): needs OPENAQ_API_KEY, see docs/APIS_AND_COSTS.md.

No OpenAQ account exists yet (docs/data-access-log.md; CLAUDE.md §3 — the human user must
sign up, self-serve, free tier). research/raw/C-data-sources.md C26: OpenAQ v3 requires a
free API key and covers Chennai CPCB stations.
"""

from __future__ import annotations

from app.events import ObservationBroadcaster
from app.models import HazardObservation
from app.storage.base import BBox, ObservationRepository


async def run_ingest_cycle(
    repository: ObservationRepository,
    broadcaster: ObservationBroadcaster | None = None,
    bbox: BBox | None = None,
) -> list[HazardObservation]:
    """Fetch OpenAQ v3 measurements for Chennai CPCB stations within `bbox` and normalise
    each reading into an `aqi` `HazardObservation` (config/hazard_classes.yaml has an `aqi`
    class already; polarity would follow a documented AQI threshold, not invented here).

    Requires env var OPENAQ_API_KEY (docs/APIS_AND_COSTS.md §1, free key). Not implemented —
    no account exists yet.
    """
    raise NotImplementedError(
        "T5.3-cont: needs OPENAQ_API_KEY; see docs/APIS_AND_COSTS.md and "
        "docs/data-access-log.md."
    )
