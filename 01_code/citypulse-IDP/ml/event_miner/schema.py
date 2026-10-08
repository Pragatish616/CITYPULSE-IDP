"""What the miner reads, what the model must return, and what is kept (ADR-030)."""

from __future__ import annotations

import hashlib
from datetime import datetime, timezone
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

Condition = Literal["flooded", "closed", "cleared", "unknown"]
CONDITIONS: tuple[str, ...] = ("flooded", "closed", "cleared", "unknown")
MAX_EVENTS = 10


class ModelEvent(BaseModel):
    """One event as the model returns it. Checked again after the model (see text.ground)."""

    model_config = ConfigDict(extra="ignore")

    place_text: str = Field(min_length=1, max_length=160)
    condition: Condition
    time_text: str = Field(default="", max_length=120)
    depth_words: str = Field(default="", max_length=120)
    quote: str = Field(min_length=1, max_length=500)


class ModelExtraction(BaseModel):
    model_config = ConfigDict(extra="ignore")

    events: list[ModelEvent] = Field(default_factory=list, max_length=MAX_EVENTS)


def extraction_schema() -> dict:
    """The JSON schema given to Ollama's `format`, so the model can only answer in this shape."""
    return {
        "type": "object",
        "properties": {
            "events": {
                "type": "array",
                "maxItems": MAX_EVENTS,
                "items": {
                    "type": "object",
                    "properties": {
                        "place_text": {"type": "string"},
                        "condition": {"type": "string", "enum": list(CONDITIONS)},
                        "time_text": {"type": "string"},
                        "depth_words": {"type": "string"},
                        "quote": {"type": "string"},
                    },
                    "required": ["place_text", "condition", "time_text", "depth_words", "quote"],
                },
            }
        },
        "required": ["events"],
    }


def choice_schema(candidate_ids: list[str]) -> dict:
    """The model may answer only one of the listed ids, or `none`."""
    return {
        "type": "object",
        "properties": {"choice": {"type": "string", "enum": [*candidate_ids, "none"]}},
        "required": ["choice"],
    }


class SourceItem(BaseModel):
    """A post or news paragraph as an operator gives it."""

    model_config = ConfigDict(extra="forbid")

    text: str = Field(min_length=1, max_length=8000)
    source_url: str = Field(default="", max_length=500)
    source_name: str = Field(min_length=1, max_length=120)
    published_at: datetime

    @field_validator("published_at")
    @classmethod
    def _aware(cls, v: datetime) -> datetime:
        if v.tzinfo is None:
            raise ValueError("published_at needs a time zone, for example 2023-12-04T10:00+05:30")
        return v.astimezone(timezone.utc)

    @property
    def item_id(self) -> str:
        return hashlib.sha256(f"{self.source_url}\n{self.text}".encode()).hexdigest()[:16]

    @property
    def language(self) -> str:
        """`ta` if at least a fifth of the letters are Tamil script, else `en`. A rough label for reporting, not a detector."""
        letters = [c for c in self.text if c.isalpha()]
        tamil = sum(1 for c in letters if "஀" <= c <= "௿")
        return "ta" if letters and tamil / len(letters) >= 0.2 else "en"


class Candidate(BaseModel):
    id: str
    name: str
    kind: str
    lat: float
    lon: float
    score: float


class MinedEvent(BaseModel):
    index: int
    place_text: str
    condition: Condition
    time_text: str
    depth_words: str
    quote: str
    candidates: list[Candidate]
    chosen_place_id: str | None
    duplicate_of: str | None = None

    @property
    def chosen(self) -> Candidate | None:
        return next((c for c in self.candidates if c.id == self.chosen_place_id), None)


class DroppedEvent(BaseModel):
    reason: str
    event: dict


class MinedItem(BaseModel):
    """What is stored for one source item. The text is kept (locally, git-ignored) so a reviewer can read the context."""

    item_id: str
    source: SourceItem
    language: str
    mined_at: datetime
    model: str
    model_digest: str | None
    embed_model: str | None
    prompt_version: str
    events: list[MinedEvent]
    dropped: list[DroppedEvent]
    seconds: float
