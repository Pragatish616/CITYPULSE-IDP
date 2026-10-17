# CityPulse as an MCP server (C6)

CityPulse can be used from any assistant that speaks the [Model Context Protocol](https://modelcontextprotocol.io) (MCP): Claude Desktop,
Claude Code, and other MCP clients. The assistant gets four tools; **every sentence the tools return comes from CityPulse's own rule-based
answerer and has passed the symbolic verifier**, so the assistant is given checked facts to quote, not a map to interpret. A question about
whether a road is safe, dry, open or passable gets the same refusal as in the app (ADR-011).

| Tool | What it does |
|---|---|
| `search_places` | Find places and streets by name (English or Tamil) |
| `plan_route` | Flood-aware route between two places or points for car, bicycle, walking or emergency; returns a verified briefing (distance, free-flow time, main streets, flood-risk rating and how much evidence it rests on) and structured data |
| `ask_about_route` | Plan a route and answer a question about it ("why this route?", "what was avoided?", "how sure is the data?") |
| `flood_event_state` | Whether the flood-hazard map is applied to routes now (dry, watch, active) and why |

The server is `services/router_api/bin/mcp_stdio.dart`. It builds the same router as the HTTP service (`lib/src/bootstrap.dart`) and calls
the HTTP API's own handler in-process, so a tool can do nothing the API would refuse. Transport: JSON-RPC 2.0, one message per line on
stdin/stdout; logs go to stderr. Protocol versions: 2025-06-18, 2025-03-26, 2024-11-05.

## Run it

```bash
cd 01_code/citypulse-IDP/services/router_api
dart pub get
dart compile exe bin/mcp_stdio.dart -o citypulse_mcp.exe
```

The executable needs the map pack and configuration. When an MCP client starts it from another folder, give absolute paths:

| Variable | Value |
|---|---|
| `CITY` | `chennai` |
| `CITIES_CONFIG` | absolute path to `01_code/citypulse-IDP/config/cities.yaml` |
| `HAZARD_CONFIG` | absolute path to `01_code/citypulse-IDP/config/hazard_classes.yaml` |
| `EVENT_STATE` | `dry`, `watch` or `active` (default `active`) |
| `OBSERVATIONS_URL` | optional: the report server, for live reports and satellite rain (as for the HTTP service) |

### Claude Desktop

Add to `claude_desktop_config.json` (Settings → Developer → Edit config), with your own paths:

```json
{
  "mcpServers": {
    "citypulse": {
      "command": "C:\\path\\to\\citypulse-IDP\\services\\router_api\\citypulse_mcp.exe",
      "env": {
        "CITY": "chennai",
        "CITIES_CONFIG": "C:\\path\\to\\citypulse-IDP\\config\\cities.yaml",
        "HAZARD_CONFIG": "C:\\path\\to\\citypulse-IDP\\config\\hazard_classes.yaml",
        "EVENT_STATE": "dry"
      }
    }
  }
}
```

### Claude Code

```bash
claude mcp add citypulse -e CITY=chennai -e CITIES_CONFIG=/abs/path/config/cities.yaml -e HAZARD_CONFIG=/abs/path/config/hazard_classes.yaml -- /abs/path/services/router_api/citypulse_mcp.exe
```

### Try it by hand

```bash
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"plan_route","arguments":{"from":"T. Nagar","to":"Velachery"}}}' \
  | CITY=chennai dart run bin/mcp_stdio.dart
```

## What the tools promise and what they do not

- Every answer sentence passed the verifier (`structuredContent.answer_verified`), or the fixed fallback was returned (`used_fallback`, with
  the verifier's `rejected_claims` for debugging).
- Every route result ends with the guide: CityPulse is a research prototype, estimates flood risk from limited data, and never states that
  a road is safe or passable.
- The assistant is told (in the server's `instructions`) to quote the tool text as given. An assistant can still paraphrase; the guarantee
  covers what the tool returns, not what a model later writes.
- Times are free-flow estimates; there is no live traffic data.
