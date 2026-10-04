# T1.3 choropleth — review notes

The acceptance criterion for T1.3 (`docs/IMPLEMENTATION_PLAN.md`) is "a choropleth of `σ(ℓ₀)`
over Chennai that a local human recognises as plausible." This is not that review — it is my
own (an LLM's) first-pass visual sanity check of the choropleth `scripts/t1_3_make_choropleth_data.py`
produced, done before committing, to catch the kind of coordinate-system or obviously-wrong-shape
error the acceptance criterion specifically calls out ("this catches coordinate-system errors
that no unit test will"). **It does not substitute for an actual Chennai resident looking at
the map** — that review is still open.

The rendered map (published as a Claude Artifact; ask the session that generated it for the
link, or regenerate with `scripts/t1_3_make_choropleth_data.py` + the HTML in this task's
commit) shows:

- **The road network's own shape is recognisably Chennai-like**: a coastal edge along the
  upper-right, and large contiguous gaps with no drivable-road cells at all in the middle of
  the built-up area — consistent with the Pallikaranai marsh / large institutional campuses
  (IIT Madras, Guindy National Park, the airport) that genuinely have little to no road network
  running through them, not a rendering bug.
- **Velachery–Taramani sits directly inside a dense, dark (high-`σ(ℓ₀)`) cluster** — Velachery
  is one of the best-known chronic waterlogging areas in Chennai; this is the single strongest
  plausibility signal the map gives.
- **Pallikaranai sits adjacent to elevated-risk cells**, consistent with `research/SYNTHESIS.md`
  §9's Michaung reporting (Narayanapuram Lake overflow onto the 200 ft radial road).
- **Adyar–Kotturpuram sits at the edge of a moderate cluster, not inside the darkest one** —
  matches the same press reporting's explicit negative signal (this corridor was *not* badly
  hit during Michaung, unlike its neighbours).
- **The Mudichur-corridor marker sits in a visibly empty region of the map, with no nearby
  cells at all** — a direct visual confirmation of the source-coverage gap already verified
  and written into `docs/DECISIONS.md` (ADR-009 addendum, 2026-09-14): the primary GCC/OpenCity
  KML has almost no data near this corridor.
- A dense high-`σ(ℓ₀)` band runs along the southeastern edge of the mapped area (OMR /
  Elcot SEZ corridor direction) — plausible given that corridor's known low-lying, historically
  waterlogged reputation, but not independently cross-checked against a named press source the
  way the other clusters were.

**What would fail this review, and didn't happen:** the road network resembling a random grid
or a shape with no recognisable coastline; high-risk cells scattered with no spatial
correlation to any named corridor; every cell reading the same colour (indicating the KML join
or the log-odds math was broken); Velachery or Pallikaranai reading as *low* risk. None of
these occurred.

**Still open:** an actual person who knows Chennai has not yet looked at this map. Book that
review before treating T1.3 as done, per the task's own acceptance criterion.
