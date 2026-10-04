# Literature review, v2

- **File:** `CityPulse_literature_review_v2.pdf`
- **Length:** 14 pages, IEEE journal format, 323 cited works.

**Build** (TeX Live):

```
cd latex
pdflatex litreview && bibtex litreview && pdflatex litreview && pdflatex litreview
```

**Contents:**
- `references_verified.tsv`: every reference with DOI or arXiv ID, venue, volume, pages, the method used to verify it, and its theme. Only cite from this file, or add new entries after opening the primary record yourself.
- `references_verification_log_v1.md`: the verification log for the first 129 references. The 194 added in October 2026 were verified through Crossref or arXiv; their evidence is in `../06_research_notes/*.md`.
- **Excluded (could not be verified cleanly):**
  - two 2026 arXiv mobile-LLM benchmarks with inconsistent identifiers;
  - an SSRN preprint with no journal version;
  - one paper whose event attribution could not be reconciled.
