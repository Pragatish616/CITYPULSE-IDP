"""Smoke test for a running CityPulse deployment: the same checks for a local stack or a live URL.

    python scripts/smoke_deploy.py https://your-site.example            # read-only checks
    python scripts/smoke_deploy.py http://127.0.0.1:8088 --write        # also posts ONE test report

The site must be the single-origin layout (docs/DEPLOY.md): `/` web app, `/api/*` router, `/ingest/*` reports.
Without --write nothing on the target is changed. With --write one report is stored on the target (a test
point, marked by its install code `smoke-test`); on in-memory storage it disappears at the next restart, but with a
database it is a real row, so do not use --write against a live site you care about.

Standard library only. Exit code 0 when every check passes, 1 otherwise. Needs no secrets and no network except to
the target.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
import uuid
import urllib.error
import urllib.request
from datetime import datetime, timezone

# A trip with a known good answer on the Chennai pack: Adyar to Velachery, about 6.5 km by car.
ADYAR = {"lat": 13.0012, "lon": 80.2565}
VELACHERY = {"lat": 12.9791, "lon": 80.2209}
MAX_ROUTE_SECONDS = 5.0


def call(base: str, path: str, *, method: str = "GET", body: dict | None = None, timeout: float = 30.0):
    """Returns (status, headers, parsed-or-raw body, seconds). Never raises on an HTTP error status."""
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(base + path, data=data, method=method, headers={"content-type": "application/json"} if data else {})
    t0 = time.perf_counter()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw, status, headers = r.read(), r.status, r.headers
    except urllib.error.HTTPError as e:
        raw, status, headers = e.read(), e.code, e.headers
    took = time.perf_counter() - t0
    try:
        parsed = json.loads(raw)
    except ValueError:
        parsed = raw
    return status, headers, parsed, took


class Report:
    def __init__(self) -> None:
        self.failed = 0

    def check(self, name: str, ok: bool, detail: str = "") -> None:
        print(f"[{'ok' if ok else 'FAIL'}] {name}" + (f" -- {detail}" if detail else ""))
        if not ok:
            self.failed += 1


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("base_url", help="for example https://your-site.example (no trailing path)")
    ap.add_argument("--write", action="store_true", help="also post one test report to /ingest/observations")
    ap.add_argument("--timeout", type=float, default=60.0, help="seconds for the first request (a sleeping free host can take a minute)")
    args = ap.parse_args(argv)
    base = args.base_url.rstrip("/")
    rep = Report()

    # 1. the web app. The first request also wakes a host that sleeps when idle, hence the longer timeout.
    try:
        status, headers, body, took = call(base, "/", timeout=args.timeout)
    except OSError as e:
        print(f"[FAIL] cannot reach {base}: {e}")
        return 1
    html = body.decode("utf-8", "replace") if isinstance(body, bytes) else str(body)
    rep.check("web app: GET / is 200 and is the Flutter page", status == 200 and "flutter" in html.lower(), f"{status}, {took:.1f}s")
    rep.check("web app: sent with nosniff and no-referrer headers", headers.get("X-Content-Type-Options") == "nosniff" and headers.get("Referrer-Policy") == "no-referrer")

    # 2. the router
    status, _, health, _ = call(base, "/api/health")
    rep.check("router: /api/health is ok and serves Chennai", status == 200 and isinstance(health, dict) and health.get("status") == "ok" and health.get("city") == "chennai",
              f"{status} {health if not isinstance(health, dict) else {k: health.get(k) for k in ('status', 'city', 'nodes', 'edges', 'event_state')}}")
    status, _, places, _ = call(base, "/api/places?q=Adyar&limit=5")
    first = places["results"][0] if status == 200 and isinstance(places, dict) and places.get("results") else {}
    rep.check("router: searching 'Adyar' puts the area before its streets", first.get("name") == "Adyar" and first.get("kind") == "suburb", f"first = {first.get('name')} ({first.get('kind')})")

    for user_class in ("commuter", "pedestrian"):
        status, _, route, took = call(base, "/api/route", method="POST", body={"from": ADYAR, "to": VELACHERY, "user_class": user_class})
        ok = status == 200 and isinstance(route, dict) and len(route.get("path", [])) > 10 and route.get("trace", {}).get("chosen", {}).get("distance_m", 0) > 3000
        rep.check(f"router: a {user_class} route Adyar to Velachery", ok and took < MAX_ROUTE_SECONDS, f"{status}, {took:.2f}s")
    status, _, bad, _ = call(base, "/api/route", method="POST", body={"from": {"lat": 28.61, "lon": 77.2}, "to": {"lat": 28.7, "lon": 77.1}})
    rep.check("router: a start point outside Chennai is refused politely", status == 422 and isinstance(bad, dict) and bad.get("reason") == "origin_outside_coverage", str(status))
    status, _, risk, _ = call(base, "/api/risk?user_class=commuter&bbox=80.04,12.86,80.44,13.22&limit=500")
    rep.check("router: /api/risk returns map features", status == 200 and isinstance(risk, dict) and risk.get("type") == "FeatureCollection", str(status))

    # 3. what must NOT be open
    status, *_ = call(base, "/api/event-state", method="PUT", body={"state": "dry"})
    rep.check("security: changing the event state without the admin token is refused", status in (401, 403), str(status))
    status, _, ev, _ = call(base, "/api/event-state")
    rep.check("router: /api/event-state is readable", status == 200 and isinstance(ev, dict) and ev.get("event_state") in ("dry", "watch", "active"), str(ev))

    # 4. the report server
    status, _, ing, _ = call(base, "/ingest/health")
    rep.check("reports: /ingest/health is ok", status == 200 and isinstance(ing, dict) and ing.get("status") == "ok", str(status))
    if args.write:
        now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        obs = {
            "id": str(uuid.uuid4()), "hazard_class": "flood", "polarity": 1, "geometry": {"type": "Point", "coordinates": [80.2341, 13.0418]},
            "accuracy_m": 25.0, "observed_at": now, "source_class": "crowd", "source_id": "install:smoke-test", "raw": {},
        }
        status, _, posted, _ = call(base, "/ingest/observations", method="POST", body=obs)
        rep.check("reports: one test report is accepted", status in (200, 201), f"{status} {posted if status >= 300 else ''}")
    else:
        print("[skip] reports: posting a test report (use --write)")

    print(f"\n{'ALL CHECKS PASSED' if rep.failed == 0 else str(rep.failed) + ' CHECK(S) FAILED'} against {base}")
    return 0 if rep.failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
