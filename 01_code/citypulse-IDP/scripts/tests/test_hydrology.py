"""Tests for scripts/hydrology.py on small grids whose answers can be worked out by hand (ADR-026, Part A2)."""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import hydrology as h  # noqa: E402


def sloping_plane(n=9):
    # elevation equals the row number: water runs to row 0
    return np.repeat(np.arange(n, dtype=float)[:, None], n, axis=1)


def test_a_plain_slope_needs_no_filling():
    dem = sloping_plane()
    filled = h.fill_depressions(dem, np.zeros_like(dem, dtype=bool))
    assert np.allclose(filled, dem, atol=1e-3)


def test_a_pit_is_filled_to_the_level_of_its_lowest_exit():
    dem = sloping_plane()
    dem[4, 4] = 1.0  # a pit in a slope where its neighbours are 3, 4 and 5 high
    filled = h.fill_depressions(dem, np.zeros_like(dem, dtype=bool))
    depth = filled - dem
    assert depth[4, 4] > 1.9, "the pit should fill to about 3, the lowest cell next to it"
    assert abs(filled[4, 4] - 3.0) < 0.01
    others = depth.copy()
    others[4, 4] = 0
    assert others.max() < 0.01, "nothing else changes"


def test_every_cell_drains_somewhere_and_the_water_is_conserved():
    rng = np.random.default_rng(3)
    dem = sloping_plane(20) + rng.normal(0, 0.8, (20, 20))
    sea = np.zeros_like(dem, dtype=bool)
    filled = h.fill_depressions(dem, sea)
    down = h.flow_direction(filled)
    acc = h.flow_accumulation(filled, down)
    sinks = down.ravel() < 0
    assert acc.ravel()[sinks].sum() == dem.size, "every cell's water ends in exactly one outlet"
    assert acc.min() >= 1


def test_a_flat_plain_drains_to_the_sea():
    dem = np.ones((9, 9))
    dem[:, 0] = 0.0  # a sea along the west edge
    sea = np.zeros_like(dem, dtype=bool)
    sea[:, 0] = True
    filled = h.fill_depressions(dem, sea)
    down = h.flow_direction(filled)
    acc = h.flow_accumulation(filled, down)
    inland_sinks = (down < 0) & ~sea
    # the border of the grid is also an outlet by definition, so inland sinks can only be on the border
    border = np.zeros_like(sea)
    border[0, :] = border[-1, :] = border[:, -1] = True
    assert not (inland_sinks & ~border).any()
    assert acc.ravel()[(down < 0).ravel()].sum() == dem.size


def test_a_valley_collects_more_water_than_its_ridge():
    n = 21
    cols = np.abs(np.arange(n) - n // 2).astype(float)
    dem = np.add.outer(np.arange(n)[::-1].astype(float) * 0.5, cols * 2.0)  # a valley along the middle column, falling to the bottom row
    filled = h.fill_depressions(dem, np.zeros_like(dem, dtype=bool))
    acc = h.flow_accumulation(filled, h.flow_direction(filled))
    assert acc[n - 2, n // 2] > 10 * acc[n - 2, 1]


def test_the_result_is_deterministic():
    rng = np.random.default_rng(5)
    dem = rng.random((15, 15))
    a = h.fill_depressions(dem, np.zeros_like(dem, dtype=bool))
    b = h.fill_depressions(dem, np.zeros_like(dem, dtype=bool))
    assert np.array_equal(a, b)
