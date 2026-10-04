"""The committed Chennai places file (scripts/build_places.py) is well formed and carries what people search for."""

import hashlib
import json
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
DIR = ROOT / "data" / "places" / "chennai-2026-10-04"


def _places():
    return json.loads((DIR / "places.json").read_text(encoding="utf-8"))["places"]


def test_file_matches_its_manifest():
    manifest = json.loads((DIR / "manifest.json").read_text(encoding="utf-8"))
    info = manifest["places_json"]
    data = (DIR / "places.json").read_bytes()
    assert hashlib.sha256(data).hexdigest() == info["sha256"]
    assert len(_places()) == info["count"]
    assert manifest["licence"].startswith("OpenStreetMap")


def test_cities_yaml_points_at_it_and_every_row_is_inside_the_box():
    cities = yaml.safe_load((ROOT / "config" / "cities.yaml").read_text(encoding="utf-8"))["cities"]["chennai"]
    assert (ROOT / cities["places"]) == DIR / "places.json"
    b = cities["bbox"]
    for name, lat, lon, kind, *_ in _places():
        assert b["min_lat"] <= lat <= b["max_lat"] and b["min_lon"] <= lon <= b["max_lon"], name
        assert kind in ("city", "town", "suburb", "neighbourhood", "quarter", "village"), (name, kind)


def test_alias_and_extra_place_are_present_and_not_duplicated():
    places = _places()
    by_name = {}
    for row in places:
        by_name.setdefault(row[0], []).append(row)
    t_nagar = by_name["Thiyagaraya Nagar"]
    assert len(t_nagar) == 1 and "T. Nagar" in t_nagar[0][4:]
    assert len(by_name["Velachery"]) == 1, "the extra Velachery point must not duplicate an OSM place"
    manifest = json.loads((DIR / "manifest.json").read_text(encoding="utf-8"))
    assert [e["name"] for e in manifest["extras_applied"]] == ["Velachery"]
    assert "railway=station" in manifest["extras_applied"][0]["source"]


def test_common_neighbourhoods_are_searchable():
    names = {row[0] for row in _places()}
    for n in ("Adyar", "Anna Nagar", "Guindy", "Mylapore", "Tambaram", "Pallikaranai", "Perungudi", "Velachery"):
        assert n in names, n
