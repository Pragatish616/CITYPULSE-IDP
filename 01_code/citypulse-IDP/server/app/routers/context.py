"""GET /context/rain: satellite rain-intensity context for Chennai (NASA IMERG via GIBS).

Context, not a hazard observation: it is never stored as a report and never says a road is flooded or passable (ADR-011). See
app/ingest/imerg.py for what it is, its limits, and how it behaves when NASA is unreachable.
"""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, HTTPException, Request, status

from app.ingest.imerg import RainUnavailable

router = APIRouter(prefix="/context", tags=["context"])


@router.get("/rain")
async def rain_context(request: Request) -> dict[str, Any]:
    service = request.app.state.rain_service
    try:
        return await service.get()
    except RainUnavailable as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc)
        ) from exc
