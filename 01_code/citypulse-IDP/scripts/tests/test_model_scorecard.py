"""The flood-model scorecard (ADR-033): the rule is applied as written, every number comes from a result file, and the stress run's own checks hold."""

import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
import model_scorecard as msc

RES = ROOT / "data" / "results"
DIR = RES / "2026-10-11-model-scorecard"
STRESS = json.loads((DIR / "stress.json").read_text(encoding="utf-8"))
CARD = json.loads((DIR / "scorecard.json").read_text(encoding="utf-8"))


def test_skill_and_bands_follow_the_rule_fixed_in_advance() -> None:
    assert msc.skill(0.5, 0.0) == 0.5
    assert abs(msc.skill(0.311, 0.188) - 0.1515) < 1e-3
    assert msc.band(0.35, 0.1) == "useful"
    assert msc.band(0.15, 0.1) == "modest"
    assert msc.band(0.05, 0.01) == "marginal"
    assert msc.band(-0.01, -0.02).startswith("no evidence")
    assert msc.band(0.5, -0.001).startswith("no evidence"), "an interval that includes 0 beats a high point estimate"


def test_scorecard_is_what_the_script_makes_from_the_files(tmp_path, monkeypatch) -> None:
    shutil.copy(DIR / "stress.json", tmp_path / "stress.json")
    monkeypatch.setattr(msc, "OUT", tmp_path)
    msc.main()
    again = json.loads((tmp_path / "scorecard.json").read_text(encoding="utf-8"))
    assert again["rows"] == CARD["rows"]


def test_scorecard_numbers_equal_the_source_files() -> None:
    n = json.loads((RES / "2026-10-04-nationwide-flood-gating" / "result.json").read_text(encoding="utf-8"))
    t = json.loads((RES / "2026-10-04-susceptibility-national-all" / "result.json").read_text(encoding="utf-8"))["results"]["spatial_blocks"]
    rows = {(r["model"], r["task"][:30]): r for r in CARD["rows"]}
    first = CARD["rows"][0]
    assert first["model_value"] == n["test"]["model"]["ap"] and first["baseline_value"] == n["test"]["b1_month_rate"]["ap"]
    reg = next(r for r in CARD["rows"] if "(registered)" in r["task"])
    assert reg["model_value"] == t["m1_terrain"]["ap"] and reg["baseline_value"] == t["best_single_feature"]["ap"]
    assert len(rows) == len(CARD["rows"])


def test_the_stress_run_reproduced_the_registered_result_and_passed_its_negative_control() -> None:
    assert STRESS["t1_repro_2deg"]["reproduced_to_3_decimals"] is True
    assert STRESS["t3_negative_control"]["passes_0.45_to_0.55"] is True


def test_the_technique_choice_followed_the_rule_and_the_lock_set_was_used_once() -> None:
    dev = STRESS["t9_alternatives_dev"]
    best = max((k for k in dev if isinstance(dev[k], dict) and "ap" in dev[k]), key=lambda k: dev[k]["ap"])
    assert STRESS["t9_chosen_by_rule"]["highest_dev_ap"] == best
    lo = dev["best_vs_a_ap_diff_ci95"][0]
    kept = STRESS["t9_chosen_by_rule"]["kept_after_interval_rule"]
    assert kept == (best if lo > 0 else "a_hgb_m1")
    lock = STRESS["t9_lock_evaluation"]
    assert {k for k in lock if isinstance(lock[k], dict) and "ap" in lock[k] and "ci95" in lock[k]} == {"a_hgb_m1", "best_single_feature"} | ({kept} if kept != "a_hgb_m1" else set())


def test_larger_blocks_do_not_collapse_the_score() -> None:
    base = STRESS["t1_repro_2deg"]["model"]["ap"]
    for k in ("t2_blocks_5deg", "t2_blocks_10deg"):
        assert STRESS[k]["model"]["ap"] > 0.9 * base
        assert STRESS[k]["model_minus_base"]["ap"]["ci95"][0] > 0
