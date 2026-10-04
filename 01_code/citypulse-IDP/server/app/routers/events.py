"""GET /events — SSE stream of newly-ingested observations.

ADR-007 note: this only ever forwards `HazardObservation` records (place + geometry as
submitted, no LLM involved) to the client that submitted/subscribes to them — there is no
cloud LLM call anywhere in this module or in T5.3's scope. Nothing here builds a generic
"forward this payload to an LLM" helper; that is T4.4's job.
"""

from __future__ import annotations

from collections.abc import AsyncIterator

from fastapi import APIRouter, Request
from sse_starlette.sse import EventSourceResponse

router = APIRouter(tags=["events"])


@router.get("/events")
async def stream_events(request: Request) -> EventSourceResponse:
    broadcaster = request.app.state.broadcaster

    async def event_generator() -> AsyncIterator[dict[str, str]]:
        # sse-starlette's EventSourceResponse already watches for client disconnect and
        # cancels this generator when it happens; polling `request.is_disconnected()` here
        # as well is unnecessary and, under some ASGI transports (e.g. httpx's
        # ASGITransport used in tests), can race with it and hang.
        async with broadcaster.subscribe() as queue:
            while True:
                obs = await queue.get()
                yield {"event": "observation", "data": obs.model_dump_json()}

    return EventSourceResponse(event_generator())
