"""POST/GET /observations — ingest, G-Set dedup (ADR-008), and bbox/time filtering."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

from conftest import make_observation_payload
from fastapi.testclient import TestClient


def test_health(client: TestClient) -> None:
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok"}


def test_post_valid_observation_is_accepted(client: TestClient) -> None:
    payload = make_observation_payload()
    resp = client.post("/observations", json=payload)
    assert resp.status_code == 201
    body = resp.json()
    assert body["id"] == payload["id"]
    assert body["inserted"] is True


def test_post_malformed_hazard_class_is_rejected_422(client: TestClient) -> None:
    payload = make_observation_payload(hazard_class="not_a_real_class")
    resp = client.post("/observations", json=payload)
    assert resp.status_code == 422


def test_post_missing_required_field_is_rejected_422(client: TestClient) -> None:
    payload = make_observation_payload()
    del payload["source_id"]
    resp = client.post("/observations", json=payload)
    assert resp.status_code == 422


def test_post_polarity_outside_domain_is_rejected_422(client: TestClient) -> None:
    payload = make_observation_payload(polarity=0)
    resp = client.post("/observations", json=payload)
    assert resp.status_code == 422


def test_posting_same_id_twice_does_not_duplicate(client: TestClient) -> None:
    payload = make_observation_payload()

    first = client.post("/observations", json=payload)
    assert first.status_code == 201
    assert first.json()["inserted"] is True

    second = client.post("/observations", json=payload)
    assert second.status_code == 201
    assert (
        second.json()["inserted"] is False
    )  # ON CONFLICT DO NOTHING semantics (ADR-008)

    listed = client.get("/observations").json()
    matching = [o for o in listed if o["id"] == payload["id"]]
    assert len(matching) == 1


def test_get_observations_filters_by_bbox(client: TestClient) -> None:
    inside = make_observation_payload(
        geometry={"type": "Point", "coordinates": [80.27, 13.08]}
    )
    outside = make_observation_payload(
        geometry={"type": "Point", "coordinates": [77.59, 12.97]}
    )  # Bangalore
    client.post("/observations", json=inside)
    client.post("/observations", json=outside)

    resp = client.get(
        "/observations",
        params={"min_lon": 80.0, "min_lat": 12.8, "max_lon": 80.5, "max_lat": 13.3},
    )
    assert resp.status_code == 200
    ids = {o["id"] for o in resp.json()}
    assert inside["id"] in ids
    assert outside["id"] not in ids


def test_get_observations_requires_full_bbox(client: TestClient) -> None:
    resp = client.get("/observations", params={"min_lon": 80.0})
    assert resp.status_code == 422


def test_get_observations_filters_by_time_window(client: TestClient) -> None:
    now = datetime.now(timezone.utc)
    old = make_observation_payload(observed_at=(now - timedelta(days=2)).isoformat())
    recent = make_observation_payload(observed_at=now.isoformat())
    client.post("/observations", json=old)
    client.post("/observations", json=recent)

    resp = client.get(
        "/observations", params={"since": (now - timedelta(hours=1)).isoformat()}
    )
    ids = {o["id"] for o in resp.json()}
    assert recent["id"] in ids
    assert old["id"] not in ids
