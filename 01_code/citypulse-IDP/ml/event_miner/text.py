"""Text checks that do not trust the model: the quote rule and name normalisation (ADR-030)."""

from __future__ import annotations

import re
import unicodedata

from ml.event_miner.schema import ModelEvent

_QUOTES = {"‘": "'", "’": "'", "“": '"', "”": '"', "–": "-", "—": "-", " ": " "}
MIN_QUOTE_CHARS = 12


def normalise(text: str) -> str:
    """For comparing quotes: Unicode NFC, plain quote marks and dashes, single spaces, case folded."""
    t = unicodedata.normalize("NFC", text)
    for a, b in _QUOTES.items():
        t = t.replace(a, b)
    return re.sub(r"\s+", " ", t).strip().casefold()


def name_key(text: str) -> str:
    """For comparing place names: letters and digits only (any script), single spaces, case folded.
    Combining marks are kept, because Tamil vowel signs are combining marks."""
    t = unicodedata.normalize("NFC", text).casefold()
    t = "".join(c if (c.isalnum() or unicodedata.category(c).startswith("M")) else " " for c in t)
    return re.sub(r"\s+", " ", t).strip()


def _strip_wrapping(quote: str) -> str:
    q = quote.strip()
    q = q.strip("\"'“”‘’")
    q = re.sub(r"^(\.\.\.|…)\s*|\s*(\.\.\.|…)$", "", q)
    return q.strip()


_SENTENCE_END = re.compile(r"(?<=[.!?।])\s+|\n+")


def _sentence_around(quote_norm: str, source_text: str) -> str | None:
    """The source sentence(s) that contain the quote, or None."""
    for sentence in _SENTENCE_END.split(source_text):
        if quote_norm in normalise(sentence):
            return sentence
    # a quote that spans a sentence boundary: fall back to the whole text
    return source_text if quote_norm in normalise(source_text) else None


def ground(event: ModelEvent, source_text: str) -> str | None:
    """None if the event may be kept; otherwise the reason it is dropped.

    - the quote must appear word for word in the source (after normalising spaces, quote marks and case);
    - it must be long enough to say something (at least 12 characters);
    - the place the model names must appear in the same source sentence as the quote, so the claim is about that place.
      (Prompt v1 required the place inside the quote; the model's Tamil quotes often left it out of an otherwise exact quote.)
    """
    quote = _strip_wrapping(event.quote)
    q = normalise(quote)
    if len(q) < MIN_QUOTE_CHARS:
        return "quote too short"
    sentence = _sentence_around(q, source_text)
    if sentence is None:
        return "quote not found in the source"
    if name_key(event.place_text) not in name_key(sentence):
        return "place not in the quoted sentence"
    return None
