"""TomTom Traffic Incident Details ingest worker — interface shape only, NOT implemented.

TODO(T5.3-cont): needs TOMTOM_API_KEY, see docs/APIS_AND_COSTS.md.

No TomTom developer account exists yet (docs/data-access-log.md; CLAUDE.md §3 — the human
user must sign up, self-serve, free tier, no credit card). Before wiring this for real:
read TomTom's full caching/storage terms on incident data — the pricing page does not state
them (research/raw/C-data-sources.md C29) — because CONTRACTS.md's append-only log means an
incident ingested here is retained, and TomTom's terms on that specific point are unread.
Free tier, once verified: 2,500 incident-detail calls + 200K tiles/month.
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
    """Fetch TomTom Traffic Incident Details for `bbox` (default: Chennai metro) and
    normalise each incident into a `HazardObservation` (hazard_class one of `accident`,
    `debris`, `closure` depending on TomTom's incident category — see
    config/hazard_classes.yaml for the mapping target).

    Requires env var TOMTOM_API_KEY (docs/APIS_AND_COSTS.md §1, Tier 1, ~15 min self-serve
    signup). Not implemented — no account exists yet.
    """
    raise NotImplementedError(
        "T5.3-cont: needs TOMTOM_API_KEY; see docs/APIS_AND_COSTS.md and "
        "docs/data-access-log.md. Read TomTom's caching/storage terms before ingesting "
        "(research/raw/C-data-sources.md C29)."
    )
