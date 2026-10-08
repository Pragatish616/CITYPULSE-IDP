"""The only places the miner may choose (ADR-030, ADR-031): OSM place names, the named field-log candidate sites, and the 31
subways of the subway watchlist (so a post about "Madley subway" can be matched to the subway, not just its area).

Retrieval combines a lexical match (any script) with an embedding match (`nomic-embed-text`, when Ollama is reachable), fused by
reciprocal rank. The model then picks one of the top five or `none`; it never supplies a coordinate.
"""

from __future__ import annotations

import hashlib
import json
from collections.abc import Callable
from dataclasses import dataclass, field
from difflib import SequenceMatcher
from pathlib import Path

import numpy as np

from ml.event_miner.schema import Candidate
from ml.event_miner.text import name_key

ROOT = Path(__file__).resolve().parents[2]
PLACES_FILE = ROOT / "data" / "places" / "chennai-2026-10-04" / "places.json"
SITES_FILE = ROOT / "server" / "app" / "fieldlog" / "sites.json"
SUBWAYS_FILE = ROOT / "data" / "watchlist" / "2026-10-09" / "subways.json"
RRF_K = 60
POOL = 20

# Words that say what kind of place it is, not which one. Dropped for the lexical match only.
GENERIC = {
    "subway", "underpass", "junction", "jn", "signal", "near", "area", "the", "at", "in", "opp", "opposite",
    "stretch", "bridge", "flyover", "road", "rd", "main", "street", "st",
    "சுரங்கப்பாதை", "சாலை", "அருகே", "பகுதி", "சந்திப்பு", "பாலம்",
}


@dataclass(frozen=True)
class Place:
    id: str
    name: str
    kind: str
    lat: float
    lon: float
    alt: tuple[str, ...] = ()

    @property
    def names(self) -> tuple[str, ...]:
        return (self.name, *self.alt)

    def document(self) -> str:
        return f"{self.name} ({self.kind}, Chennai)" + (f"; also {', '.join(self.alt)}" if self.alt else "")


def _strip_generic(key: str) -> str:
    return " ".join(w for w in key.split() if w not in GENERIC)


def load_places(
    places_file: Path = PLACES_FILE, sites_file: Path = SITES_FILE, subways_file: Path | None = SUBWAYS_FILE
) -> list[Place]:
    out: list[Place] = []
    seen: dict[str, int] = {}
    for row in json.loads(places_file.read_text(encoding="utf-8"))["places"]:
        name, lat, lon, kind, *alt = row
        slug = name_key(name).replace(" ", "-") or "place"
        seen[slug] = seen.get(slug, 0) + 1
        pid = f"place:{slug}" if seen[slug] == 1 else f"place:{slug}-{seen[slug]}"
        out.append(Place(pid, name, kind, float(lat), float(lon), tuple(a for a in alt if a)))
    for s in json.loads(sites_file.read_text(encoding="utf-8"))["sites"]:
        street = s["label"].split(", near ")[0]
        if street.lower().startswith("unnamed road"):
            continue  # nothing in a text can name it; its area is in the place list
        near = s.get("near")
        out.append(Place(s["id"], street, "candidate site (street)", float(s["lat"]), float(s["lon"]),
                         (f"{street} near {near}",) if near else ()))
    if subways_file is not None:
        for e in json.loads(subways_file.read_text(encoding="utf-8"))["entries"]:
            alts = [a for a in [e.get("name_ta"), *[n["name"] for n in e.get("names_in_news", [])], e.get("gcc_location")] if a]
            if e["lat"] is not None:
                lat, lon, kind = e["lat"], e["lon"], f"subway ({e['list'].replace('_', ' ')})"
            elif e.get("area_hint"):
                # No position is known: the AREA's point stands in so the entry can be matched by name; the kind says so.
                lat, lon, kind = e["area_hint"]["lat"], e["area_hint"]["lon"], "subway (position not known; area point)"
            else:
                continue  # a name with neither a position nor an area cannot be placed
            out.append(Place(e["id"], e["name"], kind, float(lat), float(lon), tuple(alts)))
    return out


def gazetteer_hash(places: list[Place]) -> str:
    h = hashlib.sha256()
    for p in places:
        h.update(f"{p.id}|{p.name}|{p.kind}|{p.lat}|{p.lon}|{'|'.join(p.alt)}\n".encode())
    return h.hexdigest()[:16]


def lexical_score(query: str, place: Place) -> float:
    q, qs = name_key(query), _strip_generic(name_key(query))
    best = 0.0
    for n in place.names:
        k = name_key(n)
        ks = _strip_generic(k)
        for a, b in ((q, k), (qs, ks)):
            if not a or not b:
                continue
            if a == b:
                return 1.0
            score = SequenceMatcher(None, a, b).ratio()
            # one name contained whole in the other, as words ("ganesapuram" in "ganesapuram subway")
            if f" {b} " in f" {a} " or f" {a} " in f" {b} ":
                score = max(score, 0.9)
            best = max(best, score)
    return best


@dataclass
class Retriever:
    places: list[Place]
    embed: Callable[[list[str]], list[list[float]]] | None = None
    cache_file: Path | None = None
    _vectors: np.ndarray | None = field(default=None, init=False, repr=False)

    def _doc_vectors(self) -> np.ndarray | None:
        if self.embed is None:
            return None
        if self._vectors is not None:
            return self._vectors
        key = gazetteer_hash(self.places)
        if self.cache_file and self.cache_file.exists():
            data = np.load(self.cache_file, allow_pickle=False)
            if str(data["key"]) == key and data["vectors"].shape[0] == len(self.places):
                self._vectors = data["vectors"]
                return self._vectors
        docs = [f"search_document: {p.document()}" for p in self.places]
        vecs: list[list[float]] = []
        for i in range(0, len(docs), 64):
            vecs.extend(self.embed(docs[i : i + 64]))
        arr = np.asarray(vecs, dtype=np.float32)
        arr /= np.linalg.norm(arr, axis=1, keepdims=True) + 1e-12
        self._vectors = arr
        if self.cache_file:
            self.cache_file.parent.mkdir(parents=True, exist_ok=True)
            np.savez(self.cache_file, key=np.asarray(key), vectors=arr)
        return arr

    def top(self, query: str, k: int = 5) -> list[Candidate]:
        lex = sorted(((lexical_score(query, p), p.id) for p in self.places), key=lambda x: (-x[0], x[1]))
        ranks: dict[str, float] = {}
        exact = [pid for s, pid in lex if s >= 1.0]
        for rank, (_, pid) in enumerate(lex[:POOL]):
            ranks[pid] = ranks.get(pid, 0.0) + 1.0 / (RRF_K + rank + 1)
        vecs = self._doc_vectors()
        if vecs is not None:
            q = np.asarray(self.embed([f"search_query: {query}"])[0], dtype=np.float32)  # type: ignore[misc]
            q /= np.linalg.norm(q) + 1e-12
            sims = vecs @ q
            order = np.lexsort((np.arange(len(sims)), -sims))[:POOL]
            for rank, i in enumerate(order):
                pid = self.places[int(i)].id
                ranks[pid] = ranks.get(pid, 0.0) + 1.0 / (RRF_K + rank + 1)
        by_id = {p.id: p for p in self.places}
        ordered = sorted(ranks, key=lambda pid: (pid not in exact, -ranks[pid], pid))[:k]
        return [
            Candidate(id=pid, name=by_id[pid].name, kind=by_id[pid].kind, lat=by_id[pid].lat, lon=by_id[pid].lon,
                      score=round(ranks[pid], 5))
            for pid in ordered
        ]


def distance_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    r = 6371008.8
    p1, p2 = np.radians(lat1), np.radians(lat2)
    dp, dl = p2 - p1, np.radians(lon2 - lon1)
    a = np.sin(dp / 2) ** 2 + np.cos(p1) * np.cos(p2) * np.sin(dl / 2) ** 2
    return float(2 * r * np.arcsin(np.sqrt(a)))
