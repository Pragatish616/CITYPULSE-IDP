"""The independent checker for the route-question training data catches what it should (ADR-035)."""

import copy
import json
from pathlib import Path

import pytest

from ml.route_qa import validate_dataset as vd

ROOT = Path(__file__).resolve().parents[3]
SAMPLE = [json.loads(line) for line in (ROOT / "data/qa/2026-10-13/sample.jsonl").read_text(encoding="utf-8").splitlines() if line.strip()]


def _english_with(intent: str | None = None, low: bool | None = None):
    for r in SAMPLE:
        if r["locale"] != "en" or not r["answers"]:
            continue
        if intent and r["intent"] != intent:
            continue
        is_low = "confidence: low" in r["fact_sheet"] or "confidence: stale" in r["fact_sheet"]
        if low is not None and is_low != low:
            continue
        return copy.deepcopy(r)
    pytest.skip(f"no sample record for {intent} {low}")


def test_every_sample_record_is_valid() -> None:
    assert len(SAMPLE) >= 30
    for r in SAMPLE:
        assert vd.validate_record(r) == [], r["id"]


def test_the_sample_covers_both_languages_and_some_two_part_questions() -> None:
    assert {r["locale"] for r in SAMPLE} == {"en", "ta"}
    assert any(r["secondary"] for r in SAMPLE)


def test_a_banned_word_in_an_answer_is_caught() -> None:
    r = _english_with()
    r["answers"][0]["text"] = r["answers"][0]["text"].replace(r["answers"][0]["headline"], "The road is clear. " + r["answers"][0]["headline"], 1)
    r["answers"][0]["headline"] = "The road is clear. " + r["answers"][0]["headline"].split(". ")[0]
    assert any("banned word" in p for p in vd.validate_record(r))


def test_a_number_that_is_not_in_the_fact_sheet_is_caught() -> None:
    r = _english_with("time_distance")
    r["answers"][0]["text"] += " It will take 4242 minutes."
    assert any("4242" in p for p in vd.validate_record(r))


def test_a_safety_question_without_the_refusal_is_caught() -> None:
    r = _english_with("is_safe")
    r["answers"][0]["text"] = "Yes, go on."
    r["answers"][0]["headline"] = "Yes, go on."
    assert any("not refused" in p for p in vd.validate_record(r))


def test_low_confidence_without_the_hedge_is_caught() -> None:
    r = _english_with(low=True)
    t = r["answers"][0]["text"].replace("use your own judgement", "take care")
    r["answers"][0]["text"] = t
    r["answers"][0]["headline"] = t.split(". ")[0] + "."
    r["answers"][0]["headline"] = t[: len(r["answers"][0]["headline"])]
    assert any("hedge" in p for p in vd.validate_record(r))


def test_the_fixed_fallback_text_is_not_allowed_as_a_target() -> None:
    r = _english_with()
    r["answers"][0]["text"] = vd.FALLBACK_PREFIX + ". Hazard data may be limited, so use your own judgement."
    r["answers"][0]["headline"] = r["answers"][0]["text"]
    assert any("fallback" in p for p in vd.validate_record(r))


def test_a_tamil_answer_is_refused_unless_allowed() -> None:
    r = _english_with()
    r["locale"] = "ta"
    assert any("Tamil answer" in p for p in vd.validate_record(r))
    assert not any("Tamil answer" in p for p in vd.validate_record(r, allow_tamil_answers=True))


def test_a_bad_intent_secondary_and_long_question_are_caught() -> None:
    r = _english_with()
    r["intent"] = "make_coffee"
    r["secondary"] = "make_coffee"
    r["question"] = "x" * 201
    p = vd.validate_record(r)
    assert any("unknown intent" in x for x in p) and any("secondary" in x for x in p) and any("200" in x for x in p)


def test_a_street_name_with_a_banned_word_or_digits_is_not_a_false_alarm() -> None:
    r = _english_with()
    r["fact_sheet"] += "\nother_route C: 20 min; left_out_because: higher_cost; streets: Dry Dock Road (flooding reported 5 min ago), 100 Feet Road (hazard map only, no report)"
    t = r["answers"][0]["text"]
    r["answers"][0]["text"] = t + " It leaves out a stretch of Dry Dock Road and 100 Feet Road."
    assert not any("banned" in p or "100" in p for p in vd.validate_record(r))


def test_train_and_validation_must_not_share_a_situation(tmp_path: Path) -> None:
    a = copy.deepcopy(SAMPLE[0])
    a["split"] = "train"
    b = copy.deepcopy(SAMPLE[0])
    b["split"] = "val"
    (tmp_path / "t.jsonl").write_text(json.dumps(a, ensure_ascii=False) + "\n", encoding="utf-8")
    (tmp_path / "v.jsonl").write_text(json.dumps(b, ensure_ascii=False) + "\n", encoding="utf-8")
    rep = vd.validate_files(tmp_path / "t.jsonl", tmp_path / "v.jsonl")
    assert any("both train and val" in p for p in rep["problems"])


def test_a_question_from_the_sealed_test_set_is_refused(tmp_path: Path) -> None:
    a = copy.deepcopy(SAMPLE[0])
    a["split"] = "train"
    b = copy.deepcopy(SAMPLE[1])
    b["split"] = "val"
    b["situation_id"] = "other"
    (tmp_path / "t.jsonl").write_text(json.dumps(a, ensure_ascii=False) + "\n", encoding="utf-8")
    (tmp_path / "v.jsonl").write_text(json.dumps(b, ensure_ascii=False) + "\n", encoding="utf-8")
    sealed = tmp_path / "test_questions.json"
    sealed.write_text(json.dumps([{"text": a["question"].upper() + "!!"}]), encoding="utf-8")
    rep = vd.validate_files(tmp_path / "t.jsonl", tmp_path / "v.jsonl", sealed)
    assert any("sealed test set" in p for p in rep["problems"])
