# docs

Engineering documents for the codebase. The project-level index is `../../../docs/README.md`; the rules are in `../../../CLAUDE.md`.

## Core (this folder)
| Document | For |
|---|---|
| `DECISIONS.md` | Every architecture decision record (ADR-001 onward), with evidence and limits |
| `CONTRACTS.md` | Shared schemas: observation, belief, decision trace, verification result |
| `ARCHITECTURE.md` | Component-level design |
| `EVALUATION.md` | The studies and how they are scored |
| `IMPLEMENTATION_PLAN.md` | The original task-by-task plan (the live plan is the top-level `PLAN.md`) |
| `CHENNAI_PROTOTYPE_SPEC.md`, `ADDING_A_CITY.md`, `GLOSSARY.md`, `REVIEW_CHECKLIST.md` | Scope, new cities, vocabulary, review |
| `APIS_AND_COSTS.md`, `DEPLOY.md`, `data-access-log.md` | External services and limits; running the service; what was fetched and when |

## `field/` (the pilot, the field log, event miner, accidents)
`FIELD_PROTOCOL.md`, `PILOT_PLAN.md`, `ACCIDENT_DATA.md`, `EVENT_MINER.md`, `pilot/` (offer draft), `ethics/`.

## `ops/` (testing and licences)
`MOBILE_TESTING.md`, `LICENCE_AUDIT.md`, `licence_scan_2026-10-03.json`.

## `archive/` (history only; do not treat as current)
`PROJECT_BRIEF.md`, `IMPROVEMENTS.md`, `ROADMAP.md`, `BASELINE_2026-10.md`, `COUNCIL_VERDICT.md`.

## Moved on 13 October 2026
Old path to new path. References were updated everywhere except in the frozen pre-registration files and result files, which still show the old paths (`docs/ACCIDENT_DATA.md` and similar in `PREREGISTRATION_SCORECARD.md` and `PREREGISTRATION_ROUTER_2.md`).

| Was | Now |
|---|---|
| `docs/FIELD_PROTOCOL.md`, `PILOT_PLAN.md`, `ACCIDENT_DATA.md`, `EVENT_MINER.md`, `pilot/`, `ethics/` | `docs/field/...` |
| `docs/MOBILE_TESTING.md`, `LICENCE_AUDIT.md`, `licence_scan_2026-10-03.json` | `docs/ops/...` |
| `docs/PROJECT_BRIEF.md`, `IMPROVEMENTS.md`, `ROADMAP.md`, `BASELINE_2026-10.md`, `COUNCIL_VERDICT.md` | `docs/archive/...` |
| `CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md` (repository root) | `.github/...` (GitHub still finds them there) |
