"""One-off live-data probe of the Chennai Flood Monitor (CFM-DSS) public WFS (NEXT_STEPS "data test", ADR-024 go-ahead of 9 Oct 2026).

The owner approved exactly TWO read-only requests to this government server:
  1. WFS GetCapabilities (which layers exist);
  2. WFS GetFeature, count=5, on ONE layer (to see whether readings carry today's timestamp).
This script makes those two requests and no others: no retry, no second layer, no pagination. If request 1 fails it stops and says
so (it does not try other paths). It stores only counts, layer names, property KEYS and timestamp values; no station names, no
free text, nothing personal.

    python scripts/cfm_live_probe.py            # makes the two requests and writes the result file
    python scripts/cfm_live_probe.py --dry-run  # prints what it would ask, makes no request
    python scripts/cfm_live_probe.py --base https://HOST/PATH/wfs --layer ChennaiDSS:awlr_transaction --sort time_of_measurement
        # ONE request only (GetFeature, count=5, newest first), for when the correct endpoint path is known

First run, 8 Oct 2026 21:40 UTC: request 1 (GET /geoserver/ows) returned HTTP 404 from the web server in front of GeoServer, so the
path was wrong and the test is INCONCLUSIVE, not negative. One of the two approved requests remains.

Writes data/results/<date>-cfm-live-probe/result.json.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = "https://chennaifloodmonitor.tn.gov.in/geoserver/ows"
USER_AGENT = "CityPulse-research/1.0 (+https://github.com/Pragatish616/CITYPULSE-IDP; contact via the repository)"
TIMEOUT = 60
# Layers worth reading for a live timestamp, best first. Names come from the 2026-09-29 archive's layer catalogue; the one
# actually used is the first that GetCapabilities lists. None is a subway or barrier layer: the catalogue has none.
PREFERRED = (
    "gis_awlrrls_waterlevel_with_latest_datetime",
    "gis_waterlevel_display_points_datetime",
    "gis_waterlevel_display_points",
    "gis_crowdsourced",
)
INTEREST = re.compile(r"subway|barrier|underpass|sensor|gauge|awlr|cctv|camera|flood.?meter|waterlog|crowd|latest|datetime", re.IGNORECASE)
TIME_KEY = re.compile(r"date|time|stamp|updated|reading|observ", re.IGNORECASE)


def capabilities_url() -> str:
    return BASE + "?" + urllib.parse.urlencode({"service": "WFS", "version": "2.0.0", "request": "GetCapabilities"})


def feature_url(type_name: str, base: str = BASE, sort: str | None = None) -> str:
    params = {
        "service": "WFS", "version": "2.0.0", "request": "GetFeature", "typeNames": type_name,
        "count": "5", "outputFormat": "application/json",
    }
    if sort:
        params["sortBy"] = f"{sort} D"  # newest first: the readings that say whether the layer is live
    return base + "?" + urllib.parse.urlencode(params)


def fetch(url: str) -> tuple[int, bytes, str | None]:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "*/*"})
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            return r.status, r.read(), r.headers.get("content-type")
    except urllib.error.HTTPError as e:
        return e.code, e.read()[:2000], e.headers.get("content-type")
    except (urllib.error.URLError, TimeoutError, OSError) as e:
        return 0, repr(e).encode()[:500], None


def parse_layer_names(xml: str) -> list[str]:
    """Feature type names from a WFS capabilities document (namespace prefix kept: `ChennaiDSS:layer`)."""
    return re.findall(r"<(?:\w+:)?FeatureType>\s*<(?:\w+:)?Name>([^<]+)</(?:\w+:)?Name>", xml)


def choose_layer(names: list[str]) -> str | None:
    bare = {n.split(":")[-1]: n for n in names}
    for want in PREFERRED:
        if want in bare:
            return bare[want]
    return None


def parse_time(value) -> datetime | None:
    if not isinstance(value, str):
        return None
    v = value.strip().replace("Z", "+00:00")
    for fmt in (None, "%d-%m-%Y %H:%M:%S", "%d/%m/%Y %H:%M:%S", "%d-%m-%Y %H:%M", "%Y-%m-%d %H:%M:%S"):
        try:
            t = datetime.fromisoformat(v) if fmt is None else datetime.strptime(v, fmt)  # noqa: DTZ007 (zone attached just below)
        except ValueError:
            continue
        # A reading without a zone is taken as India time (UTC+05:30), the server's own: stated, not verified.
        return t.replace(tzinfo=timezone(timedelta(hours=5, minutes=30))) if t.tzinfo is None else t
    return None


def summarise_features(doc: dict, now: datetime) -> dict:
    feats = doc.get("features") or []
    keys = sorted({k for f in feats for k in (f.get("properties") or {})})
    time_keys = [k for k in keys if TIME_KEY.search(k)]
    stamps = []
    for f in feats:
        for k in time_keys:
            t = parse_time((f.get("properties") or {}).get(k))
            if t is not None:
                stamps.append((k, t))
    newest = max((t for _, t in stamps), default=None)
    return {
        "features_returned": len(feats),
        "property_keys": keys,
        "time_like_keys": time_keys,
        "timestamps_parsed": len(stamps),
        "timestamp_values": sorted({t.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ") for _, t in stamps}),
        "newest_timestamp_utc": newest.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ") if newest else None,
        "age_of_newest_hours": round((now - newest).total_seconds() / 3600, 2) if newest else None,
        "newest_is_from_today_ist": bool(newest and newest.astimezone(timezone(timedelta(hours=5, minutes=30))).date()
                                         == now.astimezone(timezone(timedelta(hours=5, minutes=30))).date()),
    }


def single_feature(args, now: datetime) -> int:
    """The one remaining approved request: GetFeature on a named layer at a stated endpoint."""
    status, body, ctype = fetch(feature_url(args.layer, args.base, args.sort))
    r = {"http_status": status, "content_type": ctype, "bytes": len(body)}
    if status == 200:
        try:
            r.update(summarise_features(json.loads(body), now))
        except ValueError:
            r["error"] = "response was not JSON"
    else:
        r["error_start"] = body[:300].decode("utf-8", errors="replace")
    result = {
        "task": "CFM-DSS live probe, second request (single GetFeature)",
        "approved": "owner, 9 October 2026: two read-only requests in total; the first is in the earlier result",
        "run_at": now.strftime("%Y-%m-%dT%H:%M:%SZ"), "endpoint": args.base, "layer_read": args.layer,
        "sorted_newest_first_by": args.sort, "requests_made": 1, "request_2_feature": r,
    }
    out = ROOT / "data" / "results" / f"{now.strftime('%Y-%m-%d')}-cfm-live-probe-feature"
    out.mkdir(parents=True, exist_ok=True)
    (out / "result.json").write_text(json.dumps(result, indent=1, ensure_ascii=False), encoding="utf-8")
    print(json.dumps(result, indent=1, ensure_ascii=False))
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--base", help="endpoint to use for a single GetFeature request (skips request 1)")
    ap.add_argument("--layer", help="layer for the single GetFeature request, for example ChennaiDSS:awlr_transaction")
    ap.add_argument("--sort", help="property to sort newest-first by, for example time_of_measurement")
    args = ap.parse_args(argv)
    if bool(args.base) != bool(args.layer):
        ap.error("--base and --layer go together")
    if args.dry_run:
        print("request 1:", capabilities_url())
        print("request 2: GetFeature, count=5, one layer from", PREFERRED, "that request 1 lists:", feature_url("<layer>"))
        return 0
    now = datetime.now(timezone.utc)
    if args.base:
        return single_feature(args, now)
    result = {
        "task": "NEXT_STEPS data test: do the CFM-DSS public layers carry live, timestamped readings?",
        "approved": "owner, 9 October 2026: exactly two read-only requests",
        "run_at": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "endpoint": BASE,
        "requests_made": 0,
    }
    status, body, ctype = fetch(capabilities_url())
    result["requests_made"] += 1
    result["request_1_capabilities"] = {"http_status": status, "content_type": ctype, "bytes": len(body)}
    names: list[str] = []
    if status == 200:
        names = parse_layer_names(body.decode("utf-8", errors="replace"))
        result["request_1_capabilities"]["layers_listed"] = len(names)
        result["request_1_capabilities"]["layers_of_interest"] = sorted(n for n in names if INTEREST.search(n))
        result["request_1_capabilities"]["any_layer_named_for_subway_or_barrier_or_underpass"] = any(
            re.search(r"subway|barrier|underpass", n, re.IGNORECASE) for n in names
        )
    else:
        result["request_1_capabilities"]["error_start"] = body[:300].decode("utf-8", errors="replace")
    layer = choose_layer(names)
    result["layer_read"] = layer
    if layer:
        status2, body2, ctype2 = fetch(feature_url(layer))
        result["requests_made"] += 1
        r2 = {"http_status": status2, "content_type": ctype2, "bytes": len(body2)}
        if status2 == 200:
            try:
                r2.update(summarise_features(json.loads(body2), now))
            except ValueError:
                r2["error"] = "response was not JSON"
        else:
            r2["error_start"] = body2[:300].decode("utf-8", errors="replace")
        result["request_2_feature"] = r2
    else:
        result["request_2_feature"] = "not made: no preferred layer was listed (or request 1 failed); no other path was tried"
    out = ROOT / "data" / "results" / f"{now.strftime('%Y-%m-%d')}-cfm-live-probe"
    out.mkdir(parents=True, exist_ok=True)
    (out / "result.json").write_text(json.dumps(result, indent=1, ensure_ascii=False), encoding="utf-8")
    print(json.dumps(result, indent=1, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
