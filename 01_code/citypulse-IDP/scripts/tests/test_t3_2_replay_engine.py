"""Tests for scripts/t3_2_replay_engine.py (T3.2).

Two things this suite must prove, per the task card:
  1. Query-time windowing (`filter_observations_by_clock`) actually excludes future-dated
     observations and includes past/equal ones -- pure-function unit tests, no subprocess.
  2. The full pipeline is deterministic -- `test_determinism_two_runs_byte_identical` actually
     runs the pipeline twice (real corpus, real graph, real CLI subprocess) and asserts
     byte-identical output, rather than asserting this in prose. This is the acceptance
     criterion named in docs/IMPLEMENTATION_PLAN.md T3.2.

Run with: .venv/Scripts/python.exe -m pytest scripts/tests/test_t3_2_replay_engine.py -v
"""

from __future__ import annotations

import sys
from pathlib import Path

SCRIPTS_DIR = Path(__file__).resolve().parent.parent
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import t3_2_replay_engine as t32


def _obs(id_, observed_at_iso, hazard_class="flood", polarity=1, source_class="crowd"):
    return t32.ObsRecord(
        id=id_,
        hazard_class=hazard_class,
        polarity=polarity,
        observed_at=t32.parse_iso8601(observed_at_iso),
        source_class=source_class,
        distance_m=5.0,
    )


def _cfg(edge_id, observations):
    return t32.EdgeHazardConfigBuild(
        edge_id=edge_id,
        hazard_class="flood",
        prior_logodds=-1.0,
        decay_tau_seconds=7200.0,
        severity=1.0,
        h_max_mm=300.0,
        epsilon=0.1,
        observations=observations,
    )


class TestFilterObservationsByClock:
    def test_excludes_future_dated_observation(self):
        past = _obs("a", "2015-12-01T00:00:00Z")
        future = _obs("b", "2015-12-03T00:00:00Z")
        configs = {1: _cfg(1, [past, future])}
        at = t32.parse_iso8601("2015-12-02T00:00:00Z")

        out = t32.filter_observations_by_clock(configs, at)

        ids = {r.id for r in out[1]}
        assert ids == {"a"}

    def test_includes_observation_exactly_at_clock(self):
        exact = _obs("a", "2015-12-02T00:00:00Z")
        configs = {1: _cfg(1, [exact])}
        at = t32.parse_iso8601("2015-12-02T00:00:00Z")

        out = t32.filter_observations_by_clock(configs, at)

        assert [r.id for r in out[1]] == ["a"]

    def test_earlier_clock_yields_fewer_observations_than_later_clock(self):
        """The actual replay property: winding the clock forward can only add evidence,
        never remove it -- this is what makes it a *replay* rather than a random subset.
        """
        obs = [
            _obs("a", "2015-12-01T00:00:00Z"),
            _obs("b", "2015-12-02T00:00:00Z"),
            _obs("c", "2015-12-03T00:00:00Z"),
        ]
        configs = {1: _cfg(1, obs)}

        early = t32.filter_observations_by_clock(
            configs, t32.parse_iso8601("2015-12-01T12:00:00Z")
        )
        late = t32.filter_observations_by_clock(
            configs, t32.parse_iso8601("2015-12-04T00:00:00Z")
        )

        assert len(early[1]) == 1
        assert len(late[1]) == 3
        assert {r.id for r in early[1]}.issubset({r.id for r in late[1]})

    def test_empty_observations_list_when_all_future(self):
        configs = {1: _cfg(1, [_obs("a", "2099-01-01T00:00:00Z")])}
        out = t32.filter_observations_by_clock(
            configs, t32.parse_iso8601("2015-12-02T00:00:00Z")
        )
        assert out[1] == []

    def test_edge_with_no_observations_at_all_still_present_as_empty_list(self):
        configs = {1: _cfg(1, [])}
        out = t32.filter_observations_by_clock(
            configs, t32.parse_iso8601("2015-12-02T00:00:00Z")
        )
        assert out[1] == []


class TestChooseDominantHazardClass:
    def test_single_class_is_trivially_dominant(self):
        obs = [_obs("a", "2015-12-02T00:00:00Z", hazard_class="waterlogging")]
        dominant, kept, dropped = t32.choose_dominant_hazard_class(
            obs, {"flood": 1.0, "waterlogging": 0.6}
        )
        assert dominant == "waterlogging"
        assert kept == obs
        assert dropped == []

    def test_majority_class_wins_and_minority_is_dropped_not_lost_silently(self):
        obs = [
            _obs("a", "2015-12-02T00:00:00Z", hazard_class="flood"),
            _obs("b", "2015-12-02T00:00:00Z", hazard_class="flood"),
            _obs("c", "2015-12-02T00:00:00Z", hazard_class="waterlogging"),
        ]
        dominant, kept, dropped = t32.choose_dominant_hazard_class(
            obs, {"flood": 1.0, "waterlogging": 0.6}
        )
        assert dominant == "flood"
        assert {r.id for r in kept} == {"a", "b"}
        assert {r.id for r in dropped} == {"c"}

    def test_tie_broken_by_higher_severity(self):
        obs = [
            _obs("a", "2015-12-02T00:00:00Z", hazard_class="flood"),
            _obs("b", "2015-12-02T00:00:00Z", hazard_class="waterlogging"),
        ]
        dominant, _kept, dropped = t32.choose_dominant_hazard_class(
            obs, {"flood": 1.0, "waterlogging": 0.6}
        )
        assert dominant == "flood"  # higher severity wins the 1-1 tie
        assert len(dropped) == 1


class TestBfsReachability:
    def test_simple_chain(self):
        adjacency = {0: [1], 1: [2], 2: []}
        assert t32.bfs_reachable(adjacency, 0) == {0, 1, 2}
        assert t32.bfs_reachable(adjacency, 2) == {2}

    def test_disconnected_node(self):
        adjacency = {0: [1], 1: [], 2: []}
        assert t32.bfs_reachable(adjacency, 2) == {2}


class TestSampleOdPairs:
    def test_deterministic_for_fixed_seed(self):
        adjacency = {i: [(i + 1) % 20] for i in range(20)}  # one big directed cycle
        pairs_a, _ = t32.sample_od_pairs(20, adjacency, seed=42, n=10)
        pairs_b, _ = t32.sample_od_pairs(20, adjacency, seed=42, n=10)
        assert pairs_a == pairs_b

    def test_different_seed_can_differ(self):
        adjacency = {i: [(i + 1) % 50] for i in range(50)}
        pairs_a, _ = t32.sample_od_pairs(50, adjacency, seed=1, n=10)
        pairs_b, _ = t32.sample_od_pairs(50, adjacency, seed=2, n=10)
        assert pairs_a != pairs_b

    def test_all_pairs_reachable(self):
        adjacency = {i: [(i + 1) % 30] for i in range(30)}
        pairs, _ = t32.sample_od_pairs(30, adjacency, seed=7, n=15)
        for source, target in pairs:
            assert target in t32.bfs_reachable(adjacency, source)

    def test_isolated_source_is_resampled_not_a_hard_failure(self):
        # node 5 has no outgoing edges at all; sampling must skip past it, not crash or stall.
        adjacency = {i: [(i + 1) % 10] for i in range(10) if i != 5}
        adjacency[5] = []
        pairs, _stats = t32.sample_od_pairs(10, adjacency, seed=99, n=8)
        assert len(pairs) == 8
        for source, target in pairs:
            assert source != 5


class TestDeterminismEndToEnd:
    def test_determinism_two_runs_byte_identical(self, tmp_path):
        """The T3.2 acceptance criterion, verbatim: 'two runs with the same seed produce
        identical output.' This actually invokes the real corpus, real graph, and real
        AOT-compiled CLI twice and byte-compares -- not asserted in prose."""
        t32.ensure_cli_compiled()
        user_classes_cfg = t32.load_hazard_classes()["user_classes"]
        z = user_classes_cfg[t32.USER_CLASS]["z"]
        lam = user_classes_cfg[t32.USER_CLASS]["lambda"]

        run_a, _stats_a = t32.run_pipeline(
            t32.SEED, 20, t32.REPLAY_CLOCK, t32.USER_CLASS, z, lam, tmp_path / "a"
        )
        run_b, _stats_b = t32.run_pipeline(
            t32.SEED, 20, t32.REPLAY_CLOCK, t32.USER_CLASS, z, lam, tmp_path / "b"
        )

        assert run_a.errors == []
        assert run_b.errors == []
        assert len(run_a.traces) == len(run_b.traces) == 20
        assert run_a.traces == run_b.traces
        assert t32.hash_traces(run_a.traces) == t32.hash_traces(run_b.traces)


class TestReverseTwinAttachment:
    """KNOWN_FLAWS F-02 / PLAN M1.1: evidence must reach both directions of a two-way street."""

    @staticmethod
    def _edges():
        return [
            {"edge_id": 0, "from": 1, "to": 2},
            {"edge_id": 1, "from": 2, "to": 1},  # twin of 0
            {"edge_id": 2, "from": 2, "to": 3},  # one-way, no twin
            {"edge_id": 3, "from": 4, "to": 4},  # self loop, ignored
        ]

    def test_twin_index_pairs_opposite_directions_only(self):
        twins = t32.build_reverse_twin_index(self._edges())
        assert twins == {0: [1], 1: [0]}

    def test_parallel_edges_all_become_twins(self):
        edges = self._edges() + [{"edge_id": 9, "from": 2, "to": 1}]
        twins = t32.build_reverse_twin_index(edges)
        assert sorted(twins[0]) == [1, 9]

    @staticmethod
    def _write_corpus(tmp_path, snaps):
        import json

        obs_path = tmp_path / "obs.ndjson"
        snap_path = tmp_path / "snap.json"
        ids = sorted({s["observation_id"] for s in snaps})
        with open(obs_path, "w", encoding="utf-8") as f:
            for oid in ids:
                f.write(
                    json.dumps(
                        {
                            "id": oid,
                            "hazard_class": "flood",
                            "polarity": 1,
                            "observed_at": "2015-12-02T00:00:00Z",
                            "source_class": "crowd",
                        }
                    )
                    + "\n"
                )
        snap_path.write_text(json.dumps(snaps), encoding="utf-8")
        return obs_path, snap_path

    def test_default_loader_keeps_single_direction(self, tmp_path):
        obs, snap = self._write_corpus(
            tmp_path,
            [
                {"observation_id": "a", "edge_id": 0, "snap_distance_m": 4.0},
                {"observation_id": "b", "edge_id": 2, "snap_distance_m": 9.0},
            ],
        )
        by_edge = t32.load_corpus(obs, snap)
        assert set(by_edge) == {0, 2}

    def test_twin_loader_attaches_to_both_directions(self, tmp_path):
        obs, snap = self._write_corpus(
            tmp_path,
            [
                {"observation_id": "a", "edge_id": 0, "snap_distance_m": 4.0},
                {"observation_id": "b", "edge_id": 2, "snap_distance_m": 9.0},
            ],
        )
        twins = t32.build_reverse_twin_index(self._edges())
        by_edge = t32.load_corpus(obs, snap, reverse_twins=twins)
        assert set(by_edge) == {0, 1, 2}  # edge 1 gained the report; one-way edge 2 did not spread
        assert [r.id for r in by_edge[1]] == ["a"]
        assert by_edge[1][0].distance_m == 4.0  # same centreline, same snap distance
        assert [r.id for r in by_edge[2]] == ["b"]

    def test_twin_attachment_does_not_duplicate_when_both_already_have_it(self, tmp_path):
        obs, snap = self._write_corpus(
            tmp_path,
            [
                {"observation_id": "a", "edge_id": 0, "snap_distance_m": 4.0},
                {"observation_id": "a", "edge_id": 1, "snap_distance_m": 4.0},
            ],
        )
        twins = t32.build_reverse_twin_index(self._edges())
        by_edge = t32.load_corpus(obs, snap, reverse_twins=twins)
        assert [r.id for r in by_edge[0]] == ["a"]
        assert [r.id for r in by_edge[1]] == ["a"]

    def test_real_corpus_reproduces_review_figures_and_the_fix(self):
        """The 2026-10 review found 5,177 of 5,775 observed edges had a reverse twin and only
        2 of those twins carried evidence. Reproduce that, then show the fix closes it."""
        import json

        with open(t32.GRAPH_DIR / "chennai_graph_cli.json", encoding="utf-8") as f:
            twins = t32.build_reverse_twin_index(json.load(f)["edges"])
        old = t32.load_corpus()
        new = t32.load_corpus(reverse_twins=twins)

        with_twin = [e for e in old if e in twins]
        assert len(old) == 5775
        assert len(with_twin) == 5177
        assert sum(1 for e in with_twin if any(t in old for t in twins[e])) == 2

        assert all(any(t in new for t in twins[e]) for e in with_twin)
        assert len(new) > len(old) + 5000


class TestInvokeCliBatch:
    """`route-batch` (KNOWN_FLAWS F-20) keeps results aligned with the pair list and reports an
    unreachable pair as None instead of dropping it. Needs the compiled 2026-10-02 CLI, so it is
    skipped on a machine that has not built it (`make router-cli`)."""

    CLI = t32.ROOT / "data" / "bin" / "2026-10-02" / "pulse_router.exe"
    FIXTURES = t32.ROOT / "packages" / "pulse_router" / "test" / "fixtures"

    def test_alignment_and_unreachable_pair(self, tmp_path):
        import pytest

        if not self.CLI.exists():
            pytest.skip("compiled CLI not built")
        traces, errors = t32.invoke_cli_batch(
            self.CLI,
            self.FIXTURES / "smoke_graph.json",
            self.FIXTURES / "smoke_observations.json",
            [(0, 1), (1, 0)],  # no road back from 1 to 0 in the smoke graph
            "2026-09-14T12:00:00Z",
            "emergency",
            2.0,
            1.0,
            "pytest",
            tmp_path,
        )
        assert traces[0] is not None and traces[0]["chosen"]["duration_s"] == 40
        assert traces[1] is None
        assert [e["error"] for e in errors] == ["no_route"]
