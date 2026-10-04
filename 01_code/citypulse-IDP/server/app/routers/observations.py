"""POST/GET /observations — the outbox-sync ingest path (T5.4's eventual server side) and
the bbox+time read path a client uses on initial load / reconnect.

Schema violations return 422 automatically: the request body is typed as `HazardObservation`,
so FastAPI/Pydantic rejects anything that doesn't validate before this module's code runs at
all — nothing here coerces a bad payload into something valid.
"""

from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException, Query, Request, status

from app.models import HazardObservation

router = APIRouter(tags=["observations"])

# Defined once at module level (rather than called inline in the signature below) per
# ruff/flake8-bugbear B008 — a `Query(...)` call is otherwise re-evaluated as a mutable
# default on every request.
_SINCE_QUERY = Query(None, description="observed_at >= since")
_UNTIL_QUERY = Query(None, description="observed_at <= until")
_RECEIVED_SINCE_QUERY = Query(
    None,
    description=(
        "received_at >= received_since (server arrival time). Use this to page a sync: an offline "
        "report made at 09:00 and uploaded at 11:00 has a late received_at, which an observed_at "
        "cursor would skip (KNOWN_FLAWS F-10). Results are then ordered by received_at."
    ),
)


@router.post("/observations", status_code=status.HTTP_201_CREATED)
async def submit_observation(
    obs: HazardObservation, request: Request
) -> dict[str, object]:
    repository = request.app.state.repository
    # received_at is the server's clock, never the client's: it is the sync cursor (F-10), and a
    # device-supplied value (an offline phone sends its own) would let a report hide behind it.
    obs = obs.model_copy(update={"received_at": datetime.now(timezone.utc)})
    inserted = await repository.add_observation(obs)
    if inserted:
        # Only broadcast genuinely new observations — a replayed/duplicate id (G-Set dedup,
        # ADR-008) must not cause a second push to connected clients.
        await request.app.state.broadcaster.publish(obs)
    return {"id": str(obs.id), "inserted": inserted}


@router.get("/observations", response_model=list[HazardObservation])
async def list_observations(
    request: Request,
    min_lon: float | None = Query(None, description="Bbox min longitude"),
    min_lat: float | None = Query(None, description="Bbox min latitude"),
    max_lon: float | None = Query(None, description="Bbox max longitude"),
    max_lat: float | None = Query(None, description="Bbox max latitude"),
    since: datetime | None = _SINCE_QUERY,
    until: datetime | None = _UNTIL_QUERY,
    received_since: datetime | None = _RECEIVED_SINCE_QUERY,
) -> list[HazardObservation]:
    bbox_fields = (min_lon, min_lat, max_lon, max_lat)
    if all(v is not None for v in bbox_fields):
        bbox = (min_lon, min_lat, max_lon, max_lat)
    elif any(v is not None for v in bbox_fields):
        raise HTTPException(
            status_code=422,
            detail="bbox query requires all four of min_lon, min_lat, max_lon, max_lat",
        )
    else:
        bbox = None

    repository = request.app.state.repository
    return await repository.get_observations(
        bbox=bbox, since=since, until=until, received_since=received_since
    )
