# Critique and deep review

**Reading order:**
1. `CityPulse_critique_review_council_plan.pdf`: the full report. It covers classification, the review, the council and the revised plan. `critique_report.md` is the Markdown source.
2. `CLASSIFICATION.md`: TRL per component, maturity, contribution type, ACM CCS concepts and market category.
3. `deep_review/3_adjudication.md`: the final ruling on every finding, the surviving issues ranked, and questions for the authors.
4. `deep_review/1_specialist_reviews/`: eight specialist reviews, S1–S8.
   - S1–S3: novelty (flood routing, belief, explanation)
   - S4: route evaluation
   - S5: calibration
   - S6: formulation
   - S7: business
   - S8: code vs claims, and classification
5. `deep_review/2_findings_and_defences/`: findings grouped into five batches (D1–D5), each with the defence agent's rebuttal and re-computed numbers.
   - `findings.json` is the machine-readable list.

**Process:**
- Specialists → defence (arguing for the authors) → independent adjudication.
- Results: 83 findings; 5 survived as Critical, 15 as Significant for the paper, 7 as Significant for the plan, 25 as Minor; 4 dropped.

**What to act on:** surviving issues are mapped to fixable items F-01…F-23 in `../00_START_HERE/KNOWN_FLAWS.md`.
