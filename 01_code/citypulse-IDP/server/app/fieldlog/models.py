"""Field-log data model (ADR-028).

A volunteer at a site records what they SEE, with the time on their phone. This is research ground truth for the project's open question
(which streets are passable when it rains), not a statement to other users about any road: nothing here is shown to a traveller and, by
default, nothing here reaches the router's belief (see FIELDLOG_FEEDS_BELIEF in routers/fieldlog.py).

Privacy by design (DPDP): no names, no free text, no photos in v1. The volunteer is a short pseudonymous code issued by the operator. A site
is either one of the fixed candidate sites (position known, never sent by the phone) or "adhoc", where the volunteer chooses to send the
position of the spot, rounded to about 10 metres.
"""

from __future__ import annotations

import re
from datetime import datetime, timedelta, timezone
from enum import Enum
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

PROTOCOL_VERSION = "field-log-v1"
ADHOC_SITE = "adhoc"
# An entry may be logged offline and synced later; older than this is refused (the phone clock or the queue is wrong).
MAX_AGE = timedelta(days=14)
# Allowance for a phone clock a little ahead of the server.
MAX_FUTURE = timedelta(minutes=5)
# Tamil Nadu and a margin: an ad hoc point outside this is a mistake, not a Chennai-region observation.
ADHOC_BOUNDS = (8.0, 76.0, 14.5, 81.0)  # min_lat, min_lon, max_lat, max_lon
SITE_ID = re.compile(r"^[a-z0-9][a-z0-9_-]{1,31}$")
VOLUNTEER = re.compile(r"^[A-Za-z0-9_-]{2,24}$")


class PassState(str, Enum):
    """What the volunteer saw. `unknown` is a real answer ("I could not tell"), not a missing one."""

    passable = "passable"
    not_passable = "not_passable"
    unknown = "unknown"


class DepthBand(str, Enum):
    ankle = "ankle"
    knee = "knee"
    above_knee = "above_knee"
    unknown = "unknown"


class FieldLogEntry(BaseModel):
    """One observation as the phone sends it."""

    model_config = ConfigDict(extra="forbid")

    entry_id: UUID
    site_id: str
    state: PassState
    observed_at: datetime
    depth_band: DepthBand | None = None
    lat: float | None = None
    lon: float | None = None
    client: str = Field(default="web", max_length=40)

    @field_validator("site_id")
    @classmethod
    def _site_id_shape(cls, v: str) -> str:
        if not SITE_ID.match(v):
            raise ValueError("site_id must be 2 to 32 characters of a-z, 0-9, _ or -")
        return v

    @field_validator("observed_at")
    @classmethod
    def _aware(cls, v: datetime) -> datetime:
        if v.tzinfo is None:
            raise ValueError("observed_at must carry a time zone (RFC 3339)")
        return v.astimezone(timezone.utc)

    @field_validator("client")
    @classmethod
    def _client_plain(cls, v: str) -> str:
        if not re.fullmatch(r"[A-Za-z0-9._ -]*", v):
            raise ValueError(
                "client may only contain letters, digits, spaces and . _ -"
            )
        return v

    @model_validator(mode="after")
    def _consistent(self) -> FieldLogEntry:
        if self.depth_band is not None and self.state is not PassState.not_passable:
            raise ValueError("depth_band can only be given when state is not_passable")
        adhoc = self.site_id == ADHOC_SITE
        if adhoc:
            if self.lat is None or self.lon is None:
                raise ValueError("an adhoc entry needs lat and lon")
            lo_lat, lo_lon, hi_lat, hi_lon = ADHOC_BOUNDS
            if not (lo_lat <= self.lat <= hi_lat and lo_lon <= self.lon <= hi_lon):
                raise ValueError("lat/lon is outside the supported region")
            # About 10 m: the volunteer chose to share the spot, not an exact track of where they stood.
            self.lat, self.lon = round(self.lat, 4), round(self.lon, 4)
        elif self.lat is not None or self.lon is not None:
            raise ValueError(
                "lat and lon are only for adhoc entries; a known site's position is not sent"
            )
        return self

    def check_time(self, now: datetime) -> None:
        """Raises ValueError if the observation time is impossible. Separate from the model so tests can fix `now`."""
        if self.observed_at > now + MAX_FUTURE:
            raise ValueError("observed_at is in the future (is the phone clock wrong?)")
        if self.observed_at < now - MAX_AGE:
            raise ValueError("observed_at is more than 14 days old")


class StoredEntry(BaseModel):
    """What is kept: the entry plus what only the server knows."""

    model_config = ConfigDict(extra="forbid")

    protocol: Literal["field-log-v1"] = PROTOCOL_VERSION
    entry_id: UUID
    site_id: str
    state: PassState
    observed_at: datetime
    depth_band: DepthBand | None = None
    lat: float | None = None
    lon: float | None = None
    client: str
    volunteer: str
    received_at: datetime
    # received_at - observed_at, seconds: how late it was synced, and the first clue to a wrong phone clock.
    lag_seconds: int

    @classmethod
    def from_entry(
        cls, e: FieldLogEntry, volunteer: str, received_at: datetime
    ) -> StoredEntry:
        return cls(
            entry_id=e.entry_id,
            site_id=e.site_id,
            state=e.state,
            observed_at=e.observed_at,
            depth_band=e.depth_band,
            lat=e.lat,
            lon=e.lon,
            client=e.client,
            volunteer=volunteer,
            received_at=received_at,
            lag_seconds=int((received_at - e.observed_at).total_seconds()),
        )

    def content_key(self) -> tuple:
        """What must match for the same entry_id to count as a harmless repeat rather than a conflict."""
        return (
            self.site_id,
            self.state.value,
            self.observed_at.isoformat(),
            self.depth_band.value if self.depth_band else None,
            self.lat,
            self.lon,
            self.volunteer,
        )
