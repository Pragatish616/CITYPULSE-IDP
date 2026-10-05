"""FastAPI app entrypoint. Run with: uvicorn app.main:app --reload (from server/)."""

from __future__ import annotations

import os

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.events import ObservationBroadcaster
from app.fieldlog.service import FieldLogService
from app.ingest.imerg import RainContextService
from app.routers import context, events, fieldlog, health, observations
from app.storage.factory import get_repository


def create_app() -> FastAPI:
    app = FastAPI(
        title="CityPulse AI — Ingest Server",
        description=(
            "Hazard observation ingest, query, and SSE push. See server/README.md for the "
            "env vars that gate the PostGIS backend and the two zero-key ingest workers."
        ),
    )
    app.state.repository = get_repository()
    app.state.broadcaster = ObservationBroadcaster()
    # Rain context is fetched on demand and cached; nothing runs in the background (free hosts sleep).
    app.state.rain_service = RainContextService()
    # Volunteer field log (ADR-028): off until FIELDLOG_TOKENS is set; separate from the observations the router reads.
    app.state.fieldlog = FieldLogService.from_env()

    # Browsers cannot post reports from another origin without CORS. Off unless the operator
    # names the origins (comma-separated); never "*" by default (PLAN.md M2.5, strict CORS).
    origins = [
        o.strip()
        for o in os.environ.get("CORS_ALLOWED_ORIGINS", "").split(",")
        if o.strip()
    ]
    if origins:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=origins,
            allow_methods=["GET", "POST", "OPTIONS"],
            allow_headers=["content-type"],
            max_age=600,
        )

    app.include_router(health.router)
    app.include_router(observations.router)
    app.include_router(events.router)
    app.include_router(context.router)
    app.include_router(fieldlog.router)
    return app


app = create_app()
