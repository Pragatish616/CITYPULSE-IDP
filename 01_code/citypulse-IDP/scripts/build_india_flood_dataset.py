"""Merge the free Indian flood sources into one event dataset (ADR-023).

Inputs (all in data/india_flood/<date>/raw/, downloaded once, never edited):
  India_Flood_Inventory_v3.csv  IFI v4 record, IMD events 1967-2023, district names + LGD codes, no coordinates
  DFSI.csv, District_FloodedArea.csv, District_FloodImpact.csv   IFI v4 district tables
  dfo_india_events.geojson      Dartmouth Flood Observatory large-event polygons (dates, deaths, cause)
  data/packs/tamil_nadu-backbone-*/places.json   OSM place list, used only to put a point on each
                                                 Tamil Nadu district headquarters town

Outputs (data/india_flood/<date>/):
  events.ndjson           one row per source event, both sources, all India
  dfo_events.geojson      the DFO polygons, with the ids used in events.ndjson
  district_summary.csv    one row per district: severity index, flooded area, impacts, event counts
  tn_event_calendar.csv   Tamil Nadu events from both sources, clustered by the link rule below
  links_tn.csv            every IMD-DFO link behind the calendar
  result.json, MANIFEST.md

LINK RULE (fixed before any count was looked at, CLAUDE.md rule R3):
  An IMD event E and a DFO event D are linked iff
    (1) their date ranges overlap after widening each by LINK_DAYS (3) days on both sides, and
    (2) D's polygon contains the headquarters point of at least one district named in E.
  Tamil Nadu only: that is the only state with district points here. A district has no point
  if its headquarters town is not found in the place list; such districts cannot create a link.

What this is NOT: a street-level dataset. Every IFI row is at district level and every DFO polygon is
a hand-drawn region of thousands of square kilometres. Deaths from the two sources are never added.
All rows are tagged non-commercial (IFI: CC BY-NC 4.0; DFO: CC BY 3.0 for older events and
CC BY-NC-SA 4.0 for recent ones, so treated as non-commercial).
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import hashlib
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LINK_DAYS = 3

# District headquarters towns for the place-list lookup. The district name as IFI spells it (after
# normalisation) maps to the town to look for in OpenStreetMap's place list. Where the district and
# its headquarters have different names, the town is named here.
HQ_TOWN = {
    "ariyalur": "Ariyalur", "chengalpattu": "Chengalpattu", "chennai": "Chennai",
    "coimbatore": "Coimbatore", "cuddalore": "Cuddalore", "dharmapuri": "Dharmapuri",
    "dindigul": "Dindigul", "erode": "Erode", "kallakurichi": "Kallakurichi",
    "kancheepuram": "Kanchipuram", "kanniyakumari": "Nagercoil", "karur": "Karur",
    "krishnagiri": "Krishnagiri", "madurai": "Madurai", "mayiladuthurai": "Mayiladuthurai",
    "nagapattinam": "Nagapattinam", "namakkal": "Namakkal", "thenilgiris": "Udhagamandalam",
    "perambalur": "Perambalur", "pudukkottai": "Pudukkottai", "ramanathapuram": "Ramanathapuram",
    "ranipet": "Ranipet", "salem": "Salem", "sivaganga": "Sivaganga", "tenkasi": "Tenkasi",
    "thanjavur": "Thanjavur", "theni": "Theni", "thoothukkudi": "Thoothukudi",
    "tiruchirappalli": "Tiruchirappalli", "tirunelveli": "Tirunelveli",
    "tirupathur": "Tirupattur", "tiruppur": "Tiruppur", "thiruvallur": "Tiruvallur",
    "tiruvannamalai": "Tiruvannamalai", "thiruvarur": "Thiruvarur", "vellore": "Vellore",
    "viluppuram": "Viluppuram", "virudhunagar": "Virudhunagar",
}
# IFI misspellings or variants of a name, mapped to the form used as a key above.
NAME_FIX = {
    "kanniyakumariumari": "kanniyakumari", "nagarkoil": "kanniyakumari", "tiruvallur": "thiruvallur",
    "villupuram": "viluppuram", "tuticorin": "thoothukkudi", "thoothukudi": "thoothukkudi",
    "kanchipuram": "kancheepuram", "tiruvarur": "thiruvarur", "tirupattur": "tirupathur",
    "nilgiris": "thenilgiris", "tiruchirapalli": "tiruchirappalli", "trichy": "tiruchirappalli",
}
TN_BOX = (8.0, 13.6, 76.2, 80.4)  # min_lat, max_lat, min_lon, max_lon (config/cities.yaml)


def key(name: str) -> str:
    k = re.sub(r"[^a-z]", "", name.lower())
    return NAME_FIX.get(k, k)


def sha256(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def parse_date(s: str) -> dt.date | None:
    s = (s or "").strip()
    for fmt in ("%d-%m-%Y %H:%M", "%d-%m-%Y"):
        try:
            return dt.datetime.strptime(s, fmt).date()
        except ValueError:
            pass
    return None


def to_int(s) -> int | None:
    try:
        return int(float(str(s).strip()))
    except (ValueError, TypeError):
        return None


def split_list(s: str) -> list[str]:
    return [x.strip() for x in (s or "").split(",") if x.strip()]


def ring_contains(ring, x, y) -> bool:
    inside = False
    n = len(ring)
    j = n - 1
    for i in range(n):
        xi, yi = ring[i][0], ring[i][1]
        xj, yj = ring[j][0], ring[j][1]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            inside = not inside
        j = i
    return inside


def polygon_contains(geom, lon, lat) -> bool:
    polys = [geom["coordinates"]] if geom["type"] == "Polygon" else geom["coordinates"]
    for rings in polys:
        if ring_contains(rings[0], lon, lat) and not any(ring_contains(h, lon, lat) for h in rings[1:]):
            return True
    return False


def geom_bbox(geom):
    polys = [geom["coordinates"]] if geom["type"] == "Polygon" else geom["coordinates"]
    xs = [p[0] for rings in polys for p in rings[0]]
    ys = [p[1] for rings in polys for p in rings[0]]
    return [round(min(xs), 4), round(min(ys), 4), round(max(xs), 4), round(max(ys), 4)]


def iso(d: dt.date | None) -> str:
    return d.isoformat() if d else ""


def overlaps(a0, a1, b0, b1, days) -> bool:
    w = dt.timedelta(days=days)
    return a0 - w <= b1 + w and b0 - w <= a1 + w


def load_hq_points(places_path: Path) -> tuple[dict, list]:
    places = json.loads(places_path.read_text(encoding="utf-8"))["places"]
    by_name: dict[str, list] = defaultdict(list)
    for row in places:
        name, lat, lon, kind = row[0], row[1], row[2], row[3]
        alts = row[4:]
        if not (TN_BOX[0] <= lat <= TN_BOX[1] and TN_BOX[2] <= lon <= TN_BOX[3]):
            continue
        for n in [name, *alts]:
            by_name[re.sub(r"[^a-z]", "", n.lower())].append((kind, lat, lon, name))
    rank = {"city": 0, "town": 1, "suburb": 2, "village": 3}
    pts, missing = {}, []
    for dkey, town in sorted(HQ_TOWN.items()):
        cands = by_name.get(re.sub(r"[^a-z]", "", town.lower()), [])
        if not cands:
            missing.append(dkey)
            continue
        kind, lat, lon, name = sorted(cands, key=lambda c: (rank.get(c[0], 9), c[3]))[0]
        pts[dkey] = {"lat": lat, "lon": lon, "town": name, "kind": kind}
    return pts, missing


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--date", default="2026-10-04")
    ap.add_argument("--places", default=str(ROOT / "data/packs/tamil_nadu-backbone-2026-10-03/places.json"))
    a = ap.parse_args()
    base = ROOT / "data" / "india_flood" / a.date
    raw = base / "raw"

    # ---- IFI events (IMD) ----
    ifi_rows = list(csv.DictReader((raw / "India_Flood_Inventory_v3.csv").open(encoding="utf-8-sig")))
    events, ifi = [], []
    for r in ifi_rows:
        s, e = parse_date(r["Start Date"]), parse_date(r["End Date"]) or parse_date(r["Start Date"])
        states = split_list(r["State"])
        districts = split_list(r["Districts"])
        lgd = split_list(r["District_LGD_Codes"])
        ev = {
            "event_id": r["UEI"].strip(),
            "source": "IMD via India Flood Inventory v4",
            "granularity": "district_list",
            "start": iso(s), "end": iso(e or s),
            "states": states, "districts": districts,
            "lgd_codes": lgd if len(lgd) == len(districts) else [],
            "cause": r["Main Cause"].strip(),
            "deaths": to_int(r["Human fatality"]), "displaced": to_int(r["Human Displaced"]),
            "severity": None, "bbox": None,
            "licence": "CC-BY-NC-4.0", "commercial_use": False,
        }
        ifi.append((ev, s, e or s))
        events.append(ev)

    # ---- DFO events ----
    dfo_geo = json.loads((raw / "dfo_india_events.geojson").read_text(encoding="utf-8"))
    dfo, dfo_out = [], []
    for f in dfo_geo["features"]:
        p, g = f["properties"], f["geometry"]
        s = dt.datetime.fromtimestamp(p["BEGAN"] / 1000, dt.timezone.utc).date() if p["BEGAN"] else None
        e = dt.datetime.fromtimestamp(p["ENDED"] / 1000, dt.timezone.utc).date() if p["ENDED"] else s
        eid = f"DFO-{int(p['ID'])}"
        glide = (p["GLIDENUMBE"] or "").strip()
        ev = {
            "event_id": eid, "source": "Dartmouth Flood Observatory",
            "granularity": "region_polygon",
            "start": iso(s), "end": iso(e),
            "states": [], "districts": [], "lgd_codes": [],
            "cause": (p["MAINCAUSE"] or "").strip(),
            "deaths": to_int(p["DEAD"]), "displaced": to_int(p["DISPLACED"]),
            "severity": p["SEVERITY"], "bbox": geom_bbox(g),
            "glide": glide if glide not in ("", "0") else "",
            "validation": (p["VALIDATION"] or "").strip(),
            "countries": [c.strip() for c in {p["COUNTRY"] or "", p["OTHERCOUNT"] or ""} if c.strip() and c.strip() != "0"],
            "licence": "CC-BY-3.0 (older) / CC-BY-NC-SA-4.0 (recent); treated as non-commercial",
            "commercial_use": False,
        }
        dfo.append((ev, s, e, g))
        events.append(ev)
        dfo_out.append({"type": "Feature", "properties": {"event_id": eid}, "geometry": g})

    events.sort(key=lambda x: (x["source"], x["start"], x["event_id"]))
    with (base / "events.ndjson").open("w", encoding="utf-8", newline="\n") as fh:
        for ev in events:
            fh.write(json.dumps(ev, ensure_ascii=False, sort_keys=True) + "\n")
    (base / "dfo_events.geojson").write_text(
        json.dumps({"type": "FeatureCollection", "features": dfo_out}, sort_keys=True), encoding="utf-8"
    )

    # ---- Tamil Nadu headquarters points ----
    hq, hq_missing = load_hq_points(Path(a.places))

    # ---- district summary ----
    def read(name):
        return list(csv.DictReader((raw / name).open(encoding="utf-8-sig")))

    dfsi = read("DFSI.csv")
    area = read("District_FloodedArea.csv")
    impact = read("District_FloodImpact.csv")
    area_by, impact_by = defaultdict(list), defaultdict(list)
    for r in area:
        area_by[key(r["Dist_Name"])].append(r)
    for r in impact:
        impact_by[key(r["Dist_Name"])].append(r)
    counts, counts2000 = Counter(), Counter()
    for ev, s, _ in ifi:
        for st in ev["states"][:1] if len(ev["states"]) == 1 else ev["states"]:
            for d in ev["districts"]:
                counts[(key(st), key(d))] += 1
                if s and s.year >= 2000:
                    counts2000[(key(st), key(d))] += 1
    summary, ambiguous, no_area, no_impact = [], 0, 0, 0
    for r in dfsi:
        name, state = (r[""] or "").strip(), r["State_Name"].strip()
        k = key(name)
        a_rows, i_rows = area_by.get(k, []), impact_by.get(k, [])
        note = []
        if len(a_rows) != 1:
            note.append("flooded_area: " + ("ambiguous name" if len(a_rows) > 1 else "no match"))
            ambiguous += len(a_rows) > 1
            no_area += not a_rows
        if len(i_rows) != 1:
            note.append("impact: " + ("ambiguous name" if len(i_rows) > 1 else "no match"))
            no_impact += not i_rows
        ar = a_rows[0] if len(a_rows) == 1 else {}
        im = i_rows[0] if len(i_rows) == 1 else {}
        ksta = re.sub(r"[^a-z]", "", state.lower())
        n_all = sum(v for (st, d), v in counts.items() if d == k and (st == ksta or ksta.startswith(st) or st.startswith(ksta)))
        n_2000 = sum(v for (st, d), v in counts2000.items() if d == k and (st == ksta or ksta.startswith(st) or st.startswith(ksta)))
        summary.append({
            "state": state, "district": name, "dfsi": r["DFSI"],
            "pct_flooded_area_corrected": ar.get("Corrected_Percent_Flooded_Area", ""),
            "fatalities": im.get("Human_fatality", ""), "injured": im.get("Human_injured", ""),
            "population": im.get("Population", ""), "mean_flood_duration_days": im.get("Mean_Flood_Duration", ""),
            "ifi_events_1967_2023": n_all, "ifi_events_2000_2023": n_2000,
            "join_note": "; ".join(note),
        })
    summary.sort(key=lambda x: (x["state"], x["district"]))
    with (base / "district_summary.csv").open("w", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(summary[0]))
        w.writeheader()
        w.writerows(summary)

    # ---- Tamil Nadu links and calendar ----
    tn_imd = [(ev, s, e) for ev, s, e in ifi if "Tamil Nadu" in ev["states"]]
    tn_dfo_all = [(ev, s, e, g) for ev, s, e, g in dfo]
    links = []
    for ev, s, e in tn_imd:
        if not s:
            continue
        dist_keys = [key(d) for d in ev["districts"]]
        pts = [(k, hq[k]) for k in dist_keys if k in hq]
        for dev, ds, de, g in tn_dfo_all:
            if not ds or not overlaps(s, e, ds, de or ds, LINK_DAYS):
                continue
            inside = [k for k, p in pts if polygon_contains(g, p["lon"], p["lat"])]
            if inside:
                links.append({"imd_id": ev["event_id"], "dfo_id": dev["event_id"], "districts_inside": "|".join(sorted(set(inside)))})
    links.sort(key=lambda x: (x["imd_id"], x["dfo_id"]))
    with (base / "links_tn.csv").open("w", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=["imd_id", "dfo_id", "districts_inside"])
        w.writeheader()
        w.writerows(links)

    # clusters = connected components of the link graph, plus unlinked TN IMD events; DFO events
    # that are linked to nothing are not Tamil Nadu events by this rule and are left out.
    parent = {}

    def find(x):
        parent.setdefault(x, x)
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for ev, _, _ in tn_imd:
        find(ev["event_id"])
    for l in links:
        parent[find(l["imd_id"])] = find(l["dfo_id"])
    byid = {ev["event_id"]: (ev, s, e) for ev, s, e in tn_imd}
    dbyid = {ev["event_id"]: (ev, s, e) for ev, s, e, _ in dfo}
    groups = defaultdict(list)
    for x in list(parent):
        groups[find(x)].append(x)
    calendar = []
    for members in groups.values():
        imd = sorted(m for m in members if m in byid)
        dd = sorted(m for m in members if m in dbyid)
        starts = [byid[m][1] for m in imd if byid[m][1]] + [dbyid[m][1] for m in dd if dbyid[m][1]]
        ends = [byid[m][2] for m in imd if byid[m][2]] + [dbyid[m][2] for m in dd if dbyid[m][2]]
        if not starts:
            continue
        districts = sorted({d for m in imd for d in byid[m][0]["districts"]})
        calendar.append({
            "start": iso(min(starts)), "end": iso(max(ends)),
            "n_imd": len(imd), "n_dfo": len(dd),
            "corroborated_by_both_sources": bool(imd and dd),
            "districts": "; ".join(districts),
            "chennai_named": any(key(d) == "chennai" for d in districts),
            "imd_deaths_max": max([byid[m][0]["deaths"] or 0 for m in imd] or [0]),
            "dfo_deaths_max": max([dbyid[m][0]["deaths"] or 0 for m in dd] or [0]),
            "causes": "; ".join(sorted({byid[m][0]["cause"] for m in imd if byid[m][0]["cause"]} | {dbyid[m][0]["cause"] for m in dd if dbyid[m][0]["cause"]})),
            "imd_ids": "|".join(imd), "dfo_ids": "|".join(dd),
            "licence": "CC-BY-NC-4.0 and DFO terms: research use only",
        })
    calendar.sort(key=lambda x: (x["start"], x["imd_ids"], x["dfo_ids"]))
    with (base / "tn_event_calendar.csv").open("w", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(calendar[0]))
        w.writeheader()
        w.writerows(calendar)

    # ---- the Chennai 2015 check (reads, does not alter, the existing replay corpus) ----
    chennai_pt = hq["chennai"]
    chennai_2015 = {
        "proxy_timestamp_in_replay_corpus": "2015-12-02",
        "imd_events_naming_chennai_2015-11-01_to_2015-12-31": [
            {"id": ev["event_id"], "start": iso(s), "end": iso(e)}
            for ev, s, e in tn_imd
            if s and dt.date(2015, 11, 1) <= s <= dt.date(2015, 12, 31) and any(key(d) == "chennai" for d in ev["districts"])
        ],
        "dfo_events_2015_containing_chennai_hq": [
            {"id": dev["event_id"], "start": iso(ds), "end": iso(de)}
            for dev, ds, de, g in dfo
            if ds and ds.year == 2015 and polygon_contains(g, chennai_pt["lon"], chennai_pt["lat"])
        ],
    }
    proxy = dt.date(2015, 12, 2)
    chennai_2015["proxy_date_inside_an_imd_chennai_event"] = any(
        dt.date.fromisoformat(x["start"]) <= proxy <= dt.date.fromisoformat(x["end"])
        for x in chennai_2015["imd_events_naming_chennai_2015-11-01_to_2015-12-31"]
    )

    # ---- result and manifest ----
    cal_both = sum(1 for c in calendar if c["corroborated_by_both_sources"])
    result = {
        "task": "ADR-023 merged India flood event dataset",
        "built": a.date,
        "script": "scripts/build_india_flood_dataset.py",
        "link_rule": {"link_days": LINK_DAYS, "text": "date overlap (+-3 days) AND DFO polygon contains the HQ point of a named district; Tamil Nadu only"},
        "inputs_sha256": {p.name: sha256(p) for p in sorted(raw.iterdir())},
        "counts": {
            "ifi_events": len(ifi), "ifi_years": [min(e["start"] for e, _, _ in ifi if e["start"]), max(e["start"] for e, _, _ in ifi if e["start"])],
            "ifi_events_with_coordinates": 0, "dfo_events": len(dfo),
            "dfo_events_with_india_in_countries": sum(1 for e, *_ in dfo if any("India" in c for c in e["countries"])),
            "tn_imd_events": len(tn_imd), "tn_districts_with_hq_point": len(hq),
            "tn_districts_without_hq_point": hq_missing,
            "links": len(links), "tn_calendar_rows": len(calendar), "tn_calendar_corroborated_by_both": cal_both,
            "tn_calendar_chennai_named": sum(1 for c in calendar if c["chennai_named"]),
            "district_rows": len(summary), "district_rows_no_area_match": no_area, "district_rows_ambiguous_area_name": ambiguous,
            "district_rows_no_impact_match": no_impact,
        },
        "chennai_2015": chennai_2015,
        "limits": [
            "IFI rows have no coordinates: district level only.",
            "DFO polygons are hand-drawn regions; most cover thousands of square kilometres.",
            "District points exist for Tamil Nadu only, from OSM place names (not boundaries).",
            "Deaths from the two sources are different counts and are never summed.",
            "Non-commercial licences: research use only; filter commercial_use=false rows out of any product build.",
        ],
    }
    (base / "result.json").write_text(json.dumps(result, indent=2, ensure_ascii=False, sort_keys=True), encoding="utf-8")
    print(json.dumps(result["counts"], indent=1, ensure_ascii=False))
    print(json.dumps(chennai_2015, indent=1, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
