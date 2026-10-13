"""Independent checks on the route-question training data (ADR-035, PREREGISTRATION_QA.md addendum 1).

The data are written by `packages/pulse_explain/tool/gen_qa_data.dart`, whose answers already passed the Dart verifier. This
checker is deliberately separate code (Python, standard library only), so the training data are not graded only by the program
that wrote them. It checks, per record and across the two files:

* the record has the fields and values it should (19 intents, two splits, two languages, a question of at most 200 characters);
* no English answer contains a word the app must never use about a road (ADR-011), after the trace's own street names are removed;
* every number in an answer is one of the fact sheet's numbers, or the difference of two of them (within a minute of rounding);
* a safety question is always refused, never answered with a verdict;
* an answer under low or stale confidence carries a hedge;
* no answer is the fixed fallback text; Tamil answers exist only when explicitly allowed;
* train and validation share no situation; no question equals a question in the sealed test file when that file exists.

    python ml/route_qa/validate_dataset.py data/qa/2026-10-13/generated/train.jsonl data/qa/2026-10-13/generated/val.jsonl
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

INTENTS = {
    "why_route", "time_distance", "alternatives", "avoided_streets", "route_hazard", "is_safe", "should_go", "confidence",
    "data_gaps", "travel_mode", "event_state", "accidents", "limits", "departure_time", "offline", "how_it_works", "help",
    "summary", "out_of_scope",
}
FALLBACK_PREFIX = "I cannot answer that from the route data"
REFUSAL = "I cannot confirm the condition of any road"
BANNED = re.compile(r"\b(safe|safely|safest|unsafe|dry|clear|open|passable|fine|ok|okay|guaranteed)\b|go ahead|green light", re.I)
NUMBER = re.compile(r"\d+(?:\.\d+)?")
MAX_QUESTION = 200


def _names(sheet: str) -> list[str]:
    """Street and corridor names the fact sheet itself contains (they may hold words such as 'Dry' or digits)."""
    names: list[str] = []
    for line in sheet.splitlines():
        if line.startswith("other_route") and "streets:" in line:
            for part in re.split(r"\), ", line.split("streets:", 1)[1]):
                names.append(part.split(" (")[0].strip())
        elif line.startswith("no_recent_data_for:"):
            names += [n.strip() for n in line.split(":", 1)[1].split(",")]
        elif line.startswith("fact "):
            names.append(line)
    return [n for n in names if n]


def _allowed_numbers(sheet: str) -> set[str]:
    out: set[str] = set()
    minutes: list[float] = []
    for line in sheet.splitlines():
        for key in ("time_min", "distance_km", "hazard_delay_min"):
            m = re.search(rf"{key}: (\d+(?:\.\d+)?)", line)
            if m:
                out.add(m.group(1))
                if key == "time_min":
                    minutes.append(float(m.group(1)))
        if line.startswith("other_route"):
            m = re.search(r": (\d+) min;", line)
            if m:
                out.add(m.group(1))
                minutes.append(float(m.group(1)))
            out.update(re.findall(r"reported (\d+) min ago", line))
    return out | _delta_candidates(minutes)


def _delta_candidates(minutes: list[float]) -> set[str]:
    out: set[str] = set()
    if not minutes:
        return out
    base = minutes[0]
    for other in minutes[1:]:
        d = int(abs(base - other))
        out.update({str(d - 1), str(d), str(d + 1)})
    return {x for x in out if not x.startswith("-")}


def _strip(text: str, names: list[str]) -> str:
    for n in sorted(names, key=len, reverse=True):
        text = text.replace(n, " ")
    return text


def validate_record(rec: dict, *, allow_tamil_answers: bool = False) -> list[str]:
    problems: list[str] = []
    for k in ("id", "situation_id", "split", "locale", "question", "intent", "fact_sheet", "answers"):
        if k not in rec:
            problems.append(f"missing field {k}")
    if problems:
        return problems
    if rec["split"] not in ("train", "val"):
        problems.append(f"bad split {rec['split']}")
    if rec["locale"] not in ("en", "ta"):
        problems.append(f"bad locale {rec['locale']}")
    if rec["intent"] not in INTENTS:
        problems.append(f"unknown intent {rec['intent']}")
    sec = rec.get("secondary")
    if sec is not None and (sec not in INTENTS or sec == rec["intent"]):
        problems.append(f"bad secondary {sec}")
    if not rec["question"].strip() or len(rec["question"]) > MAX_QUESTION:
        problems.append("question empty or longer than 200 characters")
    sheet = rec["fact_sheet"]
    names = _names(sheet)
    allowed = _allowed_numbers(sheet)
    band = re.search(r"confidence: (\w+)", sheet)
    low = bool(band) and band.group(1) in ("low", "stale")
    if rec["locale"] == "ta" and rec["answers"] and not allow_tamil_answers:
        problems.append("a Tamil answer is present although Tamil answers are not approved")
    seen: set[int] = set()
    for a in rec["answers"]:
        text = a.get("text", "")
        if not text.strip():
            problems.append("empty answer")
            continue
        if a.get("style") in seen:
            problems.append("duplicate style")
        seen.add(a.get("style"))
        if text.startswith(FALLBACK_PREFIX):
            problems.append("an answer is the fixed fallback")
        if rec["locale"] == "en":
            if BANNED.search(_strip(text, names)):
                problems.append(f"banned word in answer: {BANNED.search(_strip(text, names)).group(0)}")
            for n in NUMBER.findall(_strip(text, names)):
                if n not in allowed:
                    problems.append(f"number {n} is not in the fact sheet")
            if rec["intent"] == "is_safe" and REFUSAL not in text:
                problems.append("a safety question was not refused")
            if low and "use your own judgement" not in text:
                problems.append("low or stale confidence without the hedge")
        if not text.startswith(a.get("headline", "")):
            problems.append("headline is not the start of the answer")
    return problems


def _norm(s: str) -> str:
    return re.sub(r"\s+", " ", re.sub(r"[^\w\s]", " ", s.lower())).strip()


def validate_files(train: Path, val: Path, sealed: Path | None = None, *, allow_tamil_answers: bool = False) -> dict:
    report: dict = {"problems": [], "records": {}, "intents_missing": []}
    sit: dict[str, set[str]] = {}
    sealed_q: set[str] = set()
    if sealed is not None and sealed.exists():
        sealed_q = {_norm(q["text"]) for q in json.loads(sealed.read_text(encoding="utf-8"))}
    counts: dict[str, int] = {}
    for name, path in (("train", train), ("val", val)):
        n = 0
        sit[name] = set()
        for line_no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if not line.strip():
                continue
            rec = json.loads(line)
            n += 1
            sit[name].add(rec.get("situation_id", ""))
            if rec.get("split") != name:
                report["problems"].append(f"{name}:{line_no} record says split {rec.get('split')}")
            for p in validate_record(rec, allow_tamil_answers=allow_tamil_answers):
                report["problems"].append(f"{name}:{line_no} {rec.get('id')}: {p}")
            if _norm(rec.get("question", "")) in sealed_q:
                report["problems"].append(f"{name}:{line_no} the question is in the sealed test set")
            counts[rec.get("intent", "?")] = counts.get(rec.get("intent", "?"), 0) + 1
        report["records"][name] = n
    both = sit["train"] & sit["val"]
    if both:
        report["problems"].append(f"{len(both)} situations are in both train and val")
    report["intents_missing"] = sorted(INTENTS - set(counts))
    if report["intents_missing"]:
        report["problems"].append(f"intents with no record: {report['intents_missing']}")
    report["by_intent"] = counts
    return report


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(__doc__)
        return 2
    sealed = Path(argv[3]) if len(argv) > 3 else Path("data/qa/2026-10-13/test_questions.json")
    rep = validate_files(Path(argv[1]), Path(argv[2]), sealed)
    print(json.dumps({k: v for k, v in rep.items() if k != "problems"}, indent=1))
    print(f"{len(rep['problems'])} problems")
    for p in rep["problems"][:30]:
        print("  ", p)
    return 1 if rep["problems"] else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
