"""HazardObservation validation — docs/CONTRACTS.md §1, exactly."""

from __future__ import annotations

from datetime import datetime, timezone

import pytest
from app.models import GeoPoint, HazardObservation
from conftest import make_observation_payload
from pydantic import ValidationError


def test_valid_observation_parses() -> None:
    obs = HazardObservation.model_validate(make_observation_payload())
    assert obs.hazard_class.value == "flood"
    assert obs.polarity == 1
    assert obs.precision_state == "exact"
    assert obs.coarsened_at is None
    # received_at is stamped by the model when the client doesn't supply one.
    assert obs.received_at is not None


def test_rejects_unknown_hazard_class() -> None:
    with pytest.raises(ValidationError):
        HazardObservation.model_validate(
            make_observation_payload(hazard_class="tsunami")
        )


@pytest.mark.parametrize("bad_polarity", [0, 2, -2, 1.5])
def test_rejects_polarity_outside_plus_minus_one(bad_polarity: object) -> None:
    with pytest.raises(ValidationError):
        HazardObservation.model_validate(
            make_observation_payload(polarity=bad_polarity)
        )


@pytest.mark.parametrize(
    "missing_field", ["id", "hazard_class", "geometry", "observed_at", "source_class"]
)
def test_rejects_missing_required_field(missing_field: str) -> None:
    payload = make_observation_payload()
    del payload[missing_field]
    with pytest.raises(ValidationError):
        HazardObservation.model_validate(payload)


def test_rejects_naive_timestamp() -> None:
    # fromisoformat with no offset produces a naive datetime deliberately — that's the test.
    naive_iso = datetime.fromisoformat("2026-09-12T05:14:22").isoformat()
    payload = make_observation_payload(observed_at=naive_iso)
    with pytest.raises(ValidationError):
        HazardObservation.model_validate(payload)


def test_coarsened_requires_coarsened_at() -> None:
    with pytest.raises(ValidationError):
        HazardObservation.model_validate(
            make_observation_payload(precision_state="coarsened")
        )


def test_coarsened_with_timestamp_is_valid() -> None:
    obs = HazardObservation.model_validate(
        make_observation_payload(
            precision_state="coarsened",
            coarsened_at=datetime.now(timezone.utc).isoformat(),
        )
    )
    assert obs.precision_state == "coarsened"


def test_geo_point_rejects_out_of_range_coordinates() -> None:
    with pytest.raises(ValidationError):
        GeoPoint(type="Point", coordinates=(200.0, 13.0))
