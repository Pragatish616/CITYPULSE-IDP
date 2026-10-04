"""CORS is opt-in: no header unless the operator lists the origin (PLAN.md M2.5)."""

from __future__ import annotations

from fastapi.testclient import TestClient

from app.main import create_app


def _preflight(client: TestClient, origin: str):
    return client.options(
        "/observations",
        headers={
            "origin": origin,
            "access-control-request-method": "POST",
            "access-control-request-headers": "content-type",
        },
    )


def test_no_cors_headers_by_default(monkeypatch):
    monkeypatch.delenv("CORS_ALLOWED_ORIGINS", raising=False)
    client = TestClient(create_app())
    r = client.get("/health", headers={"origin": "https://evil.example"})
    assert "access-control-allow-origin" not in r.headers
    assert "access-control-allow-origin" not in _preflight(client, "https://evil.example").headers


def test_listed_origin_is_allowed_and_others_are_not(monkeypatch):
    monkeypatch.setenv("CORS_ALLOWED_ORIGINS", "https://app.example, http://localhost:5000")
    client = TestClient(create_app())
    ok = _preflight(client, "http://localhost:5000")
    assert ok.status_code == 200
    assert ok.headers["access-control-allow-origin"] == "http://localhost:5000"
    other = _preflight(client, "https://evil.example")
    assert "access-control-allow-origin" not in other.headers
