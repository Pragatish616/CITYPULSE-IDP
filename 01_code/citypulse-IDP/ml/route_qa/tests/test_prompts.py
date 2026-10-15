"""The prompts the route-question model is trained and run with are built and read back the same way everywhere (ADR-035)."""

import json

from ml.route_qa import prompts as p


def test_the_label_json_round_trips() -> None:
    for intent in p.INTENTS:
        for sec in (None, "route_hazard"):
            if sec == intent:
                continue
            assert p.parse_label(p.label_json(intent, sec)) == (intent, sec)


def test_a_reply_that_is_not_a_valid_label_is_never_guessed() -> None:
    for bad in ["", "sure!", "{}", '{"intent": "confirmation"}', '{"intent": 3}', "{intent: time_distance}", '{"intent": "time_distance"']:
        assert p.parse_label(bad) == (None, None), bad


def test_a_secondary_equal_to_the_first_or_unknown_is_dropped_not_trusted() -> None:
    assert p.parse_label('{"intent": "why_route", "secondary": "why_route"}') == ("why_route", None)
    assert p.parse_label('{"intent": "why_route", "secondary": "nonsense"}') == ("why_route", None)


def test_json_inside_chatter_is_still_read() -> None:
    assert p.parse_label('Here you go: {"intent": "help", "secondary": null} done') == ("help", None)


def test_the_first_object_is_read_even_inside_brackets() -> None:
    # The Dart reader (packages/pulse_explain/lib/src/question_labeler.dart) must do the same; its test has this case too.
    assert p.parse_label('[{"intent": "help"}]') == ("help", None)


def test_the_message_builders_end_with_the_reply_only_when_one_is_given() -> None:
    q = p.messages_u("how long")
    assert [m["role"] for m in q] == ["system", "user"]
    full = p.messages_u("how long", {"intent": "time_distance", "secondary": None})
    assert [m["role"] for m in full] == ["system", "user", "assistant"]
    assert json.loads(full[-1]["content"]) == {"intent": "time_distance", "secondary": None}
    w = p.messages_w("route: A", "why this route", "why_route", "route_hazard", "Because.")
    assert w[-1]["content"] == "Because." and "ALSO: route_hazard" in w[1]["content"] and "FACTS:\nroute: A" in w[1]["content"]


def test_the_prompts_are_short_because_every_token_costs_phone_time() -> None:
    assert len(p.SYSTEM_U.split()) < 20 and len(p.SYSTEM_W.split()) < 20


def test_the_prompt_holds_nothing_but_the_fact_sheet_the_question_and_the_intents() -> None:
    sheet = "route: A\ntime_min: 17"
    text = p.user_w(sheet, "how long", "time_distance", None)
    assert text == f"FACTS:\n{sheet}\n\nQUESTION: how long\nINTENT: time_distance"
