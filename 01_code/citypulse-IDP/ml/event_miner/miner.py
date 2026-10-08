"""The pipeline for one item (ADR-030): extract with a schema, drop what the source does not say, retrieve gazetteer
candidates, let the model pick one or none.

The prompts are fixed before any test item is labelled. The examples inside them are sentences written for the prompt (they are
not from any source and must never be copied from the test set). Changing them makes the next evaluation a second attempt.
"""

from __future__ import annotations

import time
from datetime import datetime, timezone

from ml.event_miner import PROMPT_VERSION
from ml.event_miner.gazetteer import Retriever
from ml.event_miner.llm import LLMError, OllamaClient
from ml.event_miner.schema import (
    MAX_EVENTS,
    Candidate,
    DroppedEvent,
    MinedEvent,
    MinedItem,
    ModelEvent,
    SourceItem,
    choice_schema,
    extraction_schema,
)
from ml.event_miner.text import ground

EXTRACT_SYSTEM = """You read short Chennai news items and official posts (English or Tamil) and list what they say about \
specific roads, streets, subways, bridges or junctions during rain. Answer only JSON in the given schema.

For each street-level event give:
- place_text: the place exactly as written in the text (keep the text's own language and spelling);
- condition, choosing the first that applies:
  "closed"  = traffic stopped, diverted, barricaded, or the road or subway is closed or not motorable;
  "cleared" = water drained or receded, traffic restored, road or subway reopened or motorable again;
  "flooded" = water, waterlogging or inundation on the road, without saying traffic is stopped;
  "unknown" = the place is mentioned in a rain context but its condition is not stated;
- time_text: the time or date as written, or "" if none;
- depth_words: any words about depth ("knee-deep", "2 feet"), or "";
- quote: the shortest exact words copied from the text that state this event, including the place name.

Do NOT list: rainfall amounts at a station or area ("Nungambakkam recorded 12 cm"), general advice, forecasts, or places \
named without a road condition. If the text states no street-level event, return {"events": []}. Never add anything the text \
does not say."""

EXAMPLES = """Example (made up): "Traffic was diverted at the Duraisamy subway on Monday morning after rainwater stagnated."
-> {"events":[{"place_text":"Duraisamy subway","condition":"closed","time_text":"Monday morning","depth_words":"",\
"quote":"Traffic was diverted at the Duraisamy subway"}]}

Example (made up): "Water receded in the Madley subway by 4 pm and vehicles are moving again. Meenambakkam recorded 9 cm."
-> {"events":[{"place_text":"Madley subway","condition":"cleared","time_text":"by 4 pm","depth_words":"",\
"quote":"Water receded in the Madley subway by 4 pm"}]}

Example (made up): "வேளச்சேரி பிரதான சாலையில் முழங்கால் அளவு தண்ணீர் தேங்கியுள்ளது."
-> {"events":[{"place_text":"வேளச்சேரி பிரதான சாலை","condition":"flooded","time_text":"",\
"depth_words":"முழங்கால் அளவு","quote":"வேளச்சேரி பிரதான சாலையில் முழங்கால் அளவு தண்ணீர் தேங்கியுள்ளது"}]}

Example (made up): "Residents are advised to stay indoors as heavy rain is likely tonight."
-> {"events":[]}"""

CHOOSE_SYSTEM = """You match a place named in a Chennai news item to a list of known places. Answer only JSON in the given \
schema: the id of the candidate that is the same place or, for a road, subway, bridge or junction, the area that contains it \
(for example "Perambur subway" -> the area Perambur). Answer "none" if no candidate is that place or its area. Do not guess \
between two different areas."""


def extract(client: OllamaClient, item: SourceItem) -> tuple[list[ModelEvent], list[DroppedEvent]]:
    # The examples go in the system message: in the user message the small model read them as part of the text (prompt v1).
    raw = client.chat_json(f"{EXTRACT_SYSTEM}\n\n{EXAMPLES}", item.text, extraction_schema())
    kept: list[ModelEvent] = []
    dropped: list[DroppedEvent] = []
    for e in raw.get("events", []) if isinstance(raw.get("events"), list) else []:
        try:
            ev = ModelEvent.model_validate(e)
        except ValueError:
            dropped.append(DroppedEvent(reason="not in the schema", event=e if isinstance(e, dict) else {"value": e}))
            continue
        why = ground(ev, item.text)
        if why:
            dropped.append(DroppedEvent(reason=why, event=ev.model_dump()))
        else:
            kept.append(ev)
    return kept[:MAX_EVENTS], dropped


def choose(client: OllamaClient, event: ModelEvent, candidates: list[Candidate]) -> str | None:
    if not candidates:
        return None
    labels = {f"c{i + 1}": c for i, c in enumerate(candidates)}
    listing = "\n".join(f"{lab}: {c.name} ({c.kind})" for lab, c in labels.items())
    raw = client.chat_json(
        CHOOSE_SYSTEM,
        f"Place in the text: {event.place_text}\nWords from the text: {event.quote}\n\nCandidates:\n{listing}",
        choice_schema(list(labels)),
    )
    pick = raw.get("choice")
    return labels[pick].id if isinstance(pick, str) and pick in labels else None


def mine_item(client: OllamaClient, retriever: Retriever, item: SourceItem, digest: str | None = None) -> MinedItem:
    started = time.perf_counter()
    kept, dropped = extract(client, item)
    events: list[MinedEvent] = []
    for i, ev in enumerate(kept):
        candidates = retriever.top(ev.place_text, k=5)
        try:
            chosen = choose(client, ev, candidates)
        except LLMError:
            chosen = None
        events.append(
            MinedEvent(
                index=i,
                place_text=ev.place_text,
                condition=ev.condition,
                time_text=ev.time_text,
                depth_words=ev.depth_words,
                quote=ev.quote,
                candidates=candidates,
                chosen_place_id=chosen,
            )
        )
    return MinedItem(
        item_id=item.item_id,
        source=item,
        language=item.language,
        mined_at=datetime.now(timezone.utc),
        model=client.model,
        model_digest=digest,
        embed_model=client.embed_model if retriever.embed is not None else None,
        prompt_version=PROMPT_VERSION,
        events=events,
        dropped=dropped,
        seconds=round(time.perf_counter() - started, 3),
    )
