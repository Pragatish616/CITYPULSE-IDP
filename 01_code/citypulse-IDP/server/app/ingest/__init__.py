"""Ingest workers, one module per feed.

Each real (non-stub) worker exposes an async `run_ingest_cycle(repository, broadcaster, ...)`
that a scheduler would call periodically — no scheduler is built here (T5.3 scope is the
workers themselves); see each module's docstring for where that wiring would go.
"""
