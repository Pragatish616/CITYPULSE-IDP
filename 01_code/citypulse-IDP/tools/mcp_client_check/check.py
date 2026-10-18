"""Check the CityPulse MCP server (C6) with an independent client: the official MCP Python SDK's stdio client.

    python tools/mcp_client_check/check.py <path to citypulse_mcp executable> [result.json]

Run from 01_code/citypulse-IDP (config paths are made absolute from there). The SDK performs the MCP handshake and validates every
message against its own schema, so this exercises the server the way a real assistant host does, without any account or model.
"""

from __future__ import annotations

import asyncio
import json
import sys
import time
from pathlib import Path

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

ROOT = Path.cwd()


async def main(exe: str, out: str | None) -> int:
    params = StdioServerParameters(
        command=exe,
        args=[],
        env={
            "CITY": "chennai",
            "CITIES_CONFIG": str(ROOT / "config" / "cities.yaml"),
            "HAZARD_CONFIG": str(ROOT / "config" / "hazard_classes.yaml"),
            "EVENT_STATE": "dry",
        },
    )
    report: dict = {"client": "mcp python sdk", "checks": {}}
    ok = True
    t0 = time.perf_counter()
    async with stdio_client(params) as (read, write), ClientSession(read, write) as session:
        init = await session.initialize()
        report["server"] = {"name": init.serverInfo.name, "version": init.serverInfo.version, "protocol": init.protocolVersion}
        report["startup_s"] = round(time.perf_counter() - t0, 2)
        tools = await session.list_tools()
        names = [t.name for t in tools.tools]
        report["checks"]["four tools listed"] = names == ["search_places", "plan_route", "ask_about_route", "flood_event_state"]

        async def call(name: str, args: dict) -> tuple[str, dict | None, bool]:
            a = time.perf_counter()
            r = await session.call_tool(name, args)
            report.setdefault("call_ms", {})[name] = round(1000 * (time.perf_counter() - a))
            text = "\n".join(c.text for c in r.content if getattr(c, "type", "") == "text")
            return text, r.structuredContent, bool(r.isError)

        text, sc, err = await call("plan_route", {"from": "T. Nagar", "to": "Velachery", "travel_mode": "car"})
        report["plan_route_text"] = text
        report["plan_route_structured"] = sc
        report["checks"]["plan_route verified"] = (not err) and bool(sc and sc.get("answer_verified"))
        text, sc, err = await call(
            "ask_about_route", {"from": "T. Nagar", "to": "Velachery", "question": "Is it safe to drive there now?"}
        )
        report["safety_text"] = text
        report["checks"]["safety question refused"] = "cannot confirm the condition of any road" in text
        text, sc, err = await call("plan_route", {"from": "Zzqxv Nowhere", "to": "Velachery"})
        report["checks"]["bad place is a tool error"] = err
        text, sc, err = await call("search_places", {"query": "Adyar", "limit": 3})
        report["checks"]["search works"] = (not err) and "Adyar" in text
        text, sc, err = await call("flood_event_state", {})
        report["event_state_text"] = text
        report["checks"]["event state works"] = (not err) and bool(sc) and sc.get("event_state") == "dry" and "hazard map" in text
    ok = all(report["checks"].values())
    report["all_passed"] = ok
    print(json.dumps(report, indent=1, ensure_ascii=False))
    if out:
        Path(out).write_text(json.dumps(report, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(asyncio.run(main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)))
