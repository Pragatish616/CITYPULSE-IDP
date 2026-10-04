#!/bin/bash
# Starts the three processes of the one-container image and stops the container if any of them dies, so the
# host's restart policy brings everything back together instead of leaving a half-working site.
#
#   report server (FastAPI)  127.0.0.1:8000   in-memory storage: reports vanish on restart (see docs/DEPLOY.md)
#   router API (Dart)        127.0.0.1:8081
#   Caddy                    0.0.0.0:$PORT    the only port the host sees
set -euo pipefail

export PORT="${PORT:-8080}"
if [ -z "${ADMIN_TOKEN:-}" ]; then
  echo "note: ADMIN_TOKEN is not set, so PUT /api/event-state is disabled (the event state stays '${EVENT_STATE:-active}')." >&2
fi

pids=()
stop_all() {
  trap - EXIT TERM INT
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done
  wait 2>/dev/null || true
}
trap stop_all EXIT TERM INT

(cd /srv/server && exec python -m uvicorn app.main:app --host 127.0.0.1 --port 8000 --proxy-headers) &
pids+=($!)

# The router reads PORT as its own port, so give it its own value without touching Caddy's.
(cd /app && PORT=8081 exec /app/router_api) &
pids+=($!)

caddy run --config /etc/caddy/Caddyfile --adapter caddyfile &
pids+=($!)

# Wait for the first process to exit, then stop the rest and leave with a failure code.
wait -n || true
echo "a process exited; stopping the container so the host restarts it" >&2
exit 1
