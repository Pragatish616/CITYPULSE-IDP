"""GPS trace files to (t epoch seconds, lat, lon) arrays (C8). Formats: GPX 1.1 track points with times; phyphox "Location" CSV
(time in seconds since the recording started, so the start time must be given); any CSV with columns containing "time", "lat", "lon"
(time either epoch seconds or ISO 8601).

The phyphox header text was not checked against a real export [UNVERIFIED]; columns are found by keyword.
"""

from __future__ import annotations

import csv
import xml.etree.ElementTree as ET
from datetime import datetime
from pathlib import Path

import numpy as np


def _epoch(text: str) -> float:
    text = text.strip()
    try:
        return float(text)
    except ValueError:
        return datetime.fromisoformat(text.replace("Z", "+00:00")).timestamp()


def read_gpx(path: Path) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    root = ET.parse(path).getroot()
    t, la, lo = [], [], []
    for el in root.iter():
        if el.tag.endswith("trkpt"):
            when = next((c.text for c in el if c.tag.endswith("time")), None)
            if when is None:
                continue
            t.append(_epoch(when))
            la.append(float(el.attrib["lat"]))
            lo.append(float(el.attrib["lon"]))
    return _clean(np.array(t), np.array(la), np.array(lo))


def read_csv(path: Path, *, start_epoch: float | None = None) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Generic or phyphox CSV. With ``start_epoch``, the time column is taken as seconds since that moment (phyphox)."""
    with open(path, newline="", encoding="utf-8-sig") as f:
        dialect = csv.Sniffer().sniff(f.read(4096), delimiters=",;\t")
        f.seek(0)
        rows = list(csv.reader(f, dialect))
    head = [h.strip().lower() for h in rows[0]]

    def col(key: str) -> int:
        for i, h in enumerate(head):
            if key in h:
                return i
        raise ValueError(f"{path.name}: no column containing '{key}' in {rows[0]}")

    it, ila, ilo = col("time"), col("lat"), col("lon")
    t, la, lo = [], [], []
    for r in rows[1:]:
        try:
            tt = float(r[it]) + start_epoch if start_epoch is not None else _epoch(r[it])
            t.append(tt)
            la.append(float(r[ila]))
            lo.append(float(r[ilo]))
        except (ValueError, IndexError):
            continue
    return _clean(np.array(t), np.array(la), np.array(lo))


def _clean(t: np.ndarray, la: np.ndarray, lo: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Sorted by time, duplicates in time dropped."""
    order = np.argsort(t, kind="stable")
    t, la, lo = t[order], la[order], lo[order]
    keep = np.concatenate([[True], np.diff(t) > 0])
    return t[keep], la[keep], lo[keep]


def read_any(path: Path, *, start_epoch: float | None = None) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    return read_gpx(path) if path.suffix.lower() == ".gpx" else read_csv(path, start_epoch=start_epoch)
