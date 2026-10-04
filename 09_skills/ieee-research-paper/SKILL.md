---
name: "ieee-research-paper"
description: "Draft, extend, convert or audit research papers, literature reviews, surveys and related-work sections to IEEE standard: verified sources only, IEEE numeric citations, IEEEtran PDF/Word output, originality check. Use for any research paper, lit review, IEEE references/bibliography, or plagiarism check, even if IEEE is not named."
---

# IEEE research papers and literature reviews

This skill produces papers that a program committee or examiner can trust: every factual claim about other
work is traceable to a source that was actually opened, every reference is complete and in IEEE format, and
every number the paper reports comes from the user's data. Polish matters, but credibility matters more:
one invented reference or fabricated result can sink a paper and its authors' reputation, which is why the
verification steps below are not optional extras.

Also use this skill for student reports and project papers that need proper academic citations, for
converting a paper to IEEE/IEEEtran format, and for adding or checking citations.

## Non-negotiable rules (and why)

1. **Never invent a source, author, title, venue, year, page range, DOI or quote.** Add a reference only after
   opening its primary record in this session (see Appendix D). A plausible-looking but fake citation is
   academic misconduct, and reviewers check.
2. **Never fabricate or estimate results.** Numbers in a paper come from the user's data, files or explicit
   statements. If the user asks for "assumed" or "example" results written as real, decline and offer the
   honest alternative: report what was measured and state the rest as scope limits or future work. For
   literature numbers, quote only values you read in the source, and cite them.
3. **Describe others' work only as far as you have read it.** If you read only an abstract, make only
   abstract-level claims. Drop details you cannot trace to the text you opened.
4. **Credit precisely.** If a definition, metric, method or dataset comes from prior work, say so and cite it
   where it is used. Keep the paper's own contribution claims narrow and honest.
5. **Never invent author details.** Affiliations, e-mails and ORCID IDs come from the user. Until they are
   provided, use visible placeholders (`<Department>`, `<Institution>`, `<E-mail>`) and list them as open items.
6. **Ask before large downloads, installs or sending the paper to any external service** (online plagiarism
   checkers may store uploads, which can count as prior publication).

## Workflow

Follow the phases in order. Skip a phase only when it clearly does not apply (for example, no build phase
when the user wants text only).

### 1. Scope

Establish what is being produced and for whom. Ask briefly only for what you cannot infer:
- Document type: full research paper, literature review / survey, related-work section only, extension or
  conversion of an existing draft, or a citation/format/plagiarism audit.
- Venue and format: IEEE conference (two-column, typically 6-10 pages incl. references) or IEEE journal;
  a university report that still wants IEEE citations; page or word limits.
- Inputs: the user's data, results files, notes, existing draft, a reference paper to match in style, the
  list of sources they already have.
- Authors and affiliations (rule 5), title (propose one if absent and mark it as a working title).
- Output: LaTeX + PDF, Word (.docx), Markdown, or text in chat.

If the user supplies a reference paper to match, read it first and mirror its structure, heading style,
author block, figure/table conventions and reference density.

### 2. Literature search and verification

Build the source list before writing prose about other work.

1. Brainstorm candidate works by theme (foundational work, closest prior work, competing approaches,
   methodology and evaluation practice, datasets/tools used). Aim for coverage, not padding: a conference
   paper typically cites 20-40 works, a survey far more.
2. Find each candidate with web search, then **verify it** from a primary record: Crossref by DOI,
   the arXiv abstract page, the publisher or USENIX/ACM/IEEE page, or the paper PDF. Record authors (all,
   in order), exact title (including subtitle), venue with edition/ordinal, year, pages, volume/issue, DOI.
   `scripts/lookup_refs.py` automates the lookups (fallback below); details and pitfalls are in Appendix D.
3. Read enough of each source (at least the abstract; more for works you discuss in depth) to state
   accurately what it does. Note the specific sentence each citation will support.
4. Check whether the user's paper already cites each relevant work; add the missing ones.
5. Keep a verification log (key, what was opened, what claim it supports). Report it at the end.

If a claim needs a source you cannot verify, rewrite the claim without it or drop it, and tell the user.
Never leave `[citation needed]` in a delivered draft without saying so explicitly.

### 3. Structure

Use the structure in Appendix B:
- Research paper: Title, Authors, Abstract, Index Terms, I. Introduction (with contributions), II. Related Work
  (lettered subsections by theme), III. Problem Formulation / Background, IV. Methodology / System Design,
  V. Experimental Setup, VI. Results and Discussion, VII. Threats to Validity (or Limitations), VIII.
  Conclusion and Future Work, References.
- Literature review / survey: taxonomy-driven sections, a comparison table, open challenges, conclusion.
Write an outline first and share it for large pieces of work.

### 4. Drafting

Write in the style described in Appendix C: formal, precise, plain, and in the authors' own words. Key points:
- Organise related work by idea, not paper by paper; end with how this work differs.
- Paraphrase genuinely: change structure and vocabulary, not just a few words; attribute the idea anyway.
  Direct quotes only when wording itself matters, in quotation marks, short, with the citation.
- Size every claim to its evidence ("in our measurements", "on this dataset"); state scope limits plainly.
- Numbers in prose should trace to the user's data. In LaTeX projects prefer generating numbers into macros
  from the results files rather than typing them.
- No contractions, no hype, no stock AI phrasing (see the list in Appendix C).

### 5. Citations and references (IEEE)

Follow Appendix A exactly. The essentials:
- Numeric citations in square brackets, numbered in **order of first citation**: `[1]`, `[2], [3]`, `[4]-[7]`
  (en dash in ranges). The citation goes inside the sentence punctuation: "... as shown in [3]."
- Cite as a noun or as a tag, never both ("In [3], the authors show..." or "Goel et al. [3] show...").
  "et al." only for three or more authors, and always with the number.
- No citations in the abstract.
- Every reference is cited in the text, and every citation has a reference.
- Reference entries: initials + surname, "and" before the last author; more than six authors -> first author
  + "et al."; article titles in sentence case in quotation marks; journal/proceedings names abbreviated and
  italicised; book titles in title case and italics; arXiv as `arXiv preprint arXiv:NNNN.NNNNN`.

In LaTeX, use BibTeX with `IEEEtran.bst` and follow the bib conventions in Appendix A (double-braced
`Proc.` booktitles, protected acronyms, sentence-case titles via `scripts/bib_tools.py` or its fallback).

### 6. Originality check

Before delivery, compare the draft against the texts of the cited sources:
`python scripts/overlap_check.py <draft> <folder of source texts>` (collect abstracts or PDFs of the cited
works into the folder), or the fallback below. It lists every run of 6+ identical words and close
paraphrases. Rewrite flagged sentences in your own structure while keeping the claim and citation, then
re-run until no 6+ word run remains except quotations, names of methods, titles and standard terminology.
See Appendix C for how.

Be honest about the limits: this checks against the cited sources only, not the whole web. It is not
Turnitin; recommend the user run their institution's checker before submission.

### 7. Build (when a document is requested)

- **LaTeX / PDF (IEEE two-column):** start from `assets/ieee_conference_template/` (IEEEtran class and
  BibTeX style included) or the fallback below. Compile with pdflatex -> bibtex -> pdflatex x2, then read
  the `.log` and `.blg`.
- **Word (.docx):** pandoc from the LaTeX with `--citeproc --csl=assets/ieee.csl`, then a layout pass for two
  columns, Times New Roman 10 pt and the author block (python-docx). Or write the .docx directly with the
  docx skill if no LaTeX exists.
- Toolchain notes (finding or installing LaTeX, Overleaf fallback, Word layout details) are in Appendix E.

### 8. Final checks and report

Run `python scripts/check_citations.py <main.tex or draft.md> [--bib refs.bib] [--pdf main.pdf]` (or the
fallback) and fix every FAIL. Then work through the checklist in Appendix F (formatting, numbering,
captions, references, page count). Finally report to the user, plainly:
- what was produced and where the files are;
- references added (with how each was verified) and anything that could not be verified;
- citation-check and originality-check results;
- open items: placeholders (affiliations, title), page count against the limit, anything not checked.
State failures plainly; never claim a check passed unless it was run.

## Helper scripts and template (fallbacks)

This installed version carries its reference guides as appendices below. The original package also had helper
scripts and a LaTeX template; if they are not present alongside this file, use these equivalents:
- `lookup_refs.py` -> fetch `https://api.crossref.org/works/<DOI>`, `https://api.openalex.org/works/doi:<DOI>`
  (abstracts), `https://api.crossref.org/works?query.bibliographic=<title>&rows=5`, or `https://arxiv.org/abs/<ID>`
  with web fetch; always join Crossref `title` + `subtitle`.
- `bib_tools.py` -> convert .bib titles to sentence case with a short script, protecting acronyms and proper
  nouns in braces; add the `@IEEEtranBSTCTL` block from Appendix A.
- `check_citations.py` -> write a short script: collect `\cite{}` keys / `[n]` markers, check order of first
  citation, every cited key in the .bib and every .bib entry cited, no citations in the abstract, "et al."
  always followed by a number.
- `overlap_check.py` -> write a short script that tokenises the draft and each source text and reports every
  shared run of 6+ words (plus difflib ratio > 0.8 for sentence pairs).
- `assets/ieee_conference_template/` -> `IEEEtran.cls` / `IEEEtran.bst` ship with TeX Live/MiKTeX
  (CTAN package `ieeetran`); start `main.tex` from `\documentclass[conference]{IEEEtran}` with packages
  `cite, amsmath, amssymb, graphicx, url, array, algorithm, algpseudocode`, and `\bibliographystyle{IEEEtran}`.
- `assets/ieee.csl` -> the "ieee" style from the CSL styles repository (github.com/citation-style-language/styles).

---

## Appendix A: IEEE citations and reference entries

Based on the IEEE Reference Guide and IEEE Editorial Style Manual conventions. When a venue's author kit gives
different instructions, the venue wins.

### A1. In-text citations

- Numbered in square brackets in **order of first citation** in the body (the abstract is not counted and
  carries no citations). A work keeps its number wherever it is cited again.
- Placement: inside the sentence, before punctuation: "... at microsecond timescales [7]."
- Several works: `[2], [5]`; consecutive runs as a range with an en dash: `[4]-[7]` (typeset `[4]--[7]`).
  The LaTeX `cite` package does this automatically.
- As a noun: "In [3], the authors define ..." or "Reference [3] shows ..." (at sentence start write
  "Reference [3]", never "[3] shows"). With names: "Goel et al. [3] define ..." Never both styles at once.
- Authors named in text: one author "Dinda [10]"; two "Hoefler and Belli [33]"; three or more
  "Mytkowicz et al. [32]". "et al." always carries the citation number.
- Specific parts: "[3, Sec. 3.2]", "[5, Fig. 4]", "[8, p. 12]", "[2, Eq. (1)]".
- Direct quotes: short, in double quotation marks, with the number; prefer paraphrase.
- Cross-references inside the paper: "Section III", "Table II", "Fig. 3" ("Figure 3" only at the start of a
  sentence), equations as "(4)" ("Equation (4)" at the start of a sentence), "Algorithm 1".

### A2. Reference list rules

- Heading "References" (IEEEtran prints REFERENCES), entries numbered [1], [2], ... in citation order,
  hanging indent. Only works cited in the text appear, and each appears once.
- **Authors:** initials then surname: `A. B. Surname`. Hyphenated given names keep the hyphen: `G.-I. Yu`.
  Separate with commas, "and" before the last (with a comma before "and" when there are three or more).
  More than six authors: first author followed by "et al." (`W. Kwon et al.`). Organisations as authors
  are written out: `Qwen Team`.
- **Titles of articles, papers, chapters:** sentence case in double quotes, with the comma inside the quote:
  `"Heracles: Improving resource efficiency at scale,"`. Keep capitals for proper nouns, acronyms, system
  names and the first word after a colon (`Linux`, `LLM`, `PagedAttention`, `QoS`).
- **Titles of books, journals, proceedings:** italics; books in title case; journal and proceedings names
  abbreviated (A4).
- Months abbreviated: Jan., Feb., Mar., Apr., May, Jun., Jul., Aug., Sep., Oct., Nov., Dec.
- Pages `pp. 611-626` (en dash); single page `p. 5`; article numbers `Art. no. 292`.
- DOI at the end when available: `doi: 10.1145/2749469.2749475.` Be consistent across the list: either give
  DOIs for all entries that have one, or for none (some templates, e.g. IEEEtran.bst v1.14, omit them).
- URLs: `[Online]. Available: https://...` as the last element; add `Accessed: Mon. Day, Year.` for web pages.
- Prefer the peer-reviewed version over a preprint when both exist; cite both only if both are used for
  different things (for example a preprint's section numbering).

### A3. Entry formats by type

Journal article
```
[1] J. Dean and L. A. Barroso, "The tail at scale," Commun. ACM, vol. 56, no. 2, pp. 74-80, Feb. 2013,
    doi: 10.1145/2408776.2408794.
```
Pattern: `A. Author, B. Author, and C. Author, "Title of article," Abbrev. Journal, vol. x, no. x,
pp. xxx-xxx, Mon. year, doi: xxx.`

Conference paper (published proceedings)
```
[2] D. Lo, L. Cheng, R. Govindaraju, P. Ranganathan, and C. Kozyrakis, "Heracles: Improving resource
    efficiency at scale," in Proc. 42nd Annu. Int. Symp. Comput. Archit. (ISCA), 2015, pp. 450-462.
```
Pattern: `A. Author, "Title of paper," in Proc. Abbrev. Name of Conf. (ACRONYM), [City, Country,] year,
pp. xxx-xxx, doi: xxx.` Use the ordinal only if verified (e.g., from the proceedings title on Crossref).

arXiv / preprint
```
[3] K. Goel, J. Mohan, N. Kwatra, R. S. Anupindi, and R. Ramjee, "Niyama: Breaking the silos of LLM
    inference serving," arXiv preprint arXiv:2503.22562, 2025.
```
(The IEEE guide's shorter form `arXiv:2503.22562, 2025.` is also acceptable; pick one and use it throughout.)

Book / edited book / chapter
```
[4] B. Efron and R. J. Tibshirani, An Introduction to the Bootstrap. Boston, MA, USA: Springer, 1993.
[5] A. Author, "Title of chapter," in Title of Book, 2nd ed., E. Editor, Ed. City, Country: Publisher,
    year, ch. 3, pp. 45-67.
```
Thesis
```
[6] A. Author, "Title of thesis," Ph.D. dissertation, Dept. Comput. Sci., Univ. Name, City, Country, year.
    (M.S. thesis: "M.S. thesis, ...")
```
Technical report
```
[7] A. Author, "Title of report," Org. Name, City, Country, Tech. Rep. TR-123, year.
```
Standard
```
[8] IEEE Standard for Floating-Point Arithmetic, IEEE Std 754-2019, 2019.
```
Patent
```
[9] A. Author, "Title of patent," U.S. Patent 1 234 567, Jan. 1, 2020.
```
Software / code repository
```
[10] G. Gerganov and ggml-org contributors, "llama.cpp: LLM inference in C/C++," GitHub repository,
     build b11053 (commit 1af554f8f), 2023. [Online]. Available: https://github.com/ggml-org/llama.cpp
```
Dataset
```
[11] A. Author, "Title of dataset," Repository Name, year, doi: xxx. (or [Online]. Available: URL)
```
Web page
```
[12] A. Author (or Org.). "Title of page." Site Name. Accessed: Sep. 30, 2026. [Online]. Available: URL
```
Always state the version, build or commit for software and datasets used in experiments.

### A4. Abbreviations for journal and proceedings names

Proceedings Proc. | International Int. | Conference Conf. | Symposium Symp. | Annual Annu. |
Transactions Trans. | Journal J. | Computer, Computing Comput. | Communications Commun. | Systems Syst. |
Engineering Eng. | Technology Technol. | Information Inf. | Science Sci. | Society Soc. |
Architecture Archit. | Operating Oper. | Programming Program. | Languages Lang. |
Networked, Networking, Networks Netw. | Implementation Implement. | Management Manage. |
Machine Mach. | Learning Learn. | Intelligence Intell. | Artificial Artif. | Electronics Electron. |
Processing Process. | Distributed Distrib. | Performance Perform. | Applications Appl. | Analysis Anal. |
Research Res. | Review Rev. | Letters Lett. | Magazine Mag. | Automation Autom. | Recognition Recognit. |
Security Secur. | Software Softw. | European Eur. | American Amer. | Association Assoc. | Mobile Mobile |
Memory Memory | Cloud Cloud | Support Support | Microarchitecture Microarchitecture
Keep short words (Workshop, Design, High, Parallel) unabbreviated unless the venue's own style says otherwise.
Well-known forms: `IEEE Trans. Parallel Distrib. Syst.`, `Commun. ACM`, `Proc. IEEE`, `J. Supercomput.`.
Acronym in parentheses after the name: `(ISCA)`, `(OSDI)`, `(ASPLOS)`.

### A5. BibTeX conventions for IEEEtran

- Styles: `\bibliographystyle{IEEEtran}` + `\usepackage{cite}`; `IEEEtran.bst` is the unsorted variant, so
  numbering follows first citation.
- IEEEtran.bst prints titles **as written**: store article titles in IEEE sentence case with protected
  capitals (`{LLM}`, `{Linux}`). `scripts/bib_tools.py sentence-case` (or the fallback) converts a title-case .bib.
- `@inproceedings`: `booktitle = {{Proc. 42nd Annu. Int. Symp. Comput. Archit. (ISCA)}}` - double braces
  keep a CSL/pandoc build from lower-casing it.
- `@article` for journals; for arXiv: `journal = {arXiv preprint arXiv:2503.22562}`.
- `@misc` for software: `howpublished = {GitHub repository, build ...}`, `url = {...}`.
- `@book`: `publisher`, `address`; keep the title in title case.
- Style controls (put in the .bib, activate with `\bstctlcite{IEEEexample:BSTcontrol}` right after
  `\begin{document}`):
  ```
  @IEEEtranBSTCTL{IEEEexample:BSTcontrol,
    CTLdash_repeated_names = "no",
    CTLuse_forced_etal = "yes",
    CTLmax_names_forced_etal = "6",
    CTLnames_show_etal = "1"
  }
  ```
  The first line prints repeated author lists in full instead of a dash; the rest apply the more-than-six
  -> "et al." rule.
- Never put an "@" in a .bib comment: BibTeX reads it as the start of an entry.
- Internal notes in `note` fields are printed by IEEEtran; keep private notes as `%` comments instead.

### A6. Common mistakes

- Citation numbers not in order of first appearance (usually a hand-numbered list): let BibTeX number them.
- Title case in article titles, or lower-cased acronyms ("llm", "gpu") from an unprotected .bib.
- "et al." without a number, or for two authors.
- Citing in the abstract; citing a work that is not in the list; a listed work never cited.
- Missing pages/volume/DOI that the primary record has; wrong ordinal; SIGPLAN Notices reprint DOI used
  instead of the proceedings DOI.
- Preprint cited when the peer-reviewed version exists.
- Inconsistent forms of the same venue across entries.

---

## Appendix B: Structure of research papers and literature reviews

### B1. Research paper (IEEE conference)

**Title.** Specific and searchable; states the object, the method or finding, and the setting. Avoid
"novel", "towards", "a new". Mark it as a working title until the authors confirm it.

**Author block.** One block per author: name; department (italic); institution; city, country; e-mail.
Never guess these (use placeholders).

**Abstract** (150-250 words, one paragraph, no citations, no undefined abbreviations, no equations).
Cover in order: context and problem (1-2 sentences), what was done (method, setting), the main result with
its key number(s), what it means, and the principal limitation or scope. A reader should learn the
headline result from the abstract alone.

**Index Terms.** 3-6 terms, alphabetical, preferably from the IEEE Taxonomy/Thesaurus.

**I. Introduction.** Motivation and problem; why existing answers are incomplete (with citations); the
question this paper asks; approach in one paragraph; headline result stated early; a bulleted list of
contributions (specific and checkable, e.g. "a measurement of X on Y showing Z"); optionally a roadmap
paragraph ("Section II reviews ...").

**II. Related Work.** Lettered subsections by theme (A., B., ...), each ending with how this work differs.
A final paragraph or subsection positions the paper; an optional comparison table (work vs. signal,
granularity, setting, what it controls, limitation). Credit definitions and methods you reuse.

**III. Problem Formulation / Background / System Model.** Definitions, notation, assumptions and the
quantities the paper measures or optimises, with numbered equations.

**IV. Methodology / Design.** What was built or done, described as implemented, at a level that allows
replication. Algorithms as numbered Algorithm floats. State fixed parameters and why they were chosen.

**V. Experimental Setup.** Hardware, software with versions, datasets or workloads, baselines, metrics,
number of repetitions, statistical method (confidence intervals, how computed), seeds.

**VI. Results and Discussion.** One subsection per question or experiment. Lead each with the finding,
then the evidence (figure/table), then interpretation and caveats. Report variability, not only means.
Negative or inconclusive results are reported as such.

**VII. Threats to Validity / Limitations.** Internal, external, construct and statistical threats; what
was not measured. A bulleted list is acceptable here.

**VIII. Conclusion and Future Work.** Restate the question and the answer with the key numbers; what
does and does not generalise; concrete next steps. No new results, no citations needed.

**Acknowledgment** (optional, singular in IEEE style), **References**, **Appendices** (if allowed).

### B2. Literature review / survey

1. **Title and abstract**: scope, number of works reviewed, main taxonomy, key findings, open challenges.
2. **Introduction**: why the area matters now, scope boundaries (what is in and out), contributions of the
   review, comparison with existing surveys (cite them and say what this one adds).
3. **Review methodology**: databases and search engines queried, search strings, date range, inclusion
   and exclusion criteria, screening steps and counts (a PRISMA-style flow is good practice for systematic
   reviews). Only report counts you actually obtained.
4. **Background**: definitions and terminology used throughout.
5. **Taxonomy**: a classification of approaches (a figure helps), then one section per category. Within a
   category, compare works along the same dimensions and synthesise: what the approaches share, where they
   disagree, what evidence supports each.
6. **Comparative analysis**: a summary table (work, year, approach, data/setting, metric, main result,
   limitation). Every row cited; every value taken from the cited paper.
7. **Open challenges and future directions**: gaps derived from the analysis, not generic wishes.
8. **Conclusion**.
A literature review is a synthesis, not a list of summaries: every paragraph should make a point that uses
several sources.

A **related-work section** alone follows the same logic in miniature: themes, synthesis, and a closing
statement of how the paper differs.

### B3. Figures, tables, equations, algorithms

- **Tables**: Roman numerals (TABLE I). Caption *above* the table. Referenced in text as "Table I" before or
  near where it appears. Units in column headers. Horizontal rules only; no vertical rules.
- **Figures**: Arabic numerals (Fig. 1). Caption *below*, starting "Fig. 1." Axis labels with units,
  readable at column width, legend inside the plot area when possible, colours distinguishable in grey.
- IEEE numbers floats in order of first appearance; in LaTeX use `\label`/`\ref`, never hand-typed numbers.
- Wide tables and figures span both columns (`table*`, `figure*`) and float to the top of a page.
- **Equations**: numbered consecutively (1), (2), ... at the right margin; punctuate as part of the sentence;
  define every symbol at first use.
- **Algorithms**: `algorithm` + `algpseudocode`, numbered, with a caption; keep steps short.

### B4. Length budgets (IEEE two-column conference)

| Pages (incl. references) | 6 | 8 | 10 |
|---|---|---|---|
| Words of body text (approx.) | 4,000 | 5,500 | 7,000 |
| References (typical) | 15-25 | 20-35 | 25-45 |
| Figures + tables | 4-6 | 5-8 | 6-10 |

When over the limit, cut in this order: redundant restatements, tables that repeat prose, over-long
related work, secondary results (move to an appendix or artifact). Never cut limitations to save space.

---

## Appendix C: Writing style - professional, precise, original

### C1. Voice and register

- Formal but plain. Short declarative sentences; one idea per sentence; paragraphs of 3-6 sentences that
  each make one point.
- "We" is acceptable for what the authors did. Prefer active voice when it clarifies who did what.
- Tense: present for established knowledge and for what the paper shows ("Table II shows ..."); past for
  what was done in the experiments ("We ran five repetitions ...").
- No contractions, no rhetorical questions in the body, no exclamation marks, no second person.
- Define every abbreviation at first use in the abstract and again in the body: "time between tokens (TBT)".
- Units: SI, with a space and roman type: `10 ms`, `4 GB`, `2.4 GHz`; `%` without a space is also IEEE usage,
  but be consistent. Numbers below ten in words unless attached to a unit.
- Keep terminology fixed once defined; do not alternate synonyms for the same quantity.

### C2. Sizing claims to evidence

- State results with their scope: "on this dataset", "in our setup", "for the models studied".
- Separate what was measured from what is inferred: "The idle fraction rose by 0.14 [0.11, 0.18]; this is
  consistent with, but does not prove, ..."
- Report uncertainty (intervals, spread, number of runs) next to point estimates.
- Inconclusive is not negative: say which one a result is.
- Avoid unqualified "significant" unless a test was run; then name the test.
- Never write "first", "only" or "novel" unless a search supports it; prefer "we are not aware of prior work
  that ...".

### C3. Words and habits to avoid

These read as padding or machine-generated and lower reviewers' trust: delve, leverage (as a verb), utilize
(use "use"), seamless, robust (unless defined), crucial, pivotal, paramount, cutting-edge, state-of-the-art
(as filler), landscape, realm, tapestry, holistic, synergy, showcase, underscore, shed light on,
pave the way, plays a vital role, in today's world, it is worth noting that, it is important to note,
moreover/furthermore at every paragraph start, "not only ... but also" chains, groups of three adjectives,
em dashes used as a rhythm device. One occasional "however" or "moreover" is fine; patterns are the problem.

### C4. Writing about other work (paraphrase, attribution, originality)

- Read the source, close it, then write what it does in your own sentence structure and vocabulary. Changing
  a few words of the original sentence is still plagiarism (patchwriting).
- Always attribute: paraphrased ideas need the citation just as quotes do.
- Say what the work *does* and *finds*, then connect it to this paper: "X reallocates cores at microsecond
  granularity [6]; it reacts to observed congestion, whereas ...".
- Do not copy an abstract's list structure ("A, B and C") or its signature phrases; rebuild the sentence around
  the point that matters for your paper.
- Paper titles, method names, metric names and standard terms (for example "time to first token") may be
  reused verbatim; they are not plagiarism.
- Quotes: rare, short (under about 25 words), in quotation marks with the citation and, if useful, a page or
  section.
- Never describe details you have not read; if only the abstract was read, stay at that level.

### C5. Rewriting a flagged sentence

When the overlap check flags a run of identical words or a close paraphrase:
1. Identify the single claim the sentence makes and why this paper cites it.
2. Rewrite from that claim, starting the sentence differently (subject, verb, or order of ideas).
3. Use concrete, plain words; split long sentences.
4. Re-check the rewrite against the source for accuracy: it must not add details the source does not state.
5. Re-run the overlap check.

Example. Source: "Stall-free scheduling unlocks the opportunity to improve throughput with large batch sizes
while minimizing the effect of batching on latency." Too close: "Stall-free scheduling improves throughput
with large batches while minimising batching's effect on latency [11]." Better: "Sarathi-Serve cuts a long
prompt into pieces processed over several iterations, so that requests already generating keep receiving
tokens [11]."

### C6. Final read-through

Read the draft once for logic (does each paragraph earn its place, does the evidence support the claim),
once for style (the list above), and once for consistency (terms, symbols, units, numbering, capitalisation of
headings, reference format).

---

## Appendix D: Verifying sources

A reference is verified when its metadata and the claim it supports have been checked against a primary
record opened in the current session. Memory, search-result snippets and AI summaries are leads, not
verification.

### D1. Where to verify (in order of preference)

| Source type | Primary record | How |
|---|---|---|
| Anything with a DOI (ACM, IEEE, Springer, Elsevier, most journals) | Crossref record | `python scripts/lookup_refs.py doi 10.1145/2749469.2749475` or fetch api.crossref.org/works/DOI |
| arXiv preprint | arxiv.org/abs/ID page | `python scripts/lookup_refs.py arxiv 2503.22562` or fetch the abs page |
| USENIX (OSDI, NSDI, ATC, FAST, Security) - no DOIs | usenix.org presentation page (authors, pages, abstract) | web fetch the page |
| Title only | Crossref bibliographic search, then confirm by DOI | `python scripts/lookup_refs.py title "..."` |
| Abstract text | OpenAlex, publisher page, arXiv page, author PDF | |
| Software / datasets | the repository or archive page (version, commit, licence) | |
| Standards | the standards body's catalogue page | |

Notes and pitfalls:
- **Crossref splits titles:** the `title` may be just "Heracles" with the rest in `subtitle`. Always combine
  title and subtitle.
- **Proceedings vs. reprint DOIs:** ASPLOS/ISCA papers also appear in ACM SIGPLAN Notices / SIGARCH CAN
  with a different DOI. Cite the proceedings version (container title "Proceedings of ...").
- **Ordinals** ("42nd Annual ...") come from the container title; do not guess them.
- **arXiv:** the ID gives the first-version month (2503 = Mar. 2025), but the listed v1 date on the page
  is authoritative for the year; cite the year only. Check whether a peer-reviewed version exists.
- **dblp** is excellent but sits behind a bot-check; do not try to get around bot-detection or CAPTCHAs.
  Use Crossref/OpenAlex instead, or ask the user to look it up.
- **Semantic Scholar's API** is rate-limited without a key; treat 429s as "try another source".
- **arXiv's export API** may reject scripted requests (HTTP 406); the abs page works.
- Author names: keep diacritics (`Mart{\'i}nez`) and hyphenated initials (`G.-I. Yu`).
- If metadata sources disagree, the publisher's page wins; note the discrepancy in the log.

### D2. Verifying the claim, not just the citation

For each sentence that cites a work:
1. Open the text you are relying on (abstract at minimum; the relevant section for specific claims).
2. Check that the sentence says no more than the text does: numbers, mechanisms and scope must match.
3. If you rely on a specific section, figure or equation, consider citing it: `[3, Sec. 3.2]`.
4. Numbers quoted from literature: quote them only after reading them in the full text, not from an abstract
   summary by a third party. Record the sentence they came from.

### D3. Verification log (keep it; report it)

Keep one line per reference, for example in `references_log.md` next to the draft:
```
key | verified via | date | supports (which sentence/claim) | notes
lo2015heracles | Crossref 10.1145/2749469.2749475 + author PDF | 2026-09-23 | 15 s control loop, Sec. II-C | pages 450-462
```
Candidates considered but not cited, and why (not verifiable, not relevant), belong in the log too, so the
next session does not re-add them blindly.

### D4. When a source cannot be verified

Remove the claim or rewrite it without the unverifiable detail, and tell the user which reference was
dropped and why. Do not substitute a similar-looking reference that says something different.

---

## Appendix E: Building PDF and Word output

### E1. LaTeX (IEEEtran two-column PDF)

1. Copy `assets/ieee_conference_template/` to the project if available (it contains `main.tex`, `refs.bib`,
   `IEEEtran.cls`, `IEEEtran.bst`); otherwise build the skeleton per the fallback section. For journals use
   `\documentclass[journal]{IEEEtran}`.
2. Packages: `cite`, `amsmath`, `amssymb`, `graphicx`, `url`, `array`, `algorithm`, `algpseudocode`. Avoid
   `hyperref` colour boxes and page numbers in camera-ready conference papers unless the venue asks.
3. Compile: `pdflatex main` -> `bibtex main` -> `pdflatex main` -> `pdflatex main`.
4. Read the logs, and fix before delivering:
   - `main.log`: "Citation ... undefined", "Reference ... undefined", "There were undefined references",
     "Overfull \hbox" wider than about 5 pt (text sticking into the margin).
   - `main.blg`: "I didn't find a database entry", "Warning--", "I was expecting a `{'" (often an `@` in a
     comment).
5. Page count: `Output written on main.pdf (N pages`.

#### Finding or installing a LaTeX engine

Check in this order: `pdflatex --version` on PATH; MiKTeX or TeX Live under Program Files; inside WSL
(`wsl -- which pdflatex`, and `~/slackgate/tinytex/.TinyTeX/bin/x86_64-linux/pdflatex` on this user's machine,
where TinyTeX is already installed with algorithms, algorithmicx, cite and courier added). If none exists:
- **Overleaf** (no install): zip the project for the user to upload; never log in on the user's behalf.
- **TinyTeX** (user space, no admin): ask before downloading (TinyTeX-1 for Linux is about 55 MB). Verify the
  SHA-256 against the digest on the GitHub release, extract, then `tlmgr install algorithms algorithmicx cite
  courier` (plus anything a compile reports missing).
- tectonic may stall downloading its package bundle on some networks; prefer TinyTeX if it does.

#### Layout tips

- Wide tables: `table*` (spans both columns, floats to the top). Narrow tables with long text: `\footnotesize`,
  `\setlength{\tabcolsep}{3pt}` and ragged-right paragraph columns
  `>{\raggedright\arraybackslash}p{2.5cm}` (needs `array`).
- Figures: `\includegraphics[width=\columnwidth]{...}`; `figure*` with `\textwidth` if unreadable at column width.
- Unbreakable identifiers like `SCHED_IDLE` in narrow cells cause overfull boxes: widen that column.
- Use `\label`/`\ref` for every section, table, figure, equation and algorithm; never type the numbers.
- Algorithms: `\begin{algorithm}[t]\caption{...}\label{alg:x}\begin{algorithmic}[1] ... \end{algorithmic}\end{algorithm}`.
- Author block: `\author{\IEEEauthorblockN{Name}\IEEEauthorblockA{\textit{Dept.}\\ Institution\\ City, Country\\ email}\and ...}`.
- Keywords: `\begin{IEEEkeywords} ... \end{IEEEkeywords}` after the abstract.

### E2. Word (.docx)

Preferred route when a LaTeX source exists (keeps numbering and citations identical to the PDF):
1. Resolve `\ref` numbers from the compiled `.aux` file and write them into a copy of the sources, with
   hand-numbered headings ("I. Introduction", subsections "A. ..."), captions ("TABLE I. ...", "Fig. 1. ...")
   and equation tags, because pandoc does not number them.
2. `pandoc main.tex --from=latex --to=docx --citeproc --bibliography=refs.bib --csl=ieee.csl
   [--reference-doc=template.docx] -o out.docx`. pandoc cannot read `algorithmic`; substitute a verbatim block.
3. Layout pass with python-docx:
   - US Letter, margins top 0.75 in, bottom 1 in, left/right 0.625 in; Times New Roman 10 pt, justified.
   - Title 24 pt centred; author block as a borderless table with one column per author.
   - Abstract run-in "Abstract-" bold italic, text bold 9 pt; "Index Terms-" likewise.
   - Heading 1 centred small caps; Heading 2 italic.
   - A continuous section break after the author block; body sections set to two columns (0.25 in gap).
   - Wide tables and long code blocks: surround with continuous section breaks and set that section to one column.
   - Tables: fixed layout with explicit column widths sized to content (Word keeps pandoc's narrow widths
     otherwise); set first-line indent 0 in cells, 8 pt text.
   - Add a "References" heading before the bibliography; references 8 pt.
4. Check by exporting to PDF through Word (COM automation on Windows) and looking at every page; compare the
   numbers in the Word text with the PDF text.
Without LaTeX, write the .docx directly (docx skill), using the same styles and a numbered reference list.

### E3. Markdown or chat output

Use the same structure and IEEE numbering; list references at the end under "References" in IEEE format.

---

## Appendix F: Pre-delivery checklist

Report each item as pass / fail / not applicable. Never mark an item passed without checking it.

### Content integrity
- [ ] Every number in the paper traces to the user's data or a cited source; nothing estimated or invented.
- [ ] Every reference verified against a primary record this session (verification log exists).
- [ ] Every sentence about other work matches what the source says (abstract-level claims only if only
      the abstract was read).
- [ ] Reused definitions, metrics, datasets and methods are credited where used.
- [ ] Contribution claims are narrow and supported; limitations are stated.
- [ ] Originality check run; no 6+ word runs copied from sources except quotes, titles, names, standard terms.

### Citations and references
- [ ] Citation check reports 0 FAIL.
- [ ] Numbered in order of first citation; no citation in the abstract; every [n] within range.
- [ ] Every cited work listed once; no listed work uncited.
- [ ] Entries complete for their type (authors, title, venue, year; volume/issue/pages/DOI where they exist).
- [ ] Sentence-case article titles; protected acronyms; abbreviated venue names; consistent arXiv form.
- [ ] More than six authors -> "et al."; "et al." in text only for 3+ authors and always with a number.

### Format (IEEE conference)
- [ ] Two columns, 10 pt Times, IEEEtran conference layout (or the venue's template).
- [ ] Title, author blocks (no guessed affiliations), "Abstract-", "Index Terms-".
- [ ] Roman section numbers, lettered subsections; tables Roman with captions above; figures Arabic with
      captions below; equations numbered consecutively; all floats referenced in text, in order.
- [ ] No overfull boxes over about 5 pt; no undefined references; BibTeX clean.
- [ ] Page count within the limit (report it; propose cuts rather than cutting silently).
- [ ] Bullets only in contributions and threats/limitations lists.

### Delivery
- [ ] Files delivered where the user can find them; locations reported.
- [ ] Open items listed: placeholders, title confirmation, anything not verified or not checked.

---

Third-party notes: IEEEtran.cls/IEEEtran.bst are by Michael Shell et al. (CTAN, LPPL); the IEEE CSL style is
from the Citation Style Language project (CC BY-SA 3.0).