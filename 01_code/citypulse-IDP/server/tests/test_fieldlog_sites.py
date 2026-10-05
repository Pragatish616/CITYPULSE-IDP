"""The shipped site list is exactly what scripts/build_fieldlog_sites.py makes from the committed watchlist and places files."""

import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SITES = ROOT / "server" / "app" / "fieldlog" / "sites.json"


def load_builder():
    spec = importlib.util.spec_from_file_location(
        "build_fieldlog_sites", ROOT / "scripts" / "build_fieldlog_sites.py"
    )
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def test_sites_json_is_in_step_with_its_generator() -> None:
    assert json.loads(SITES.read_text(encoding="utf-8")) == json.loads(
        json.dumps(load_builder().build(), ensure_ascii=False)
    ), "run: python scripts/build_fieldlog_sites.py"


def test_every_site_is_a_labelled_unverified_candidate_with_a_unique_id() -> None:
    doc = json.loads(SITES.read_text(encoding="utf-8"))
    sites = doc["sites"]
    assert doc["kind"] == "candidate" and len(sites) == 402
    assert len({s["id"] for s in sites}) == len(sites)
    for s in sites:
        assert s["id"] in s["label"] and "candidate" in s["label"]
        assert s["verified_on_ground"] is False and s["basin_hint_verified"] is False
        assert 12.0 <= s["lat"] <= 14.0 and 79.0 <= s["lon"] <= 81.0
        assert s["near"] is None or (
            s["near_m"] is not None and 0 <= s["near_m"] <= 2000
        )


def test_most_sites_have_a_neighbourhood_a_volunteer_can_search_by() -> None:
    sites = json.loads(SITES.read_text(encoding="utf-8"))["sites"]
    assert sum(1 for s in sites if s["near"]) >= 395
