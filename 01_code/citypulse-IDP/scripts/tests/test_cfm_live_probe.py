"""The CFM-DSS probe makes at most two requests and reads timestamps without guessing. No network here."""

import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import cfm_live_probe as probe

NOW = datetime(2026, 10, 9, 12, 0, tzinfo=timezone.utc)
CAPS = """<wfs:WFS_Capabilities><wfs:FeatureTypeList>
<wfs:FeatureType><wfs:Name>ChennaiDSS:gis_crowdsourced</wfs:Name></wfs:FeatureType>
<wfs:FeatureType><wfs:Name>ChennaiDSS:gis_awlrrls_waterlevel_with_latest_datetime</wfs:Name></wfs:FeatureType>
<wfs:FeatureType><wfs:Name>ChennaiDSS:wards</wfs:Name></wfs:FeatureType>
</wfs:FeatureTypeList></wfs:WFS_Capabilities>"""


def test_layer_names_and_the_preferred_choice() -> None:
    names = probe.parse_layer_names(CAPS)
    assert names == [
        "ChennaiDSS:gis_crowdsourced",
        "ChennaiDSS:gis_awlrrls_waterlevel_with_latest_datetime",
        "ChennaiDSS:wards",
    ]
    assert probe.choose_layer(names) == "ChennaiDSS:gis_awlrrls_waterlevel_with_latest_datetime"
    assert probe.choose_layer(["ChennaiDSS:wards"]) is None


def test_urls_ask_for_five_features_of_one_layer_in_json() -> None:
    u = probe.feature_url("ChennaiDSS:x")
    assert "count=5" in u and "outputFormat=application%2Fjson" in u and "typeNames=ChennaiDSS%3Ax" in u
    assert "GetCapabilities" in probe.capabilities_url()


def test_timestamps_with_and_without_a_zone() -> None:
    assert probe.parse_time("2026-10-09T08:00:00Z") == datetime(2026, 10, 9, 8, 0, tzinfo=timezone.utc)
    ist = probe.parse_time("09-10-2026 13:30:00")  # no zone: taken as India time
    assert ist is not None and ist.astimezone(timezone.utc) == datetime(2026, 10, 9, 8, 0, tzinfo=timezone.utc)
    assert probe.parse_time("not a time") is None and probe.parse_time(None) is None


def test_summary_reports_keys_age_and_today_without_keeping_values_other_than_times() -> None:
    doc = {"features": [
        {"properties": {"station_name": "SECRET", "water_level_m": 1.2, "recorded_datetime": "2026-10-09T10:00:00Z"}},
        {"properties": {"station_name": "SECRET2", "water_level_m": 0.9, "recorded_datetime": "2026-10-08T01:00:00Z"}},
    ]}
    s = probe.summarise_features(doc, NOW)
    assert s["features_returned"] == 2 and s["time_like_keys"] == ["recorded_datetime"]
    assert s["newest_timestamp_utc"] == "2026-10-09T10:00:00Z" and s["age_of_newest_hours"] == 2.0
    assert s["newest_is_from_today_ist"] is True
    assert "SECRET" not in str(s)


def test_old_readings_are_not_from_today() -> None:
    doc = {"features": [{"properties": {"datetime": "2025-12-01T00:00:00Z"}}]}
    s = probe.summarise_features(doc, NOW)
    assert s["newest_is_from_today_ist"] is False and s["age_of_newest_hours"] > 7000


def test_no_timestamps_gives_none_not_a_guess() -> None:
    s = probe.summarise_features({"features": [{"properties": {"level": 3}}]}, NOW)
    assert s["newest_timestamp_utc"] is None and s["newest_is_from_today_ist"] is False


def test_the_probe_makes_at_most_two_requests(monkeypatch, tmp_path) -> None:
    calls = []

    def fake_fetch(url):
        calls.append(url)
        if "GetCapabilities" in url:
            return 200, CAPS.encode(), "text/xml"
        return 200, b'{"features": [{"properties": {"recorded_datetime": "2026-10-09T10:00:00Z"}}]}', "application/json"

    monkeypatch.setattr(probe, "fetch", fake_fetch)
    monkeypatch.setattr(probe, "ROOT", tmp_path)
    assert probe.main([]) == 0
    assert len(calls) == 2


def test_if_request_one_fails_no_other_path_is_tried(monkeypatch, tmp_path) -> None:
    calls = []

    def fake_fetch(url):
        calls.append(url)
        return 404, b"not found", "text/html"

    monkeypatch.setattr(probe, "fetch", fake_fetch)
    monkeypatch.setattr(probe, "ROOT", tmp_path)
    assert probe.main([]) == 0
    assert len(calls) == 1


def test_single_feature_mode_makes_exactly_one_request_newest_first(monkeypatch, tmp_path) -> None:
    calls = []

    def fake_fetch(url):
        calls.append(url)
        return 200, b'{"features": [{"properties": {"time_of_measurement": "2026-10-09T10:00:00Z"}}]}', "application/json"

    monkeypatch.setattr(probe, "fetch", fake_fetch)
    monkeypatch.setattr(probe, "ROOT", tmp_path)
    args = ["--base", "https://example.test/x/wfs", "--layer", "ChennaiDSS:awlr_transaction", "--sort", "time_of_measurement"]
    assert probe.main(args) == 0
    assert len(calls) == 1
    assert calls[0].startswith("https://example.test/x/wfs?") and "sortBy=time_of_measurement+D" in calls[0]


def test_base_and_layer_must_come_together() -> None:
    import pytest

    with pytest.raises(SystemExit):
        probe.main(["--base", "https://example.test/x"])
