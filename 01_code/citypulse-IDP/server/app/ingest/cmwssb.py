"""CMWSSB reservoir-level scraper — interface shape only, NOT implemented.

TODO(T5.3-cont): needs confirmed CMWSSB page reachability from an Indian IP; see
docs/IMPLEMENTATION_PLAN.md T0.5 and docs/APIS_AND_COSTS.md.

docs/IMPLEMENTATION_PLAN.md T0.5 found `cmwssb.tn.gov.in/previous-lake-level`'s page
structure unreachable from two independent research environments outside India ("'30-line
scraper' is a hope, not a confirmed fact, until someone reaches it from an Indian IP" —
research/raw/C-data-sources.md). Do not build a scraper against a page nobody on this team
has successfully loaded; a scraper against a guessed DOM structure is worse than no scraper.
"""

from __future__ import annotations

from app.events import ObservationBroadcaster
from app.models import HazardObservation
from app.storage.base import ObservationRepository


async def run_ingest_cycle(
    repository: ObservationRepository,
    broadcaster: ObservationBroadcaster | None = None,
) -> list[HazardObservation]:
    """Scrape CMWSSB reservoir/lake levels (Chembarambakkam etc.) and emit them as
    `context_facts`-style auxiliary records (reservoir level is not itself a point hazard —
    see docs/CONTRACTS.md §3's `reservoir_level_pct` example), which escalate the
    watchlist corridors downstream of each reservoir per ADR-009.

    Not implemented — the source page has not been successfully reached from any
    environment available to this team (docs/IMPLEMENTATION_PLAN.md T0.5). Reachability must
    be confirmed from an Indian IP before this is built for real.
    """
    raise NotImplementedError(
        "T5.3-cont: cmwssb.tn.gov.in/previous-lake-level unreachable in two research "
        "environments (docs/IMPLEMENTATION_PLAN.md T0.5); confirm reachability from an "
        "Indian IP before implementing."
    )
