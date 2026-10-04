"""Storage backend selection.

Selection logic (per task brief — documented here, the one place it happens):
`SUPABASE_URL` set and non-empty -> `PostGISObservationRepository`; otherwise ->
`InMemoryObservationRepository`. This is checked once, at app startup
(`app.main.create_app`), and the chosen repository is stored on `app.state.repository`.

Judgement call: Supabase's dashboard gives you `SUPABASE_URL` (a REST endpoint,
`https://<ref>.supabase.co`) and `SUPABASE_SERVICE_KEY` — neither is a Postgres DSN.
`.env.example` (as of this task) does not list a raw connection string. Rather than
guessing at Supabase's pooler hostname convention (which varies by project/region and would
silently break), this module:
  1. prefers an explicit `SUPABASE_DB_URL` or `DATABASE_URL` env var if set (the real
     Postgres connection string, copied from Supabase's project settings -> Database page);
  2. otherwise derives a best-effort DSN from `SUPABASE_URL` + `SUPABASE_SERVICE_KEY` using
     Supabase's documented direct-connection hostname pattern, which will need to be
     confirmed once a real project exists (see server/README.md).
"""

from __future__ import annotations

import os
from urllib.parse import quote, urlparse

from app.storage.base import ObservationRepository
from app.storage.memory import InMemoryObservationRepository


def _derive_dsn_from_supabase_url(supabase_url: str, service_key: str) -> str:
    host = urlparse(supabase_url).hostname or ""
    ref = host.split(".")[0] if host else ""
    if not ref:
        raise ValueError(
            f"could not parse a project ref out of SUPABASE_URL={supabase_url!r}"
        )
    db_host = f"db.{ref}.supabase.co"
    password = quote(service_key, safe="")
    return f"postgresql://postgres:{password}@{db_host}:5432/postgres"


def get_repository() -> ObservationRepository:
    supabase_url = os.environ.get("SUPABASE_URL", "").strip()
    if not supabase_url:
        return InMemoryObservationRepository()

    # Import lazily so `psycopg_pool` is only required when this path is actually taken.
    from app.storage.postgis import PostGISObservationRepository

    dsn = (
        os.environ.get("SUPABASE_DB_URL", "").strip()
        or os.environ.get("DATABASE_URL", "").strip()
    )
    if not dsn:
        service_key = os.environ.get("SUPABASE_SERVICE_KEY", "")
        dsn = _derive_dsn_from_supabase_url(supabase_url, service_key)

    return PostGISObservationRepository(dsn=dsn)
