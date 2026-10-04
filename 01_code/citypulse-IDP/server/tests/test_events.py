"""GET /events (SSE) — connects and yields on a new observation. Lightweight per task brief,
not exhaustive (no reconnect/backpressure testing).

Deliberately does NOT use `httpx.ASGITransport` here: that transport buffers the *entire*
ASGI response body before returning it to the caller, so it never completes against an
endless SSE stream (verified while writing this test — it hangs forever, not flakily). A
real socket, via a background `uvicorn` server on an ephemeral port, gets genuine incremental
streaming instead.
"""

from __future__ import annotations

import asyncio
import json
import threading
import time
from collections.abc import Iterator

import httpx
import pytest
import uvicorn
from conftest import make_observation_payload


@pytest.fixture
def live_server_url(monkeypatch: pytest.MonkeyPatch) -> Iterator[str]:
    monkeypatch.delenv("SUPABASE_URL", raising=False)
    from app.main import create_app

    app = create_app()
    config = uvicorn.Config(app, host="127.0.0.1", port=0, log_level="warning")
    server = uvicorn.Server(config)
    thread = threading.Thread(target=server.run, daemon=True)
    thread.start()

    deadline = time.monotonic() + 5.0
    while not server.started and time.monotonic() < deadline:
        time.sleep(0.01)
    assert server.started, "uvicorn test server did not start in time"

    port = server.servers[0].sockets[0].getsockname()[1]
    try:
        yield f"http://127.0.0.1:{port}"
    finally:
        server.should_exit = True
        thread.join(timeout=5)


async def test_sse_stream_yields_new_observation(live_server_url: str) -> None:
    payload = make_observation_payload()

    async with httpx.AsyncClient(base_url=live_server_url, timeout=5.0) as client:

        async def post_after_delay() -> None:
            await asyncio.sleep(0.2)
            resp = await client.post("/observations", json=payload)
            assert resp.status_code == 201

        poster = asyncio.create_task(post_after_delay())
        try:
            async with client.stream("GET", "/events") as response:
                assert response.status_code == 200
                received_event = False
                async for line in response.aiter_lines():
                    if line.startswith("data:"):
                        data = json.loads(line[len("data:") :].strip())
                        assert data["id"] == payload["id"]
                        received_event = True
                        break
                assert received_event
        finally:
            await poster
