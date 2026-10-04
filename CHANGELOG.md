# Changelog

All notable changes. The project is a research prototype with no tagged releases yet; entries are by date and
by decision record. Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added
- Combined Chennai + Tamil Nadu serving: routes with both ends in Chennai use the detailed pack, flood layer
  and advisor; all other routes use the Tamil Nadu main-road pack (ADR-022).
- On-device route advisor: risk level, proceed / wait / avoid verdict, evidence level, route-choice check
  (ADR-021).
- Tamil Nadu main-road region pack (257,249 edges, 9 MB) and a 25,144-place gazetteer; highway-number search
  (ADR-020).
- Viewport-limited hazard overlay, thinned long routes, per-region snap radius and opening zoom.
- Travel modes: car, bicycle, on foot, emergency vehicle (ADR-019).
- City-agnostic pack pipeline (ADR-018) and an "Adding a city" guide.
- Project documentation for GitHub: README, contribution guide, security policy, CI, issue templates.

- Merged India flood event dataset: India Flood Inventory v4 plus Dartmouth Flood Observatory events, linked for Tamil Nadu, research-only licences (ADR-023).

- Training-data assessment and downloads: Chennai Flood Monitor archive (local only) and NYC FloodNet sandbox, with fetch and profile scripts (ADR-024).

- Nationwide district flood-event model, trained under a pre-registered rule; it did not beat two simple baselines (ADR-025).

- Terrain and past floods as training data: 91 India flood maps and elevation tiles, a nationwide terrain model, Chennai studies and three routing tests, all pre-registered; the nationwide model met its rule, the Chennai and routing rules were not met (ADR-026).
- Tested terrain-hydrology code (`scripts/hydrology.py`).

### Fixed
- Place search finds neighbourhoods and suburbs (a dated OSM gazetteer for Chennai), and a name typed exactly now ranks first (F-31).
- Web: the report sheet closes after sending; sheets no longer pass clicks through to the map (F-32).
- Report sheet names the spot as the centre of the map and says how to pick another (F-33).
- Route card says when no flood hazard was found, beside the thin-evidence reason (F-34).

### Changed
- Pessimistic index is now a Beta-posterior upper quantile; it no longer lowers caution after a weak report
  (ADR-015).
- Explanations are template-based with a stronger symbolic gate (ADR-016).
- Studies 1 and 2 re-run and re-scored under one reference belief (ADR-017).
- Routes in regions without a flood layer no longer show a flood banner, hazard badge or hazard explanation.
- Two Python tests that need the large Chennai graph now skip when it is absent, instead of failing.

### Known problems
See [`00_START_HERE/KNOWN_FLAWS.md`](00_START_HERE/KNOWN_FLAWS.md). Notably: nothing has run on a phone;
crowd reports add nothing measurable on the 2015 replay; the Tamil text is unreviewed; pack format v1 cannot
hold a whole state's streets (F-26).

## 2026-10-02 and 2026-10-03

Independent review and correction pass (see `04_critique_and_review/` and `07_reanalysis/`).

## 2026-09

Initial build: router, belief engine, explanation template and verifier, Flutter shell, ingest server,
replay harness and the first evaluation.
