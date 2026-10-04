"""Tests for scripts/study_common.py (T3.3/T3.4).

Two things this suite must prove, per the task card:
  1. `fuse_py`/`pessimistic_py` (the Python replica of `pulse_belief`'s pure arithmetic) match
     the Dart package's own behaviour -- translated directly from
     `packages/pulse_belief/test/fusion_test.dart` and `pessimistic_test.dart`, not merely
     asserted to match in prose.
  2. The Beta-reputation-with-forgetting baseline and the Study 1/2 metric functions
     (Brier/Murphy decomposition, adaptive ECE, log loss, AUROC) are correct against
     hand-computable toy cases with known answers.

Run with: .venv/Scripts/python.exe -m pytest scripts/tests/test_study_common.py -v
"""

from __future__ import annotations

import math

import pytest
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

SCRIPTS_DIR = Path(__file__).resolve().parent.parent
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import study_common as sc
import t3_2_replay_engine as t32


def _obs(id_, polarity, distance_m, age, reliability=0.9, t0=None):
    t0 = t0 or datetime(2026, 9, 13, 12, tzinfo=timezone.utc)
    base = t32.ObsRecord(
        id=id_,
        hazard_class="flood",
        polarity=polarity,
        observed_at=t0 - age,
        source_class="_direct",
        distance_m=distance_m,
    )
    return sc._ObsWithReliability(base, {"_direct": reliability})


T0 = datetime(2026, 9, 13, 12, tzinfo=timezone.utc)


class TestFusePyParity:
    """Translated 1:1 from packages/pulse_belief/test/fusion_test.dart."""

    def test_no_observations_posterior_equals_prior(self):
        belief = sc.fuse_py([], prior_logodds=-1.5, at=T0, decay_tau_seconds=3600)
        assert belief["posterior_logodds"] == -1.5
        assert belief["n_eff"] == 0.0
        assert belief["newest_observation_at"] is None
        assert belief["contributing_ids"] == []

    def test_observation_beyond_kernel_cutoff_contributes_nothing(self):
        far = _obs("far", 1, 10000, timedelta(0))
        belief = sc.fuse_py([far], prior_logodds=0, at=T0, decay_tau_seconds=3600)
        assert belief["posterior_logodds"] == 0.0
        assert belief["n_eff"] == 0.0

    def test_decay_monotonicity(self):
        ages = [
            timedelta(0),
            timedelta(minutes=30),
            timedelta(hours=1),
            timedelta(hours=2),
        ]
        n_effs, shifts = [], []
        for age in ages:
            obs = _obs("o", 1, 0, age)
            belief = sc.fuse_py([obs], prior_logodds=0, at=T0, decay_tau_seconds=3600.0)
            n_effs.append(belief["n_eff"])
            shifts.append(belief["posterior_logodds"] - belief["prior_logodds"])
        for i in range(1, len(ages)):
            assert n_effs[i] < n_effs[i - 1]
            assert shifts[i] < shifts[i - 1]

    def test_opposing_observations_cancel_but_both_count_neff(self):
        present = _obs("present", 1, 0, timedelta(minutes=5))
        absent = _obs("absent", -1, 0, timedelta(minutes=5))
        belief = sc.fuse_py(
            [present, absent], prior_logodds=-0.8, at=T0, decay_tau_seconds=3600
        )
        assert math.isclose(belief["posterior_logodds"], -0.8, abs_tol=1e-9)
        solo = sc.fuse_py([present], prior_logodds=-0.8, at=T0, decay_tau_seconds=3600)
        assert math.isclose(belief["n_eff"], 2 * solo["n_eff"], abs_tol=1e-9)

    def test_newest_observation_tracks_max_not_input_order(self):
        older = _obs("older", 1, 0, timedelta(hours=2))
        newer = _obs("newer", 1, 0, timedelta(minutes=1))
        belief = sc.fuse_py(
            [older, newer], prior_logodds=0, at=T0, decay_tau_seconds=3600
        )
        assert belief["newest_observation_at"] == newer.observed_at

    def test_future_dated_observation_raises(self):
        future = _obs("future", 1, 0, timedelta(minutes=-1))
        import pytest

        with pytest.raises(ValueError):
            sc.fuse_py([future], prior_logodds=0, at=T0, decay_tau_seconds=3600)


class TestPessimisticPyParity:
    """Translated 1:1 from packages/pulse_belief/test/pessimistic_test.dart."""

    def test_z_zero_reduces_to_p_mean_exactly(self):
        assert sc.pessimistic_py(p_mean=0.37, n_eff=5, z=0) == 0.37
        assert sc.pessimistic_py(p_mean=0.37, n_eff=0, z=0) == 0.37
        assert sc.pessimistic_py(p_mean=0.37, n_eff=1_000_000, z=0) == 0.37

    def test_lower_n_eff_widens_band(self):
        wide = sc.pessimistic_py(p_mean=0.6, n_eff=0.001, z=1.0)
        narrow = sc.pessimistic_py(p_mean=0.6, n_eff=50, z=1.0)
        assert wide > narrow
        assert wide > 0.6

    def test_clamp_engages_for_emergency_class(self):
        p_mean, n_eff, z = 0.5, 1.0, 2.0
        raw_unclamped = p_mean + z * math.sqrt(p_mean * (1 - p_mean) / (n_eff + 1))
        assert raw_unclamped > 1.0
        assert sc.pessimistic_py(p_mean=p_mean, n_eff=n_eff, z=z) == 1.0

    def test_never_exceeds_one_across_sweep(self):
        for p_mean in [0.1, 0.3, 0.5, 0.7, 0.9]:
            for n_eff in [0.0, 0.1, 0.5, 1.0, 2.0]:
                assert sc.pessimistic_py(p_mean=p_mean, n_eff=n_eff, z=2) <= 1.0


class TestBetaReputationWithForgetting:
    def test_single_fresh_positive_observation_no_decay(self):
        """Hand-computable: kappa(0)=1, reliability=0.9, forgetting^0=1 -> r=0.9, s=0,
        p = (0.9+1)/(0.9+2) = 1.9/2.9.
        """
        obs = [_obs("a", 1, 0, timedelta(0), reliability=0.9)]
        result = sc.beta_reputation_p(obs, at=T0, forgetting_lambda_per_hour=1.0)
        assert math.isclose(result["r"], 0.9, abs_tol=1e-9)
        assert result["s"] == 0.0
        assert math.isclose(result["p_mean"], 1.9 / 2.9, abs_tol=1e-9)

    def test_no_observations_gives_uninformative_half(self):
        result = sc.beta_reputation_p([], at=T0)
        assert result["p_mean"] == 0.5

    def test_forgetting_shrinks_old_evidence_toward_half(self):
        fresh = [_obs("fresh", 1, 0, timedelta(0), reliability=0.9)]
        old = [_obs("old", 1, 0, timedelta(hours=10), reliability=0.9)]
        p_fresh = sc.beta_reputation_p(fresh, at=T0, forgetting_lambda_per_hour=0.9)[
            "p_mean"
        ]
        p_old = sc.beta_reputation_p(old, at=T0, forgetting_lambda_per_hour=0.9)[
            "p_mean"
        ]
        assert p_fresh > p_old > 0.5

    def test_negative_polarity_pulls_reputation_below_half(self):
        obs = [_obs("neg", -1, 0, timedelta(0), reliability=0.9)]
        result = sc.beta_reputation_p(obs, at=T0, forgetting_lambda_per_hour=1.0)
        assert result["p_mean"] < 0.5


class TestBrierMurphyDecomposition:
    def test_perfect_predictions_zero_brier_full_resolution(self):
        probs = [1.0, 1.0, 0.0, 0.0]
        outcomes = [1, 1, 0, 0]
        d = sc.brier_murphy_decomposition(probs, outcomes, n_bins=2)
        assert math.isclose(d["brier"], 0.0, abs_tol=1e-9)
        assert math.isclose(d["reliability"], 0.0, abs_tol=1e-9)
        assert math.isclose(d["decomposition_check"], d["brier"], abs_tol=1e-9)

    def test_climatology_forecast_zero_resolution(self):
        """Predicting the base rate for everyone: resolution collapses to 0 (no
        discrimination), reliability is exactly 0 (predicted always equals bin mean outcome),
        so Brier == uncertainty.
        """
        outcomes = [1, 0, 0, 0]
        ybar = sum(outcomes) / len(outcomes)
        probs = [ybar] * len(outcomes)
        d = sc.brier_murphy_decomposition(probs, outcomes, n_bins=1)
        assert math.isclose(d["reliability"], 0.0, abs_tol=1e-9)
        assert math.isclose(d["resolution"], 0.0, abs_tol=1e-9)
        assert math.isclose(d["brier"], d["uncertainty"], abs_tol=1e-9)

    def test_hand_computed_brier_score(self):
        probs = [0.8, 0.2]
        outcomes = [1, 0]
        d = sc.brier_murphy_decomposition(probs, outcomes, n_bins=5)
        expected = ((0.8 - 1) ** 2 + (0.2 - 0) ** 2) / 2
        assert math.isclose(d["brier"], expected, abs_tol=1e-9)


class TestAdaptiveECE:
    def test_perfect_calibration_zero_ece(self):
        # bin means must equal outcome means exactly for zero ECE: p=0 paired with o=0,
        # p=1 paired with o=1 (a p=0.1 bin whose outcomes are all 0 is *not* perfectly
        # calibrated -- 0.1 != 0 -- so this uses 0.0/1.0 predictions, not merely low/high ones).
        probs = [0.0, 0.0, 1.0, 1.0]
        outcomes = [0, 0, 1, 1]
        assert math.isclose(
            sc.adaptive_ece(probs, outcomes, n_bins=2), 0.0, abs_tol=1e-9
        )

    def test_hand_computed_single_bin(self):
        probs = [0.2, 0.8]
        outcomes = [1, 1]
        # one bin containing both: p_bar=0.5, o_bar=1.0 -> ece = 1*|0.5-1.0| = 0.5
        assert math.isclose(
            sc.adaptive_ece(probs, outcomes, n_bins=1), 0.5, abs_tol=1e-9
        )


class TestLogLoss:
    def test_hand_computed(self):
        probs = [0.9, 0.1]
        outcomes = [1, 0]
        expected = -(math.log(0.9) + math.log(0.9)) / 2
        assert math.isclose(sc.log_loss(probs, outcomes), expected, abs_tol=1e-9)


class TestAUROC:
    def test_perfect_separation_is_one(self):
        probs = [0.9, 0.8, 0.2, 0.1]
        outcomes = [1, 1, 0, 0]
        assert sc.auroc(probs, outcomes) == 1.0

    def test_perfect_anti_separation_is_zero(self):
        probs = [0.1, 0.2, 0.8, 0.9]
        outcomes = [1, 1, 0, 0]
        assert sc.auroc(probs, outcomes) == 0.0

    def test_random_ties_is_half(self):
        probs = [0.5, 0.5, 0.5, 0.5]
        outcomes = [1, 0, 1, 0]
        assert math.isclose(sc.auroc(probs, outcomes), 0.5, abs_tol=1e-9)

    def test_single_class_is_nan(self):
        assert math.isnan(sc.auroc([0.1, 0.9], [1, 1]))


class TestC0HazardBlind:
    def test_empty_hazards_document(self):
        assert sc.make_c0_hazards_json() == {"hazards": []}


class TestC2SharedDecay:
    def test_all_classes_get_shared_tc(self):
        hazard_classes = t32.load_hazard_classes()
        c2 = sc.make_c2_hazard_classes(hazard_classes)
        for cls in c2["classes"].values():
            assert cls["T_c_seconds"] == sc.C2_SHARED_TC_SECONDS
        # severity/h_max/epsilon untouched
        assert (
            c2["classes"]["flood"]["severity"]
            == hazard_classes["classes"]["flood"]["severity"]
        )


class TestC4FixedTTL:
    def test_drops_observations_older_than_ttl(self):
        recent = t32.ObsRecord(
            id="recent",
            hazard_class="flood",
            polarity=1,
            observed_at=T0 - timedelta(hours=1),
            source_class="crowd",
            distance_m=0,
        )
        stale = t32.ObsRecord(
            id="stale",
            hazard_class="flood",
            polarity=1,
            observed_at=T0 - timedelta(hours=100),
            source_class="crowd",
            distance_m=0,
        )
        cfg = t32.EdgeHazardConfigBuild(
            edge_id=1,
            hazard_class="flood",
            prior_logodds=-1.0,
            decay_tau_seconds=7200.0,
            severity=1.0,
            h_max_mm=300.0,
            epsilon=0.1,
            observations=[recent, stale],
        )
        configs = {1: cfg}
        windowed = {1: [recent, stale]}
        ttl_configs, ttl_windowed, stats = sc.apply_fixed_ttl(
            configs, windowed, at=T0, ttl_seconds=6 * 3600.0
        )
        assert [o.id for o in ttl_windowed[1]] == ["recent"]
        assert ttl_configs[1].decay_tau_seconds == sc.C4_NO_DECAY_TAU_SECONDS
        assert stats["observations_dropped"] == 1
        assert stats["observations_kept"] == 1


class TestFuseBetaParity:
    """The Python Beta replica must agree with the Dart implementation (ADR-015). The vectors were
    produced by the Dart code (packages/pulse_belief/tool/golden_vectors.dart), not by this file."""

    @staticmethod
    def _cases():
        import json

        path = Path(__file__).parent / "fixtures" / "beta_golden.json"
        return json.loads(path.read_text(encoding="utf-8"))

    def test_matches_dart_on_all_golden_cases(self):
        doc = self._cases()
        at = datetime(2015, 12, 2, 12, tzinfo=timezone.utc)
        assert doc["params"] == {
            "prior_strength": sc.BETA_PRIOR_STRENGTH,
            "evidence_scale": sc.BETA_EVIDENCE_SCALE,
            "reference_reliability": sc.BETA_REFERENCE_RELIABILITY,
        }
        for i, case in enumerate(doc["cases"]):
            obs = []
            for j, r in enumerate(case["reports"]):
                base = t32.ObsRecord(
                    id=f"o{j}",
                    hazard_class="flood",
                    polarity=r["polarity"],
                    observed_at=at - timedelta(seconds=r["age_s"]),
                    source_class="crowd",
                    distance_m=r["distance_m"],
                )
                wrapper = sc._ObsWithReliability(base, {"crowd": r["alpha"]})
                obs.append(wrapper)
            p0 = case["p0"]
            belief = sc.fuse_beta_py(obs, math.log(p0 / (1 - p0)), at, case["tau_s"])
            tag = f"case {i}"
            assert belief["alpha"] == pytest.approx(case["alpha"], rel=1e-9, abs=1e-12), tag
            assert belief["beta"] == pytest.approx(case["beta"], rel=1e-9, abs=1e-12), tag
            assert belief["p_mean"] == pytest.approx(case["p_mean"], rel=1e-9, abs=1e-12), tag
            assert belief["n_eff"] == pytest.approx(case["n_eff"], rel=1e-9, abs=1e-12), tag
            for z, expected in case["p_tilde"].items():
                got = sc.pessimistic_beta_py(belief, float(z))
                # Dart's normal CDF is the A&S 7.1.26 approximation (error < 1.5e-7).
                assert got == pytest.approx(expected, abs=2e-6), f"{tag} z={z}"

    def test_the_f01_dip_is_gone(self):
        at = datetime(2015, 12, 2, tzinfo=timezone.utc)
        series = []
        for k in range(4):
            obs = [
                sc._ObsWithReliability(
                    t32.ObsRecord(f"c{i}", "flood", 1, at, "crowd", 0.0), {"crowd": 0.6}
                )
                for i in range(k)
            ]
            b = sc.fuse_beta_py(obs, math.log(0.05 / 0.95), at, 7200.0)
            series.append(sc.pessimistic_beta_py(b, 1.28))
        assert series == sorted(series) and len(set(series)) == 4, series
