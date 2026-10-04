# CityPulse AI: final IDP folder

CityPulse AI is an offline-first, flood-aware navigation prototype for Chennai, built by Pragatish N, Ravi and Jyotish at VIT Chennai.

The folder holds four things:
- the working code;
- the October 2026 evaluation and review;
- the IEEE paper and literature review;
- a gated plan, and `PLAN.md`: the build plan for the Android app, the responsive web app, the server and the AI/ML layer.

**AI agents:** read `CLAUDE.md` first, then `PLAN.md`.
**People:** start with `00_START_HERE/PROJECT_STATUS.md`.

| Folder | Contents |
|---|---|
| `00_START_HERE/` | Status, known flaws (with file and line), next steps, key numbers |
| `01_code/citypulse-IDP/` | Main codebase: Dart router, belief and explanation packages; Flutter app; FastAPI server; Python harness; pinned data |
| `01_code/citypulse-ai-kotlin-prototype/` | AI-generated Android UI mock-up (reference only) |
| `02_paper/` | IEEE conference paper v2, PDF and LaTeX |
| `03_literature_review/` | Literature review v2 (PDF and LaTeX), 323 verified references, verification log |
| `04_critique_and_review/` | Classification, deep review (specialists, defences, adjudication), full report PDF |
| `05_council/` | Four-agent council (Believer, Skeptic, Investor, Judge) and the verdict log |
| `06_research_notes/` | Verified literature tables by theme; market and competitor brief |
| `07_reanalysis/` | Independent re-scoring of Study 1 under one reference belief |
| `08_archive_v1/` | Superseded first drafts, kept for history |
| `09_skills/` | Writing and council skills used to produce the documents |

**Headline result.** On the 2015 Chennai flood replay, routing changes came from the static GCC hazard map; crowd reports added nothing measurable. The next step is time-stamped street-level passability data. Choosing a different model would not address that.

**Not included:** the 557 MB raw OSM extract and the git history. Both remain in the original `Downloads/citypulse-IDP/citypulse-IDP/` folder.
