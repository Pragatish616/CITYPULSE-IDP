"""Event miner (ADR-030). A fake Ollama server stands in for the model: these tests prove the checks around the model work
(quote rule, gazetteer-only places, review, evaluation arithmetic), NOT that the model is accurate. No network."""

from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path

import httpx
import numpy as np
import pytest

from ml.event_miner import evaluate as ev
from ml.event_miner.gazetteer import (
    Place,
    Retriever,
    gazetteer_hash,
    lexical_score,
    load_places,
)
from ml.event_miner.llm import LLMError, OllamaClient
from ml.event_miner.miner import mine_item
from ml.event_miner.schema import ModelEvent, SourceItem
from ml.event_miner.store import MinerStore
from ml.event_miner.text import ground, name_key, normalise

WHEN = "2023-12-04T10:00:00+05:30"
SMALL = [
    Place("place:velachery", "Velachery", "suburb", 12.97, 80.22, ("வேளச்சேரி",)),
    Place("place:perambur", "Perambur", "suburb", 13.11, 80.23),
    Place("place:t-nagar", "Thiyagaraya Nagar", "suburb", 13.04, 80.23, ("T. Nagar", "T Nagar")),
    Place("tw1-0002", "Kalaingar Karunanidhi Road", "candidate site (street)", 12.95, 80.24),
]


def item(text: str, source: str = "Test source (made up)", published: str = WHEN, url: str = "") -> SourceItem:
    return SourceItem(text=text, source_name=source, published_at=published, source_url=url)


class FakeOllama:
    """Answers /api/chat from queues: one for extraction calls, one for place-choice calls. Records every request."""

    def __init__(self, extractions=(), choices=(), status: int = 200) -> None:
        self.extractions, self.choices, self.status = list(extractions), list(choices), status
        self.requests: list[dict] = []

    def handler(self, request: httpx.Request) -> httpx.Response:
        if self.status != 200:
            return httpx.Response(self.status, text="down")
        if request.url.path == "/api/tags":
            return httpx.Response(200, json={"models": [{"name": "qwen3.5:0.8b", "digest": "abc123def456"}]})
        body = json.loads(request.content)
        self.requests.append(body)
        if request.url.path == "/api/embed":
            return httpx.Response(200, json={"embeddings": [[1.0, 0.0] for _ in body["input"]]})
        props = body["format"]["properties"]
        answer = self.extractions.pop(0) if "events" in props else self.choices.pop(0)
        content = answer if isinstance(answer, str) else json.dumps(answer)
        return httpx.Response(200, json={"message": {"role": "assistant", "content": content}})

    def client(self) -> OllamaClient:
        return OllamaClient(base_url="http://ollama.test", model="qwen3.5:0.8b", transport=httpx.MockTransport(self.handler))


def event(place: str, condition: str, quote: str, time_text: str = "", depth: str = "") -> dict:
    return {"place_text": place, "condition": condition, "time_text": time_text, "depth_words": depth, "quote": quote}


# ---------------------------------------------------------------------------------------------- the quote rule


def test_a_quote_found_word_for_word_is_kept() -> None:
    src = "Traffic was diverted at the Perambur subway on Monday after rainwater stagnated."
    e = ModelEvent.model_validate(event("Perambur subway", "closed", "Traffic was diverted at the Perambur subway"))
    assert ground(e, src) is None


@pytest.mark.parametrize(
    ("quote", "place", "reason"),
    [
        ("Traffic was stopped at the Perambur subway", "Perambur subway", "quote not found in the source"),
        ("Perambur", "Perambur", "quote too short"),
        ("rainwater stagnated on Monday", "Perambur", "quote not found in the source"),
        ("Traffic was diverted at the Perambur subway", "Velachery", "place not in the quoted sentence"),
    ],
)
def test_a_quote_the_source_does_not_contain_is_dropped(quote, place, reason) -> None:
    src = "Traffic was diverted at the Perambur subway on Monday after rainwater stagnated."
    assert ground(ModelEvent.model_validate(event(place, "closed", quote)), src) == reason


def test_the_place_may_sit_outside_the_quote_but_must_be_in_the_same_sentence() -> None:
    src = "பெரம்பூர் சுரங்கப்பாதையில் மழைநீர் தேங்கியதால் போக்குவரத்து நிறுத்தப்பட்டது. வேளச்சேரியில் மழை பெய்தது."
    kept = ModelEvent.model_validate(
        event("பெரம்பூர் சுரங்கப்பாதை", "closed", "மழைநீர் தேங்கியதால் போக்குவரத்து நிறுத்தப்பட்டது.")
    )
    assert ground(kept, src) is None
    wrong_sentence = ModelEvent.model_validate(
        event("வேளச்சேரி", "closed", "மழைநீர் தேங்கியதால் போக்குவரத்து நிறுத்தப்பட்டது.")
    )
    assert ground(wrong_sentence, src) == "place not in the quoted sentence"


def test_spacing_case_and_curly_quotes_do_not_matter_but_words_do() -> None:
    src = "The “Madley” subway was   closed  to traffic."
    e = ModelEvent.model_validate(event("Madley subway", "closed", 'the "madley" subway was closed to traffic'))
    assert ground(e, src) is None


def test_tamil_quotes_and_names_keep_their_vowel_signs() -> None:
    src = "வேளச்சேரி பிரதான சாலையில் முழங்கால் அளவு தண்ணீர் தேங்கியுள்ளது."
    e = ModelEvent.model_validate(
        event("வேளச்சேரி பிரதான சாலை", "flooded", "வேளச்சேரி பிரதான சாலையில் முழங்கால் அளவு தண்ணீர்")
    )
    assert ground(e, src) is None
    assert name_key("வேளச்சேரி") != name_key("வளசசர"), "vowel signs are part of the name"
    assert normalise("A  B") == "a b"


# ---------------------------------------------------------------------------------------------- items


def test_an_item_needs_a_time_zone_and_gets_a_stable_id_and_a_language() -> None:
    with pytest.raises(ValueError, match="time zone"):
        item("x", published="2023-12-04T10:00:00")
    a, b = item("Rain at Perambur"), item("Rain at Perambur")
    assert a.item_id == b.item_id and len(a.item_id) == 16
    assert a.published_at == datetime(2023, 12, 4, 4, 30, tzinfo=timezone.utc)
    assert a.language == "en" and item("வேளச்சேரியில் மழை").language == "ta"


# ---------------------------------------------------------------------------------------------- the gazetteer


def test_the_real_gazetteer_loads_with_unique_ids_and_no_unnamed_sites() -> None:
    places = load_places()
    ids = [p.id for p in places]
    assert len(ids) == len(set(ids))
    osm = [p for p in places if p.id.startswith("place:")]
    subways = [p for p in places if p.id.startswith("sub-")]
    sites = [p for p in places if not p.id.startswith(("place:", "sub-"))]
    assert len(osm) == 661 and len(sites) == 186
    # 30 of the 31 subways can be placed: the news-only Choolaimedu one has neither a position nor an area
    assert len(subways) == 30 and "sub-news-choolaimedu-loyola" not in {p.id for p in subways}
    assert not any(p.name.lower().startswith("unnamed") for p in sites)
    kolathur = [p for p in osm if p.name == "Kolathur"]
    assert len(kolathur) == 2 and {p.id for p in kolathur} == {"place:kolathur", "place:kolathur-2"}


def test_lexical_matching_ignores_kind_words_and_reads_tamil_alternates() -> None:
    velachery = SMALL[0]
    assert lexical_score("Velachery", velachery) == 1.0
    assert lexical_score("Velachery subway", velachery) == 1.0
    assert lexical_score("வேளச்சேரி சாலை", velachery) == 1.0
    assert lexical_score("Perambur", velachery) < 0.6
    assert Retriever(SMALL).top("T Nagar subway", k=1)[0].id == "place:t-nagar"


def test_retrieval_is_deterministic_and_the_embedding_cache_is_keyed(tmp_path: Path) -> None:
    calls = {"n": 0}

    def embed(texts):
        calls["n"] += 1
        return [[float(len(t) % 7), 1.0, float(i)] for i, t in enumerate(texts)]

    cache = tmp_path / "emb.npz"
    r1 = Retriever(SMALL, embed=embed, cache_file=cache)
    top1 = r1.top("Perambur")
    assert top1[0].id == "place:perambur" and len(top1) <= 5
    docs_calls = calls["n"]
    r2 = Retriever(SMALL, embed=embed, cache_file=cache)
    assert [c.id for c in r2.top("Perambur")] == [c.id for c in top1]
    assert calls["n"] == docs_calls + 1, "documents came from the cache; only the query was embedded"
    data = np.load(cache)
    assert str(data["key"]) == gazetteer_hash(SMALL)


# ---------------------------------------------------------------------------------------------- the model client


def test_the_client_asks_for_deterministic_json_with_thinking_off() -> None:
    fake = FakeOllama(extractions=[{"events": []}])
    schema = {"type": "object", "properties": {"events": {"type": "array"}}}
    out = fake.client().chat_json("sys", "user", schema)
    assert out == {"events": []}
    body = fake.requests[0]
    assert body["think"] is False and body["stream"] is False
    assert body["options"]["temperature"] == 0 and body["options"]["seed"] == 20260918
    assert body["format"] == schema


def test_model_errors_are_errors_not_empty_answers() -> None:
    with pytest.raises(LLMError, match="returned 500"):
        FakeOllama(status=500).client().chat_json("s", "u", {"type": "object"})
    with pytest.raises(LLMError, match="did not answer JSON"):
        FakeOllama(extractions=["not json"]).client().chat_json("s", "u", {"type": "object", "properties": {"events": {}}})


def test_the_default_server_is_this_machine(monkeypatch) -> None:
    monkeypatch.delenv("OLLAMA_URL", raising=False)
    c = OllamaClient()
    assert c.base_url == "http://127.0.0.1:11434"
    c.close()


# ---------------------------------------------------------------------------------------------- the pipeline


def test_mining_keeps_grounded_events_drops_invented_ones_and_maps_only_to_listed_places() -> None:
    text = (
        "Traffic was diverted at the Perambur subway on Monday morning after rainwater stagnated. "
        "Water receded on Kalaingar Karunanidhi Road by 4 pm."
    )
    fake = FakeOllama(
        extractions=[{"events": [
            event("Perambur subway", "closed", "Traffic was diverted at the Perambur subway", "Monday morning"),
            event("Velachery", "flooded", "Velachery was under knee-deep water"),  # not in the text: invented
            event("Kalaingar Karunanidhi Road", "cleared", "Water receded on Kalaingar Karunanidhi Road by 4 pm", "by 4 pm"),
        ]}],
        choices=[{"choice": "c1"}, {"choice": "c9"}],  # c9 was never offered: treated as no match
    )
    client = fake.client()
    mined = mine_item(client, Retriever(SMALL), item(text), digest="abc")
    assert [e.place_text for e in mined.events] == ["Perambur subway", "Kalaingar Karunanidhi Road"]
    assert [d.reason for d in mined.dropped] == ["quote not found in the source"]
    assert mined.events[0].chosen_place_id == "place:perambur"
    assert mined.events[1].chosen_place_id is None
    assert mined.events[1].condition == "cleared"
    choice_formats = [r["format"] for r in fake.requests if "choice" in r["format"]["properties"]]
    assert choice_formats[0]["properties"]["choice"]["enum"][-1] == "none"
    assert mined.model_digest == "abc" and mined.prompt_version == "miner-prompt-v2"


def test_an_item_with_no_street_event_gives_none() -> None:
    fake = FakeOllama(extractions=[{"events": []}])
    mined = mine_item(fake.client(), Retriever(SMALL), item("Nungambakkam recorded 12 cm of rain."))
    assert mined.events == [] and mined.dropped == []


def test_events_that_break_the_schema_are_dropped_and_counted() -> None:
    fake = FakeOllama(extractions=[{"events": [{"place_text": "Perambur", "condition": "dry", "quote": "x"}]}])
    mined = mine_item(fake.client(), Retriever(SMALL), item("Perambur"))
    assert mined.events == [] and mined.dropped[0].reason == "not in the schema"


# ---------------------------------------------------------------------------------------------- review store


def mined_one(text: str, source: str = "Feed A", published: str = WHEN, choice: str = "c1"):
    fake = FakeOllama(
        extractions=[{"events": [event("Perambur subway", "closed", "Traffic was diverted at the Perambur subway")]}],
        choices=[{"choice": choice}],
    )
    return mine_item(fake.client(), Retriever(SMALL), item(text, source=source, published=published))


def test_review_is_append_only_latest_decision_wins_and_export_follows_it(tmp_path: Path) -> None:
    store = MinerStore(tmp_path)
    places = {p.id: p for p in SMALL}
    m = store.add(mined_one("Traffic was diverted at the Perambur subway today."))
    assert [(i.item_id, k) for i, k in store.pending()] == [(m.item_id, 0)]
    store.decide(m.item_id, 0, "reject", "v01", places)
    store.decide(m.item_id, 0, "correct", "v02", places, place_id="place:velachery", condition="flooded", note="re-read")
    assert store.pending() == []
    assert len(store.decisions_file.read_text(encoding="utf-8").splitlines()) == 2
    csv_text = store.export_csv(places)
    _header, row = csv_text.splitlines()
    assert "place:velachery" in row and ",flooded," in row and ",correct,v02," in row
    assert "Velachery" in row and "qwen3.5:0.8b" in row


def test_bad_decisions_are_refused(tmp_path: Path) -> None:
    store = MinerStore(tmp_path)
    places = {p.id: p for p in SMALL}
    m = store.add(mined_one("Traffic was diverted at the Perambur subway today."))
    with pytest.raises(KeyError):
        store.decide(m.item_id, 5, "accept", "v01", places)
    with pytest.raises(ValueError, match="not in the gazetteer"):
        store.decide(m.item_id, 0, "correct", "v01", places, place_id="place:atlantis")
    with pytest.raises(ValueError, match="needs a place id"):
        store.decide(m.item_id, 0, "correct", "v01", places)
    with pytest.raises(ValueError, match="only a correction"):
        store.decide(m.item_id, 0, "accept", "v01", places, condition="closed")
    with pytest.raises(ValueError):
        store.decide(m.item_id, 0, "accept", "a b c", places)


def test_a_repeat_from_the_same_source_within_six_hours_is_flagged_not_dropped(tmp_path: Path) -> None:
    store = MinerStore(tmp_path)
    first = store.add(mined_one("Traffic was diverted at the Perambur subway today."))
    again = store.add(mined_one("Traffic was diverted at the Perambur subway, police said.", published="2023-12-04T14:00:00+05:30"))
    other_source = store.add(mined_one("Traffic was diverted at the Perambur subway (feed B).", source="Feed B"))
    later = store.add(mined_one("Traffic was diverted at the Perambur subway again.", published="2023-12-05T10:00:00+05:30"))
    assert again.events[0].duplicate_of == f"{first.item_id}:0"
    assert other_source.events[0].duplicate_of is None and later.events[0].duplicate_of is None
    assert len(store.items()) == 4


def test_export_cells_cannot_become_spreadsheet_formulas(tmp_path: Path) -> None:
    store = MinerStore(tmp_path)
    places = {p.id: p for p in SMALL}
    m = store.add(mined_one("Traffic was diverted at the Perambur subway today.", source="=HYPERLINK(1)"))
    store.decide(m.item_id, 0, "accept", "v01", places)
    assert ",'=HYPERLINK(1)," in store.export_csv(places)


# ---------------------------------------------------------------------------------------------- evaluation


def test_matching_needs_the_same_place_and_the_same_condition() -> None:
    gold = [
        {"place_id": "place:perambur", "condition": "closed"},
        {"place_id": None, "place_text": "Ganesapuram subway", "condition": "flooded"},
    ]
    mined = [
        {"place_id": "place:perambur", "place_text": "Perambur subway", "condition": "flooded"},  # wrong condition
        {"place_id": None, "place_text": "Ganesapuram", "condition": "flooded"},  # same place text, no id
        {"place_id": "place:perambur", "place_text": "Perambur", "condition": "closed"},
    ]
    tp, pairs = ev.match_events(gold, mined)
    assert tp == 2 and pairs == [(0, 2), (1, 1)]


def test_scores_by_hand() -> None:
    places = {p.id: p for p in SMALL}
    rows = [
        {"gold": [{"place_id": "place:perambur", "condition": "closed"}],
         "mined": [{"place_id": "place:perambur", "condition": "closed"}, {"place_id": None, "place_text": "x", "condition": "unknown"}],
         "tp": 1, "dropped": 1, "seconds": 2.0},
        {"gold": [{"place_id": "place:velachery", "condition": "flooded"}, {"place_id": None, "place_text": "Madley subway", "condition": "closed"}],
         "mined": [{"place_id": "place:velachery", "condition": "cleared"}], "tp": 0, "dropped": 0, "seconds": 4.0},
        {"gold": [], "mined": [], "tp": 0, "dropped": 0, "seconds": 1.0},
    ]
    s = ev.score(rows, places)
    assert (s["precision"], s["recall"]) == (round(1 / 3, 4), round(1 / 3, 4))
    assert s["place_accuracy"] == 1.0 and s["place_within_200m"] == 1.0
    assert s["condition_accuracy_when_place_matched"] == 0.5
    assert s["share_dropped_by_quote_rule"] == 0.25
    assert s["share_gold_events_not_in_gazetteer"] == round(1 / 3, 4)
    assert s["useful_for_suggestions"] is False
    assert s["seconds_per_item"] == {"mean": 2.33, "median": 2.0, "max": 4.0}


def test_labels_are_checked_against_the_gazetteer_and_the_conditions() -> None:
    places = {p.id: p for p in SMALL}
    with pytest.raises(ValueError, match="not in the gazetteer"):
        ev.validate_labels([{"events": [{"place_id": "place:atlantis", "condition": "closed"}]}], places)
    with pytest.raises(ValueError, match="condition"):
        ev.validate_labels([{"events": [{"place_id": "place:perambur", "condition": "wet"}]}], places)
    with pytest.raises(ValueError, match="needs place_text"):
        ev.validate_labels([{"events": [{"place_id": None, "condition": "closed"}]}], places)


def test_agreement_between_two_labellers() -> None:
    labs = [
        {"events": [{"place_id": "place:perambur", "condition": "closed"}],
         "second_events": [{"place_id": "place:perambur", "condition": "closed"}]},
        {"events": [{"place_id": "place:perambur", "condition": "closed"}],
         "second_events": [{"place_id": "place:perambur", "condition": "flooded"}]},
        {"events": []},
    ]
    assert ev.agreement(labs) == {"items_labelled_twice": 2, "identical_label_sets": 1, "event_f1_between_labellers": 0.5}


def test_an_evaluation_run_writes_numbers_but_no_source_text_to_the_committed_result(tmp_path: Path) -> None:
    labels = tmp_path / "labels.jsonl"
    labels.write_text(json.dumps({
        "text": "SECRET-TEXT Traffic was diverted at the Perambur subway on Monday.",
        "source_name": "Feed A", "published_at": WHEN, "labeller": "v01",
        "events": [{"place_id": "place:perambur", "condition": "closed", "time_stated": True}],
    }) + "\n", encoding="utf-8")
    fake = FakeOllama(
        extractions=[{"events": [event("Perambur subway", "closed", "Traffic was diverted at the Perambur subway")]}],
        choices=[{"choice": "c1"}],
    )
    out, detail = tmp_path / "result", tmp_path / "detail"
    result = ev.run(labels, fake.client(), Retriever(SMALL), out_dir=out, detail_dir=detail, today="2026-10-08")
    assert result["overall"]["precision"] == 1.0 and result["overall"]["recall"] == 1.0
    assert result["meets_preregistered_size"] is False, "1 item is below the pre-registered 100"
    committed = (out / "result.json").read_text(encoding="utf-8")
    assert "SECRET-TEXT" not in committed and "Traffic was diverted" not in committed
    assert "SECRET-TEXT" in (detail / "2026-10-08.jsonl").read_text(encoding="utf-8")
