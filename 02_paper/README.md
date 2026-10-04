# IEEE conference paper, v2

- **File:** `CityPulse_paper_v2.pdf`
- **Title:** *Does Crowd Evidence Help Flood-Aware Routing? An Offline Routing Prototype and a Replay Study on the Chennai Road Network*
- **Length:** 8 pages, 90 references.

**Build** (TeX Live with `pdflatex` and `bibtex`):

```
cd latex
pdflatex paper && bibtex paper && pdflatex paper && pdflatex paper
python3 check_citations.py paper.tex
```

`check_citations.py` checks citation order, missing keys and "et al." usage.

**Open items:**
- Author surnames, departments and e-mails are still placeholders.
- The acknowledgment section is empty.
- Every number must be updated after the fixes in `../00_START_HERE/KNOWN_FLAWS.md`, especially F-01 and F-02.

**Where the numbers come from:**
- `latex/numbers.tex` holds macros taken from `../07_reanalysis/` and `../01_code/citypulse-IDP/data/results/`.
- Hybrid baseline, observed/prior-only split and holdout values come from `../04_critique_and_review/deep_review/2_findings_and_defences/D3_evaluation_defense.md`.
