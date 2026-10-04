"""Small, tested terrain hydrology for the susceptibility study (ADR-026, Part A2): depression filling, D8 flow direction, flow accumulation.

Written from the published algorithms (priority-flood depression filling with a small epsilon so flat areas drain, Barnes et al. 2014; D8 steepest
descent; accumulation by processing cells from high to low). Pure numpy and heapq: slow for very large grids but adequate for the
~1.4 million cells of the Chennai study area. Cells in `outlets` and cells on the grid border can drain out of the grid.
"""

from __future__ import annotations

import heapq

import numpy as np

# neighbour offsets (row, col) and their horizontal distance in cell units
NEIGHBOURS = [(-1, -1, 2**0.5), (-1, 0, 1.0), (-1, 1, 2**0.5), (0, -1, 1.0), (0, 1, 1.0), (1, -1, 2**0.5), (1, 0, 1.0), (1, 1, 2**0.5)]


def fill_depressions(dem: np.ndarray, outlets: np.ndarray, eps: float = 1e-4) -> np.ndarray:
    """Raise every cell that cannot drain to the lowest level from which it drains, leaving a gradient of `eps` per cell on flats.

    `outlets` marks cells that are drains (the sea); the grid border is an outlet as well. Returns float64.
    """
    H, W = dem.shape
    dem = dem.astype(np.float64)
    filled = np.full((H, W), np.inf)
    closed = np.zeros((H, W), dtype=bool)
    heap: list[tuple[float, int, int]] = []
    border = np.zeros((H, W), dtype=bool)
    border[0, :] = border[-1, :] = border[:, 0] = border[:, -1] = True
    for r, c in zip(*np.nonzero(outlets | border)):
        filled[r, c] = dem[r, c]
        closed[r, c] = True
        heapq.heappush(heap, (dem[r, c], int(r), int(c)))
    while heap:
        level, r, c = heapq.heappop(heap)
        for dr, dc, _ in NEIGHBOURS:
            nr, nc = r + dr, c + dc
            if 0 <= nr < H and 0 <= nc < W and not closed[nr, nc]:
                closed[nr, nc] = True
                v = max(dem[nr, nc], level + eps)
                filled[nr, nc] = v
                heapq.heappush(heap, (v, nr, nc))
    return filled


def flow_direction(filled: np.ndarray) -> np.ndarray:
    """Index (flattened) of the steepest-descent neighbour of every cell, or -1 where no neighbour is lower (outlets and border sinks)."""
    H, W = filled.shape
    best = np.zeros((H, W))
    down = np.full((H, W), -1, dtype=np.int64)
    pad = np.pad(filled, 1, constant_values=np.inf)
    rows, cols = np.indices((H, W))
    for dr, dc, dist in NEIGHBOURS:
        nb = pad[1 + dr : 1 + dr + H, 1 + dc : 1 + dc + W]
        drop = (filled - nb) / dist
        better = drop > best
        best = np.where(better, drop, best)
        down = np.where(better, (rows + dr) * W + (cols + dc), down)
    return down


def flow_accumulation(filled: np.ndarray, down: np.ndarray) -> np.ndarray:
    """Number of cells (including itself) whose water passes through each cell."""
    H, W = filled.shape
    acc = np.ones(H * W)
    flat_down = down.ravel()
    order = np.argsort(-filled.ravel(), kind="stable")
    for i in order:
        j = flat_down[i]
        if j >= 0:
            acc[j] += acc[i]
    return acc.reshape(H, W)
