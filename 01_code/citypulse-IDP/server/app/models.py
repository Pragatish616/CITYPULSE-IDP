"""Pydantic models mirroring docs/CONTRACTS.md exactly.

These are shared interfaces (CONTRACTS.md preamble: "change only by ADR"). Two models live
here in T5.3's scope:

- `HazardObservation` (CONTRACTS.md §1) — the append-only ingest unit, including the
  `precision_state`/`coarsened_at` pair added by ADR-010.
- `EdgeBelief` (CONTRACTS.md §2) — a read model. Nothing in this server computes belief
  fusion (that is T1.2, `packages/pulse_belief`); it is modelled here only so a future
  `GET /edges/{id}/belief`-style endpoint has a typed shape to return, per the task brief.

Judgement call (documented per CLAUDE.md §4 — flag, don't silently resolve): ADR-009 says
HazardObservation "gains `watchlist_point_id`", but the worked example in CONTRACTS.md §1
(last touched 2026-09-12) does not show that field — ADR-009's consequence was written
2026-09-14, after CONTRACTS.md's own last edit, and CONTRACTS.md was never updated to match.
Rather than silently ignoring the ADR (CLAUDE.md §"Hard rules") or silently inventing a
field the contract doesn't show, `watchlist_point_id` is added here as `Optional[str] = None`
— additive, so every existing example in CONTRACTS.md §1 still validates unchanged. This
inconsistency should be reconciled in CONTRACTS.md directly; see server/README.md.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Annotated, Any, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from app.config import HazardClass, SourceClass

Longitude = Annotated[float, Field(ge=-180.0, le=180.0)]
Latitude = Annotated[float, Field(ge=-90.0, le=90.0)]


class GeoPoint(BaseModel):
    """GeoJSON Point, [longitude, latitude] per RFC 7946 (and CONTRACTS.md §1's example)."""

    model_config = ConfigDict(extra="forbid")

    type: Literal["Point"] = "Point"
    coordinates: tuple[Longitude, Latitude]


class HazardObservation(BaseModel):
    """docs/CONTRACTS.md §1 — an immutable claim that something was true at a place at a time.

    Never edited or deleted (ADR-008: append-only G-Set CRDT). A later observation with
    opposite polarity supersedes an earlier one only in belief fusion, never in storage.
    """

    model_config = ConfigDict(extra="forbid")

    id: UUID
    hazard_class: HazardClass
    polarity: Literal[1, -1]
    geometry: GeoPoint
    accuracy_m: float = Field(ge=0)
    observed_at: datetime
    received_at: datetime | None = None
    source_class: SourceClass
    source_id: str = Field(min_length=1)
    intensity: dict[str, Any] | None = None
    raw: dict[str, Any] = Field(default_factory=dict)
    precision_state: Literal["exact", "coarsened"] = "exact"
    coarsened_at: datetime | None = None
    # ADR-009 consequence, not yet reflected in CONTRACTS.md §1's example — see module docstring.
    watchlist_point_id: str | None = None

    @field_validator("observed_at", "received_at", "coarsened_at")
    @classmethod
    def _require_timezone_aware(cls, v: datetime | None) -> datetime | None:
        if v is not None and v.tzinfo is None:
            raise ValueError(
                "timestamp must be timezone-aware (RFC 3339 UTC per CONTRACTS.md)"
            )
        return v

    @model_validator(mode="after")
    def _defaults_and_consistency(self) -> HazardObservation:
        # received_at is the server's ingest-time stamp when a client/worker doesn't supply
        # one; CONTRACTS.md §1 says "decay runs on observed_at, latency analysis on the
        # difference [with received_at]" — that difference is only meaningful if received_at
        # reflects actual receipt, so we stamp it here rather than trusting an absent value
        # to mean anything else.
        if self.received_at is None:
            self.received_at = datetime.now(timezone.utc)
        if self.precision_state == "coarsened" and self.coarsened_at is None:
            raise ValueError(
                "coarsened_at is required when precision_state is 'coarsened' (ADR-010)"
            )
        if self.precision_state == "exact" and self.coarsened_at is not None:
            raise ValueError(
                "coarsened_at must be null while precision_state is 'exact' (ADR-010)"
            )
        return self


class EdgeBelief(BaseModel):
    """docs/CONTRACTS.md §2 — what the router reads. Read model only; not written here."""

    model_config = ConfigDict(extra="forbid")

    edge_id: int
    hazard_class: HazardClass
    prior_logodds: float
    posterior_logodds: float
    p_mean: float = Field(ge=0, le=1)
    n_eff: float = Field(ge=0)
    p_pessimistic: float = Field(ge=0, le=1)
    z: float
    newest_observation_at: datetime
    contributing_observations: list[UUID]
