"""The two prompts the route-question model is trained and run with (ADR-035), and how a reply is read back.

Task U (understand): a question in, a JSON label out. Task W (write): the route's fact sheet, the question and the intents in, the
answer text out. Training, evaluation and (later) the app use these same builders, so what the model sees never differs between them.
No fact reaches the model except the fact sheet that `qaFactSheet` in `pulse_explain` writes from the route's own DecisionTrace.
"""

from __future__ import annotations

import json
import re

INTENTS = [
    "why_route", "time_distance", "alternatives", "avoided_streets", "route_hazard", "is_safe", "should_go", "confidence",
    "data_gaps", "travel_mode", "event_state", "accidents", "limits", "departure_time", "offline", "how_it_works", "help",
    "summary", "out_of_scope",
]

# The prompts are kept short on purpose: every prompt token costs training time and phone time. The rules are taught by the data (every
# target passed the verifier) and enforced at run time by the verifier, not by instructions the model might ignore.
SYSTEM_U = "Label the traveller's question about a route. Reply with JSON."

SYSTEM_W = "Answer the traveller from the FACTS only."


def messages_u(question: str, label: dict | None = None) -> list[dict]:
    msgs = [{"role": "system", "content": SYSTEM_U}, {"role": "user", "content": question}]
    if label is not None:
        msgs.append({"role": "assistant", "content": label_json(label["intent"], label.get("secondary"))})
    return msgs


def label_json(intent: str, secondary: str | None) -> str:
    return json.dumps({"intent": intent, "secondary": secondary}, separators=(", ", ": "))


def user_w(fact_sheet: str, question: str, intent: str, secondary: str | None) -> str:
    return f"FACTS:\n{fact_sheet}\n\nQUESTION: {question}\nINTENT: {intent}" + (f"\nALSO: {secondary}" if secondary else "")


def messages_w(fact_sheet: str, question: str, intent: str, secondary: str | None, answer: str | None = None) -> list[dict]:
    msgs = [{"role": "system", "content": SYSTEM_W}, {"role": "user", "content": user_w(fact_sheet, question, intent, secondary)}]
    if answer is not None:
        msgs.append({"role": "assistant", "content": answer})
    return msgs


def parse_label(text: str) -> tuple[str | None, str | None]:
    """Reads the model's JSON reply. Anything that is not a valid label gives (None, None): never a guess."""
    m = re.search(r"\{.*?\}", text, re.S)
    if not m:
        return None, None
    try:
        obj = json.loads(m.group(0))
    except json.JSONDecodeError:
        return None, None
    intent = obj.get("intent")
    sec = obj.get("secondary")
    if intent not in INTENTS:
        return None, None
    if sec is not None and (sec not in INTENTS or sec == intent):
        sec = None
    return intent, sec
