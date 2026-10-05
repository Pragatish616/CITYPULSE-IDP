"""Field log (ADR-028): model rules, the append-only store, tokens and limits, and the HTTP surface. No network, no real clock."""

from __future__ import annotations

import csv
import io
import json
import threading
from datetime import datetime, timedelta, timezone
from uuid import uuid4

import pytest
from pydantic import ValidationError

from app.fieldlog.models import FieldLogEntry, PassState, StoredEntry
from app.fieldlog.service import FieldLogService, TokenBook, Window
from app.fieldlog.store import CSV_HEADER, Conflict, FieldLogStore, to_csv_row

NOW = datetime(2026, 10, 5, 18, 0, tzinfo=timezone.utc)
TOKEN_A = "tok-alice-0123456789"
TOKEN_B = "tok-bob---0123456789"
ADMIN = "admin-token-0123456789"
KNOWN_SITE = "tw1-0004"


def payload(**kw) -> dict:
    p = {
        "entry_id": str(uuid4()),
        "site_id": KNOWN_SITE,
        "state": "not_passable",
        "observed_at": (NOW - timedelta(minutes=2)).isoformat(),
        "depth_band": "knee",
        "client": "web-1",
    }
    p.update(kw)
    return {k: v for k, v in p.items() if v is not None}


def make_service(tmp_path, **kw) -> FieldLogService:
    args = {
        "directory": tmp_path,
        "tokens": f"alice:{TOKEN_A},bob:{TOKEN_B}",
        "admin_token": ADMIN,
        "now": lambda: NOW,
    }
    args.update(kw)
    return FieldLogService(**args)


@pytest.fixture
def svc(tmp_path) -> FieldLogService:
    return make_service(tmp_path)


@pytest.fixture
def api(client, app_instance, svc):
    app_instance.state.fieldlog = svc
    return client


# ---------------------------------------------------------------------------------------------- the model


def test_a_good_entry_parses_and_is_normalised_to_utc() -> None:
    e = FieldLogEntry.model_validate(payload(observed_at="2026-10-05T23:30:00+05:30"))
    assert e.observed_at == datetime(2026, 10, 5, 18, 0, tzinfo=timezone.utc)


@pytest.mark.parametrize(
    "bad",
    [
        {"observed_at": "2026-10-05T18:00:00"},  # no time zone
        {"state": "dry"},  # not one of the three answers
        {"site_id": "Has Space"},
        {"site_id": ""},
        {"entry_id": "not-a-uuid"},
        {"state": "passable", "depth_band": "knee"},  # depth only with not_passable
        {"lat": 13.0, "lon": 80.2},  # a known site never sends a position
        {"note": "free text is not accepted"},  # extra fields are refused
        {"client": "<script>"},
        {"client": "x" * 41},
    ],
)
def test_bad_entries_are_refused(bad: dict) -> None:
    with pytest.raises(ValidationError):
        FieldLogEntry.model_validate(payload(**bad))


def test_adhoc_needs_a_position_inside_the_region_and_is_rounded() -> None:
    e = FieldLogEntry.model_validate(
        payload(
            site_id="adhoc",
            depth_band=None,
            state="unknown",
            lat=13.08273999,
            lon=80.27071999,
        )
    )
    assert (e.lat, e.lon) == (13.0827, 80.2707)
    for bad in (
        {"lat": None, "lon": None},
        {"lat": 28.6, "lon": 77.2},
        {"lat": 13.0, "lon": None},
    ):
        with pytest.raises(ValidationError):
            FieldLogEntry.model_validate(
                payload(
                    site_id="adhoc",
                    depth_band=None,
                    state="unknown",
                    **{"lat": 13.0, "lon": 80.2, **bad},
                )
            )


def test_time_rules_future_and_stale() -> None:
    FieldLogEntry.model_validate(payload()).check_time(NOW)
    with pytest.raises(ValueError, match="future"):
        FieldLogEntry.model_validate(
            payload(observed_at=(NOW + timedelta(minutes=6)).isoformat())
        ).check_time(NOW)
    FieldLogEntry.model_validate(
        payload(observed_at=(NOW + timedelta(minutes=4)).isoformat())
    ).check_time(NOW)
    with pytest.raises(ValueError, match="14 days"):
        FieldLogEntry.model_validate(
            payload(observed_at=(NOW - timedelta(days=15)).isoformat())
        ).check_time(NOW)


# ---------------------------------------------------------------------------------------------- the store


def stored(volunteer="alice", **kw) -> StoredEntry:
    return StoredEntry.from_entry(
        FieldLogEntry.model_validate(payload(**kw)), volunteer, NOW
    )


def test_store_appends_and_survives_a_restart(tmp_path) -> None:
    s = FieldLogStore(tmp_path)
    a, b = stored(), stored(state="passable", depth_band=None)
    assert s.add(a) is True and s.add(b) is True
    s2 = FieldLogStore(tmp_path)  # a new process
    assert len(s2) == 2
    assert {str(e.entry_id) for e in s2.iter_entries()} == {
        str(a.entry_id),
        str(b.entry_id),
    }
    assert s2.add(a) is False, "an acknowledged entry is still known after the restart"


def test_an_identical_repeat_is_harmless_and_a_different_one_is_a_conflict(
    tmp_path,
) -> None:
    s = FieldLogStore(tmp_path)
    a = stored()
    assert s.add(a) is True and s.add(a) is False
    changed = a.model_copy(update={"state": PassState.passable, "depth_band": None})
    with pytest.raises(Conflict):
        s.add(changed)
    assert len(s) == 1


def test_a_torn_last_line_is_skipped_and_counted_not_fatal(tmp_path) -> None:
    s = FieldLogStore(tmp_path)
    s.add(stored())
    path = next(tmp_path.glob("fieldlog-*.jsonl"))
    with path.open("a", encoding="utf-8") as f:
        f.write(
            '{"protocol": "field-log-v1", "entry_id": "half a lin'
        )  # crash mid-write
    s2 = FieldLogStore(tmp_path)
    assert len(s2) == 1 and s2.corrupt_lines == 1
    assert s2.add(stored()) is True, "and writing carries on"


def test_files_are_per_received_day_and_plain_json_lines(tmp_path) -> None:
    s = FieldLogStore(tmp_path)
    s.add(stored())
    files = list(tmp_path.glob("fieldlog-*.jsonl"))
    assert [f.name for f in files] == ["fieldlog-2026-10-05.jsonl"]
    line = json.loads(files[0].read_text(encoding="utf-8").splitlines()[0])
    assert (
        line["protocol"] == "field-log-v1"
        and line["volunteer"] == "alice"
        and line["lag_seconds"] == 120
    )


def test_concurrent_writers_lose_nothing(tmp_path) -> None:
    s = FieldLogStore(tmp_path)

    def work() -> None:
        for _ in range(25):
            s.add(stored())

    threads = [threading.Thread(target=work) for _ in range(8)]
    [t.start() for t in threads]
    [t.join() for t in threads]
    assert len(s) == 200
    assert len(FieldLogStore(tmp_path)) == 200
    assert sum(1 for _ in FieldLogStore(tmp_path).iter_entries()) == 200


def test_csv_cells_that_look_like_formulas_are_neutralised() -> None:
    e = stored(site_id="adhoc", depth_band=None, state="unknown", lat=13.0, lon=80.2)
    row = to_csv_row(e.model_copy(update={"client": "=1+1"}))
    assert row[CSV_HEADER.index("client")] == "'=1+1"
    assert len(row) == len(CSV_HEADER)


# ---------------------------------------------------------------------------------------------- tokens and windows


def test_token_book_refuses_weak_or_malformed_entries_and_identifies_the_rest() -> None:
    book = TokenBook(
        f"alice:{TOKEN_A}, bob:short, :nocode0123456789012, bad code:{TOKEN_B}, carol:{TOKEN_B}"
    )
    assert len(book) == 2 and book.refused == 3
    assert book.identify(TOKEN_A) == "alice"
    assert book.identify(TOKEN_B) == "carol"
    assert (
        book.identify("nope") is None
        and book.identify(None) is None
        and book.identify("") is None
    )


def test_window_counts_and_forgets() -> None:
    t = {"now": 0.0}
    w = Window(3, 10, clock=lambda: t["now"])
    assert [w.allow("k") for _ in range(4)] == [True, True, True, False]
    assert w.allow("other") is True
    t["now"] = 11.0
    assert w.allow("k") is True


def test_sites_file_ships_with_the_server(svc) -> None:
    assert len(svc.site_ids) == 402 and KNOWN_SITE in svc.site_ids
    assert svc.known_site("adhoc") and not svc.known_site("tw9-9999")


# ---------------------------------------------------------------------------------------------- the HTTP surface


def post(api, body, token=TOKEN_A, **headers):
    h = {"x-fieldlog-token": token, **headers} if token else dict(headers)
    return api.post(
        "/fieldlog/entries",
        content=body if isinstance(body, (str, bytes)) else json.dumps(body),
        headers=h,
    )


def test_a_volunteer_can_log_and_it_is_stored_with_their_code(api, svc) -> None:
    r = post(api, payload())
    assert r.status_code == 201 and r.json()["status"] == "stored"
    (e,) = list(svc.store.iter_entries())
    assert (
        e.volunteer,
        e.site_id,
        e.state.value,
        e.depth_band.value,
        e.lag_seconds,
    ) == ("alice", KNOWN_SITE, "not_passable", "knee", 120)


def test_sending_it_again_is_a_harmless_duplicate(api, svc) -> None:
    body = payload()
    assert post(api, body).status_code == 201
    again = post(api, body)
    assert again.status_code == 200 and again.json()["status"] == "duplicate"
    assert len(svc.store) == 1


def test_same_id_different_content_is_a_conflict(api) -> None:
    body = payload()
    post(api, body)
    r = post(api, {**body, "state": "passable", "depth_band": None})
    assert r.status_code == 409 and r.json()["status"] == "conflict"


def test_another_volunteer_cannot_overwrite_an_entry(api) -> None:
    body = payload()
    post(api, body)
    assert post(api, body, token=TOKEN_B).status_code == 409


def test_wrong_or_missing_token_is_401_and_stores_nothing(api, svc) -> None:
    assert post(api, payload(), token="wrong-token-0123456789").status_code == 401
    assert post(api, payload(), token=None).status_code == 401
    assert len(svc.store) == 0


def test_logging_is_off_until_tokens_are_configured(
    client, app_instance, tmp_path
) -> None:
    app_instance.state.fieldlog = make_service(tmp_path, tokens=None)
    r = client.post(
        "/fieldlog/entries",
        content=json.dumps(payload()),
        headers={"x-fieldlog-token": TOKEN_A},
    )
    assert r.status_code == 403
    assert client.get("/fieldlog/health").json()["enabled"] is False


def test_bad_input_gets_422_with_field_names_and_never_echoes_values(api, svc) -> None:
    r = post(api, payload(state="dry", site_id="Bad Id"))
    assert r.status_code == 422
    problems = r.json()["problems"]
    assert {p["field"] for p in problems} >= {"state", "site_id"}
    assert "Bad Id" not in r.text
    assert len(svc.store) == 0


def test_time_and_site_checks_are_422(api) -> None:
    far = post(api, payload(observed_at=(NOW + timedelta(hours=2)).isoformat()))
    old = post(api, payload(observed_at=(NOW - timedelta(days=20)).isoformat()))
    unknown = post(api, payload(site_id="tw9-9999"))
    assert (far.status_code, old.status_code, unknown.status_code) == (422, 422, 422)
    assert unknown.json()["problems"][0]["field"] == "site_id"


def test_not_json_and_oversized_bodies_are_refused(api) -> None:
    assert post(api, "this is not json").status_code == 422
    assert post(api, "x" * 5000).status_code == 413


def test_adhoc_entry_is_stored_with_a_rounded_position(api, svc) -> None:
    r = post(
        api,
        payload(
            site_id="adhoc",
            state="unknown",
            depth_band=None,
            lat=13.0827399,
            lon=80.2707199,
        ),
    )
    assert r.status_code == 201
    (e,) = list(svc.store.iter_entries())
    assert (e.lat, e.lon) == (13.0827, 80.2707)


def test_a_volunteer_over_the_hourly_limit_gets_429_and_others_are_unaffected(
    api, svc
) -> None:
    svc.by_volunteer_hour = Window(3, 3600)
    codes = [post(api, payload()).status_code for _ in range(4)]
    assert codes == [201, 201, 201, 429]
    assert post(api, payload(), token=TOKEN_B).status_code == 201


def test_repeated_wrong_tokens_are_slowed_but_a_valid_token_is_never_locked_out(
    api, svc
) -> None:
    # Behind a host's proxy many people share one address; a lockout must not let anyone lock every volunteer out.
    svc.bad_auth = Window(3, 600)
    assert [
        post(api, payload(), token="wrong-token-0123456789").status_code
        for _ in range(4)
    ] == [401, 401, 401, 429]
    assert (
        post(api, payload()).status_code == 201
    ), "the right token still works while wrong guesses are being slowed"
    assert (
        api.get("/fieldlog/whoami", headers={"x-fieldlog-token": TOKEN_A}).status_code
        == 200
    )


def test_reading_the_log_needs_the_admin_token(api, svc) -> None:
    post(api, payload())
    for path in ("/fieldlog/entries", "/fieldlog/export.csv", "/fieldlog/summary"):
        assert api.get(path).status_code == 401
        assert (
            api.get(path, headers={"x-admin-token": TOKEN_A}).status_code == 401
        ), "a volunteer token is not an admin token"
    ok = api.get("/fieldlog/entries", headers={"x-admin-token": ADMIN})
    assert (
        ok.status_code == 200
        and ok.json()["count"] == 1
        and ok.json()["entries"][0]["volunteer"] == "alice"
    )


def test_reading_is_off_without_an_admin_token(client, app_instance, tmp_path) -> None:
    app_instance.state.fieldlog = make_service(tmp_path, admin_token=None)
    assert (
        client.get("/fieldlog/entries", headers={"x-admin-token": ADMIN}).status_code
        == 403
    )
    assert make_service(tmp_path, admin_token="short").admin_token_refused is True


def test_export_is_a_csv_with_a_header_and_one_row_per_entry(api) -> None:
    post(api, payload())
    post(api, payload(state="passable", depth_band=None))
    r = api.get("/fieldlog/export.csv", headers={"x-admin-token": ADMIN})
    assert r.status_code == 200 and r.headers["content-type"].startswith("text/csv")
    assert (
        "attachment" in r.headers["content-disposition"]
        and r.headers["cache-control"] == "no-store"
    )
    rows = list(csv.reader(io.StringIO(r.text)))
    assert rows[0] == CSV_HEADER and len(rows) == 3
    assert {row[CSV_HEADER.index("state")] for row in rows[1:]} == {
        "not_passable",
        "passable",
    }


def test_summary_counts(api) -> None:
    post(api, payload())
    post(api, payload(state="unknown", depth_band=None), token=TOKEN_B)
    s = api.get("/fieldlog/summary", headers={"x-admin-token": ADMIN}).json()
    assert (
        s["entries"] == 2
        and s["by_state"] == {"not_passable": 1, "unknown": 1}
        and s["by_volunteer"] == {"alice": 1, "bob": 1}
    )


def test_public_sites_and_health(api) -> None:
    sites = api.get("/fieldlog/sites")
    assert (
        sites.status_code == 200
        and len(sites.json()["sites"]) == 402
        and sites.json()["kind"] == "candidate"
    )
    assert all(s["verified_on_ground"] is False for s in sites.json()["sites"])
    h = api.get("/fieldlog/health").json()
    assert (
        h["enabled"] is True
        and h["volunteers_configured"] == 2
        and h["durable"] is False
        and "NOT known to be persistent" in h["durability_note"]
    )
    assert TOKEN_A not in json.dumps(h) and ADMIN not in json.dumps(h)


def test_the_page_has_a_strict_content_security_policy_and_the_redirect_is_relative(
    api,
) -> None:
    page = api.get("/fieldlog/")
    assert page.status_code == 200 and "text/html" in page.headers["content-type"]
    csp = page.headers["content-security-policy"]
    assert (
        "script-src 'self'" in csp
        and "unsafe-inline" not in csp
        and "frame-ancestors 'none'" in csp
    )
    redirect = api.get("/fieldlog", follow_redirects=False)
    assert (
        redirect.status_code == 308 and redirect.headers["location"] == "fieldlog/"
    ), "relative, so a path prefix is kept"


def test_only_listed_assets_are_served(api) -> None:
    assert api.get("/fieldlog/assets/../../main.py").status_code in (404, 307, 400)
    assert api.get("/fieldlog/assets/secrets.txt").status_code == 404


def test_field_log_is_kept_apart_from_the_observation_store(api) -> None:
    post(api, payload())
    assert (
        api.get("/observations").json() == []
    ), "nothing logged here reaches the router's belief (ADR-028)"


def test_whoami_tells_a_volunteer_their_token_works_and_wrong_ones_count_toward_the_lockout(
    api, svc
) -> None:
    assert api.get(
        "/fieldlog/whoami", headers={"x-fieldlog-token": TOKEN_A}
    ).json() == {"volunteer": "alice"}
    svc.bad_auth = Window(2, 600)
    codes = [
        api.get(
            "/fieldlog/whoami", headers={"x-fieldlog-token": "wrong-token-0123456789"}
        ).status_code
        for _ in range(3)
    ]
    assert codes == [401, 401, 429]
    assert (
        api.get("/fieldlog/whoami", headers={"x-fieldlog-token": TOKEN_A}).status_code
        == 200
    )


def test_whoami_is_403_when_logging_is_off(client, app_instance, tmp_path) -> None:
    app_instance.state.fieldlog = make_service(tmp_path, tokens=None)
    assert (
        client.get(
            "/fieldlog/whoami", headers={"x-fieldlog-token": TOKEN_A}
        ).status_code
        == 403
    )


def test_every_listed_asset_and_the_service_worker_are_served_with_the_right_type(
    api,
) -> None:
    expected = {
        "app.js": "javascript",
        "core.js": "javascript",
        "i18n.js": "javascript",
        "style.css": "css",
    }
    for name, kind in expected.items():
        r = api.get(f"/fieldlog/assets/{name}")
        assert r.status_code == 200 and kind in r.headers["content-type"], name
        assert (
            r.headers["x-content-type-options"] == "nosniff"
            and "content-security-policy" in r.headers
        )
    sw = api.get("/fieldlog/sw.js")
    assert (
        sw.status_code == 200
        and "javascript" in sw.headers["content-type"]
        and sw.headers["cache-control"] == "no-cache"
    )
    # tests and anything not listed stay private
    assert api.get("/fieldlog/assets/core.test.mjs").status_code == 404
    assert api.get("/fieldlog/assets/index.html").status_code == 404


def test_the_page_works_under_the_strict_policy_no_inline_script_style_or_handlers() -> (
    None
):
    import re
    from pathlib import Path

    html = (
        Path(__file__).resolve().parents[1]
        / "app"
        / "static"
        / "fieldlog"
        / "index.html"
    ).read_text(encoding="utf-8")
    assert not re.search(
        r"<script(?![^>]*\bsrc=)", html
    ), "an inline script would be blocked by the policy"
    assert (
        " style=" not in html and "<style" not in html
    ), "inline styles would be blocked"
    assert not re.search(r"\son[a-z]+=", html), "inline event handlers would be blocked"
    assert (
        "http://" not in html and "https://" not in html
    ), "the page must not load anything from another origin"
    refs = re.findall(r'(?:src|href)="(assets/[^"]+)"', html)
    assert refs and all(
        r.removeprefix("assets/") in {"app.js", "style.css"} for r in refs
    )


def test_the_admin_endpoints_slow_wrong_guesses_but_never_refuse_the_right_token(
    api, svc
) -> None:
    svc.bad_auth = Window(2, 600)
    wrong = [
        api.get(
            "/fieldlog/summary", headers={"x-admin-token": "wrong-admin-0123456789"}
        ).status_code
        for _ in range(3)
    ]
    assert wrong == [401, 401, 429]
    assert (
        api.get("/fieldlog/summary", headers={"x-admin-token": ADMIN}).status_code
        == 200
    )
