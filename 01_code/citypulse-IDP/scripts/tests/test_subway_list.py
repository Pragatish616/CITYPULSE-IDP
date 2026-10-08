"""The subway watchlist (M3.1, ADR-031): GCC's table copied exactly, positions only where OpenStreetMap has them and labelled by how
sure the match is, nothing claimed as verified. Committed outputs must equal what the builder produces. No network."""

import importlib.util
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))


def load(name: str):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / f"{name}.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


builder = load("build_subway_list")
extract = load("extract_osm_subways")
SOURCE = json.loads(builder.SOURCE.read_text(encoding="utf-8"))
LIST = json.loads(builder.OUT_LIST.read_text(encoding="utf-8"))
SITES = json.loads(builder.OUT_SITES.read_text(encoding="utf-8"))
QUALITIES = {"osm_named", "osm_road_tunnel", "osm_hint", "none"}


def test_committed_outputs_are_what_the_builder_makes() -> None:
    listing, sites = builder.build()
    sites["source"]["sha256"] = SITES["source"]["sha256"]
    assert json.loads(json.dumps(listing, ensure_ascii=False)) == LIST, "run: python scripts/build_subway_list.py"
    assert json.loads(json.dumps(sites, ensure_ascii=False)) == SITES, "run: python scripts/build_subway_list.py"
    assert SITES["source"]["sha256"] == builder.sha256(builder.OUT_LIST)


def test_gcc_table_has_sixteen_road_rail_and_five_pedestrian_rows_copied_exactly() -> None:
    assert [r["gcc_no"] for r in SOURCE["road_rail_subways"]] == list(range(1, 17))
    assert [r["gcc_no"] for r in SOURCE["pedestrian_subways"]] == list(range(1, 6))
    by_id = {e["id"]: e for e in LIST["entries"]}
    for r in SOURCE["road_rail_subways"]:
        e = by_id[f"sub-gcc-rr-{r['gcc_no']:02d}"]
        assert (e["zone_ward"], e["gcc_location"], e["list"]) == (r["zone_ward"], r["location"], "gcc_road_rail")
    for r in SOURCE["pedestrian_subways"]:
        e = by_id[f"sub-gcc-ped-{r['gcc_no']:02d}"]
        assert (e["zone_ward"], e["gcc_location"], e["list"]) == (r["zone_ward"], r["location"], "gcc_pedestrian")
    assert SOURCE["sources"]["gcc_bridges"]["url"] == "https://chennaicorporation.gov.in/gcc/department/bridges/"


def test_every_entry_is_unverified_and_has_a_unique_valid_id() -> None:
    ids = [e["id"] for e in LIST["entries"]]
    assert len(ids) == len(set(ids)) == LIST["entries_total"] == 31
    for e in LIST["entries"]:
        assert re.fullmatch(r"[a-z0-9][a-z0-9_-]{1,31}", e["id"]), e["id"]
        assert e["verified_on_ground"] is False
    assert LIST["counts"] == {"gcc_road_rail": 16, "gcc_pedestrian": 5, "news_only": 3, "osm_only": 7}


def test_a_position_exists_exactly_when_osm_supplied_one_and_is_inside_chennai() -> None:
    for e in LIST["entries"]:
        q = e["position"]["quality"]
        assert q in QUALITIES
        assert (e["lat"] is None) == (e["lon"] is None) == (q == "none"), e["id"]
        assert bool(e["position"]["osm_features"]) == (q != "none"), e["id"]
        if e["lat"] is not None:
            assert 12.75 <= e["lat"] <= 13.25 and 79.95 <= e["lon"] <= 80.35, e["id"]
            assert e["position"]["span_m"] <= builder.MAX_SPAN_M
        else:
            assert e["area_hint"] is None or "not the subway's position" in e["area_hint"]["note"]


def test_uncertain_matches_say_so_and_are_not_called_named() -> None:
    by_id = {e["id"]: e for e in LIST["entries"]}
    perambur = by_id["sub-gcc-rr-07"]["position"]
    assert perambur["quality"] == "osm_hint" and "pedestrian tunnel" in perambur["note"] and "hint, not the subway itself" in perambur["note"]
    assert by_id["sub-gcc-rr-01"]["position"]["quality"] == "osm_named"
    assert "highway=construction" in by_id["sub-gcc-rr-01"]["position"]["note"]
    assert by_id["sub-gcc-ped-01"]["position"]["quality"] == "osm_hint"
    for key in ("sub-gcc-rr-03", "sub-gcc-rr-06", "sub-gcc-rr-08", "sub-gcc-ped-02", "sub-gcc-ped-03", "sub-gcc-ped-04", "sub-gcc-ped-05"):
        assert by_id[key]["position"]["quality"] == "none" and by_id[key]["lat"] is None, key


def test_the_list_never_claims_equality_with_the_news_count_of_22() -> None:
    assert "22 subways" in LIST["note"] and "no claim to equal them" in LIST["note"]
    assert "NOTHING is verified on the ground" in LIST["note"]


def test_known_positions_are_where_chennai_geography_says() -> None:
    by_id = {e["id"]: e for e in LIST["entries"]}
    # Hand-checked against well-known places: the RBI subway lies on Rajaji Salai by Parry's/High Court (about 13.085 N, 80.289 E);
    # Madley subway beside Mambalam station (about 13.035 N, 80.227 E).
    rbi, madley = by_id["sub-gcc-rr-04"], by_id["sub-gcc-rr-12"]
    assert abs(rbi["lat"] - 13.085) < 0.005 and abs(rbi["lon"] - 80.289) < 0.005
    assert abs(madley["lat"] - 13.035) < 0.005 and abs(madley["lon"] - 80.227) < 0.005
    assert rbi["name_ta"] and "சுரங்கப்பாதை" in rbi["name_ta"]


def test_field_log_sites_mirror_the_watchlist() -> None:
    assert SITES["count"] == len(SITES["sites"]) == len(LIST["entries"])
    by_id = {e["id"]: e for e in LIST["entries"]}
    for s in SITES["sites"]:
        e = by_id[s["id"]]
        assert (s["lat"], s["lon"], s["position_quality"]) == (e["lat"], e["lon"], e["position"]["quality"])
        assert s["verified_on_ground"] is False and s["site_kind"] == "subway"
        assert e["name"] in s["label"]


def test_the_osm_extractor_only_selects_subway_like_features() -> None:
    assert extract.says_subway({"name": "RBI Subway"})
    assert extract.says_subway({"name:ta": "நுங்கம்பாக்கம் சுரங்கப்பாதை"})
    assert extract.says_subway({"name": "Ambattur railway Underpass"})
    assert not extract.says_subway({"name": "Anna Salai", "highway": "primary"})
    assert extract.length_m([13.0, 13.001], [80.0, 80.0]) == 111.2


def test_the_osm_extract_is_recorded_with_its_licence_and_source() -> None:
    raw = json.loads(builder.OSM.read_text(encoding="utf-8"))
    assert raw["licence"] == "OpenStreetMap contributors, ODbL 1.0"
    assert raw["source"]["file"] == "southern-zone-260911.osm.pbf" and raw["count"] == len(raw["features"]) > 100
    assert LIST["sources"]["openstreetmap"]["sha256"] == builder.sha256(builder.OSM)


def test_the_check_sheet_is_generated_and_has_a_row_and_a_map_link_per_positioned_subway() -> None:
    sheet = builder.OUT_SHEET.read_text(encoding="utf-8")
    assert sheet == builder.build_checksheet(LIST)
    rows = [line for line in sheet.splitlines() if line.startswith("| | sub-")]
    assert len(rows) == 31
    assert sheet.count("[open map](https://www.openstreetmap.org/?mlat=") == sum(1 for e in LIST["entries"] if e["lat"] is not None)
    assert "None is verified on the ground" in sheet and "more than 100 m" in sheet
