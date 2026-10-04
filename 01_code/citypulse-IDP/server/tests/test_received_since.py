"""Sync cursor on server arrival time (KNOWN_FLAWS F-10)."""

from __future__ import annotations

import time
from datetime import datetime, timedelta, timezone

from conftest import make_observation_payload
from fastapi.testclient import TestClient


def test_late_upload_of_an_old_report_is_found_by_received_since(client: TestClient) -> None:
    cursor = datetime.now(timezone.utc)
    time.sleep(0.01)  # arrival pacing only: the server stamps received_at from its own clock
    old = make_observation_payload(
        observed_at=(cursor - timedelta(hours=2)).isoformat()  # made offline two hours ago
    )
    assert client.post("/observations", json=old).status_code == 201

    # The old observed_at cursor misses it; the arrival cursor does not.
    by_observed = client.get("/observations", params={"since": cursor.isoformat()}).json()
    assert old["id"] not in [o["id"] for o in by_observed]
    by_received = client.get(
        "/observations", params={"received_since": cursor.isoformat()}
    ).json()
    assert old["id"] in [o["id"] for o in by_received]


def test_received_at_is_the_servers_clock_not_the_clients(client: TestClient) -> None:
    forged = make_observation_payload(
        received_at=(datetime.now(timezone.utc) - timedelta(days=30)).isoformat()
    )
    before = datetime.now(timezone.utc)
    assert client.post("/observations", json=forged).status_code == 201
    row = next(o for o in client.get("/observations").json() if o["id"] == forged["id"])
    stored = datetime.fromisoformat(row["received_at"].replace("Z", "+00:00"))
    assert stored >= before


def test_received_since_orders_by_arrival(client: TestClient) -> None:
    start = datetime.now(timezone.utc)
    time.sleep(0.01)
    first = make_observation_payload(observed_at=(start - timedelta(hours=1)).isoformat())
    time.sleep(0.01)
    second = make_observation_payload(observed_at=(start - timedelta(hours=5)).isoformat())
    for p in (first, second):
        assert client.post("/observations", json=p).status_code == 201
        time.sleep(0.01)
    rows = client.get("/observations", params={"received_since": start.isoformat()}).json()
    assert [o["id"] for o in rows] == [first["id"], second["id"]]
