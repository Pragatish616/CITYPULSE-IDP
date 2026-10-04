"""Shared pytest fixtures.

Its mere presence at `server/` (pytest's default "prepend" import mode) puts `server/` on
`sys.path`, so `import app...` resolves regardless of the directory `pytest` is invoked from.
"""

from __future__ import annotations

from collections.abc import Iterator
from datetime import datetime, timezone
from typing import Any

import pytest
from app.main import create_app
from app.util import uuid7
from fastapi.testclient import TestClient


@pytest.fixture
def app_instance(monkeypatch: pytest.MonkeyPatch):
    # Force the in-memory backend regardless of a developer's real .env — tests never hit a
    # real database (no Supabase project exists yet; see server/README.md).
    monkeypatch.delenv("SUPABASE_URL", raising=False)
    return create_app()


@pytest.fixture
def client(app_instance) -> Iterator[TestClient]:
    with TestClient(app_instance) as c:
        yield c


def make_observation_payload(**overrides: Any) -> dict[str, Any]:
    """A minimal valid HazardObservation payload (docs/CONTRACTS.md §1), with overrides for
    tests that need to break one specific field.
    """
    payload: dict[str, Any] = {
        "id": str(uuid7()),
        "hazard_class": "flood",
        "polarity": 1,
        "geometry": {"type": "Point", "coordinates": [80.2707, 13.0827]},
        "accuracy_m": 12.0,
        "observed_at": datetime.now(timezone.utc).isoformat(),
        "source_class": "crowd",
        "source_id": "test-source",
        "precision_state": "exact",
    }
    payload.update(overrides)
    return payload
