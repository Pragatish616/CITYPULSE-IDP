"""/fieldlog: volunteers record what they see at a site, with the time (ADR-028).

Research ground truth, kept apart from the routing belief on purpose: nothing logged here is shown to a traveller, and nothing here changes a
route. Deciding to let it do so (and at what trust) is a separate decision for the owner.
"""

from __future__ import annotations

import csv
import io
from datetime import datetime
from pathlib import Path
from typing import Annotated, Any

from fastapi import APIRouter, HTTPException, Query, Request, status
from fastapi.responses import (
    FileResponse,
    JSONResponse,
    PlainTextResponse,
    RedirectResponse,
    Response,
)
from pydantic import ValidationError

from app.fieldlog.models import FieldLogEntry, StoredEntry
from app.fieldlog.service import FieldLogService
from app.fieldlog.store import CSV_HEADER, Conflict, to_csv_row

router = APIRouter(prefix="/fieldlog", tags=["fieldlog"])

STATIC = Path(__file__).resolve().parents[1] / "static" / "fieldlog"
ASSETS = {
    "app.js": "text/javascript",
    "core.js": "text/javascript",
    "i18n.js": "text/javascript",
    "style.css": "text/css",
}
MAX_BODY = 2048
CSP = (
    "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; "
    "base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
)
PAGE_HEADERS = {
    "Content-Security-Policy": CSP,
    "Permissions-Policy": "geolocation=(self), camera=(), microphone=()",
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "no-referrer",
    "Cache-Control": "no-cache",
}


def service(request: Request) -> FieldLogService:
    return request.app.state.fieldlog


def _client_key(request: Request) -> str:
    return request.client.host if request.client else "unknown"


def _problems(exc: ValidationError) -> list[dict[str, str]]:
    # Field names and messages only: never echo the submitted values back.
    out = []
    for err in exc.errors():
        loc = ".".join(str(p) for p in err["loc"]) or "body"
        out.append({"field": loc, "message": err["msg"].removeprefix("Value error, ")})
    return out


def _volunteer(request: Request, svc: FieldLogService) -> str:
    """The volunteer behind a valid token. A valid token is NEVER refused because of earlier wrong guesses: behind a host's proxy many
    people can share one address, and a lockout that also blocked valid tokens would let anyone lock every volunteer out. Only further
    WRONG tokens are slowed (429 instead of 401) once an address has made too many."""
    volunteer = svc.tokens.identify(request.headers.get("x-fieldlog-token"))
    if volunteer is not None:
        return volunteer
    ip = _client_key(request)
    if svc.bad_auth.over(ip):
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS,
            "Too many wrong tokens from this address. Try again later.",
        )
    svc.bad_auth.hit(ip)
    raise HTTPException(
        status.HTTP_401_UNAUTHORIZED, "Missing or wrong x-fieldlog-token."
    )


# ---- the page --------------------------------------------------------------------------------------------------------------------------


@router.get("", include_in_schema=False)
async def page_redirect() -> RedirectResponse:
    # Relative on purpose: behind a path prefix (/ingest/fieldlog) an absolute "/fieldlog/" would drop the prefix.
    return RedirectResponse("fieldlog/", status_code=status.HTTP_308_PERMANENT_REDIRECT)


@router.get("/", include_in_schema=False)
async def page() -> FileResponse:
    return FileResponse(
        STATIC / "index.html",
        media_type="text/html; charset=utf-8",
        headers=PAGE_HEADERS,
    )


@router.get("/assets/{name}", include_in_schema=False)
async def asset(name: str) -> FileResponse:
    media = ASSETS.get(name)
    if media is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND)
    return FileResponse(
        STATIC / name,
        media_type=media,
        headers={**PAGE_HEADERS, "Cache-Control": "no-cache"},
    )


@router.get("/sw.js", include_in_schema=False)
async def service_worker() -> FileResponse:
    # Served from /fieldlog/ so its scope is the page's own folder, wherever a proxy mounts it.
    return FileResponse(
        STATIC / "sw.js",
        media_type="text/javascript",
        headers={**PAGE_HEADERS, "Cache-Control": "no-cache"},
    )


# ---- public reads ----------------------------------------------------------------------------------------------------------------------


@router.get("/sites")
async def sites(request: Request) -> JSONResponse:
    return JSONResponse(
        service(request).sites_doc, headers={"Cache-Control": "public, max-age=3600"}
    )


@router.get("/health")
async def health(request: Request) -> dict[str, Any]:
    return service(request).health()


@router.get("/whoami")
async def whoami(request: Request) -> dict[str, str]:
    """Lets the page tell a volunteer at once whether their token works. Counts toward the wrong-token lockout like any other try."""
    svc = service(request)
    if not svc.enabled:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            "Field logging is not switched on for this server.",
        )
    return {"volunteer": _volunteer(request, svc)}


# ---- volunteers write ------------------------------------------------------------------------------------------------------------------


@router.post("/entries")
async def add_entry(request: Request) -> JSONResponse:
    svc = service(request)
    if not svc.enabled:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            "Field logging is not switched on for this server.",
        )
    volunteer = _volunteer(request, svc)
    if not (
        svc.by_volunteer_hour.allow(volunteer) and svc.by_volunteer_day.allow(volunteer)
    ):
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS,
            "Too many entries from this volunteer. Slow down and try again later.",
        )

    declared = request.headers.get("content-length")
    if declared and declared.isdigit() and int(declared) > MAX_BODY:
        raise HTTPException(413, "Entry too large.")
    body = await request.body()
    if len(body) > MAX_BODY:
        raise HTTPException(413, "Entry too large.")

    try:
        entry = FieldLogEntry.model_validate_json(body)
    except ValidationError as exc:
        return JSONResponse(
            {"status": "rejected", "problems": _problems(exc)}, status_code=422
        )
    now = svc.now()
    problems: list[dict[str, str]] = []
    try:
        entry.check_time(now)
    except ValueError as exc:
        problems.append({"field": "observed_at", "message": str(exc)})
    if not svc.known_site(entry.site_id):
        problems.append({"field": "site_id", "message": "unknown site"})
    if problems:
        return JSONResponse(
            {"status": "rejected", "problems": problems}, status_code=422
        )

    stored = StoredEntry.from_entry(entry, volunteer, now)
    try:
        new = svc.store.add(stored)
    except Conflict:
        return JSONResponse(
            {
                "status": "conflict",
                "message": "This entry_id was already stored with different content.",
            },
            status_code=status.HTTP_409_CONFLICT,
        )
    except OSError:
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            "The server could not write the log. Keep the entry and try again.",
        ) from None
    return JSONResponse(
        {
            "status": "stored" if new else "duplicate",
            "entry_id": str(entry.entry_id),
            "received_at": stored.received_at.isoformat(),
        },
        status_code=status.HTTP_201_CREATED if new else status.HTTP_200_OK,
    )


# ---- operator reads --------------------------------------------------------------------------------------------------------------------


def _admin(request: Request) -> FieldLogService:
    svc = service(request)
    if svc.admin_token is None:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            "Reading the log is not switched on for this server.",
        )
    if svc.admin_ok(request.headers.get("x-admin-token")):
        return svc
    ip = _client_key(request)
    if svc.bad_auth.over(ip):
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS,
            "Too many wrong tokens from this address. Try again later.",
        )
    svc.bad_auth.hit(ip)
    raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Missing or wrong x-admin-token.")


@router.get("/entries")
async def list_entries(
    request: Request,
    since: Annotated[datetime | None, Query()] = None,
    limit: Annotated[int, Query(ge=1, le=5000)] = 500,
) -> dict:
    svc = _admin(request)
    rows = []
    for e in svc.store.iter_entries(since):
        rows.append(e.model_dump(mode="json"))
        if len(rows) >= limit:
            break
    return {"count": len(rows), "entries": rows}


@router.get("/export.csv")
async def export_csv(request: Request) -> Response:
    svc = _admin(request)
    buf = io.StringIO()
    writer = csv.writer(buf, lineterminator="\n")
    writer.writerow(CSV_HEADER)
    for e in svc.store.iter_entries():
        writer.writerow(to_csv_row(e))
    return PlainTextResponse(
        buf.getvalue(),
        media_type="text/csv; charset=utf-8",
        headers={
            "Content-Disposition": 'attachment; filename="fieldlog-export.csv"',
            "Cache-Control": "no-store",
        },
    )


@router.get("/summary")
async def summary(request: Request) -> dict:
    svc = _admin(request)
    by_state: dict[str, int] = {}
    by_site: dict[str, int] = {}
    for e in svc.store.iter_entries():
        by_state[e.state.value] = by_state.get(e.state.value, 0) + 1
        by_site[e.site_id] = by_site.get(e.site_id, 0) + 1
    return {
        "entries": len(svc.store),
        "by_state": by_state,
        "sites_with_entries": len(by_site),
        "by_volunteer": svc.store.counts_by_volunteer(),
    }
