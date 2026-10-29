# Datasheet: Chennai Street Flood Evidence (CSFE), prototype v0.2

Structure follows Gebru et al., *Datasheets for Datasets* (Communications of the ACM 64(12), 2021). Build: `2026-10-30/`
(`scripts/build_csfe_proto.py`, rain-window convention B). Schema and sources: `README.md`. All counts below are from
`2026-10-30/summary.json` and the tables, as of 30 Oct 2026.

## Motivation

- **Why it was created.** Chennai has no dataset of time-stamped, street-level evidence of whether a road or subway was flooded,
  closed or open. The CityPulse replay corpus (2015) has one proxy timestamp, no depth and no negative reports, which made decay,
  depth rules and false avoidance untestable (paper, Section VIII). CSFE gathers fragments that already exist into one table.
- **Who created it.** The CityPulse team (VIT Chennai), with an AI assistant writing the build code and hand-extracting news facts;
  every extracted fact carries its link.
- **Funding.** None.

## Composition

- **Instances.** 7,010 observations, one per statement that a place was flooded, not flooded, closed, open or had a depth: 5,221
  crowd, 1,711 official, 78 news. Plus context tables: 87 rain gauges with 451,408 gauge-days (1976–2026), 47 water-level stations
  with 10,064 station-days (2021–2026), 200 ward model depths, 8 city-level news count statements, and a 68-row subway status
  timeline (19 subways, 7 events).
- **Labels.** `kind` is one of `closed`, `partly_open`, `open`, `waterlogged_open`, `not_waterlogged`, `waterlogged`, `depth`,
  `depth_range`, `report_unclear`. Negatives (`not_waterlogged`, `open`, `waterlogged_open`): 163.
- **Time.** 247 observations are known to the day or better; the rest are event-level (2015, 2020) or unknown.
- **Missing.** No gauge rain for 2020–2022 or after Feb 2026; 16 news rows link to watchlist subways that have no position yet;
  9 place names are unmatched on purpose (ambiguous or roads).
- **Noise and conflicts.** Of 52 subway–event pairs, 6 carry more than one status: 4 are real sequences (closed, then reopened or
  partly opened) and 2 are cross-source (Fengal 2024: GCC said "waterlogged but open" at 09:58 on 30 Nov; a report published at 12:45
  on 1 Dec listed the same subways as closed). The citizen app's `level` field is undocumented. Some "official" 2015 points are
  vulnerability designations, not observations.
- **Personal data.** None kept. Citizen-app free text is dropped; no names, faces or number plates; no traces of individuals.
- **Is it a sample?** Yes, of whatever was published: news lists favour closures and well-known subways (15 of the 19 subways in the
  timeline were reported closed at least once). Absence of a report is not evidence of no flooding.

## Collection process

- **Sources.** CFM-DSS (Chennai Flood Monitor, Government of Tamil Nadu) via a Hugging Face mirror pinned on 4 Oct 2026; OpenCity's
  2015 flood layers; the project's subway watchlist; news articles (The News Minute, South First, Business Today, News Today,
  IBTimes/IANS, ThePrint/PTI, The Tribune/PTI, Onmanorama/PTI), read on 29–30 Oct 2026.
- **News extraction.** By hand from each article: the publication time, the place as written, its status, and a quote of at most
  12 words. Live blogs give the time of each update. Publication time is an upper bound on when a status applied.
- **Rain attachment.** For observations known to the day or better: the gauge reading whose 24 h window contains the observation.
  The window convention (a reading dated D covers about 08:30 on D to 08:30 on D+1) was **inferred from the rain series** after an
  earlier assumption proved wrong (`BENCHMARK_PREREGISTRATION.md`, addendum 1); it is not confirmed from gauge metadata.
- **Snapping.** Points to the nearest road edge within 50 m on the 2026-09-14 OpenStreetMap graph, both directions of two-way streets.

## Preprocessing

Depth classes become cm ranges (<2 ft → 0–61 cm, 2–3 ft → 61–91, 3–5 ft → 91–152, >5 ft → 152 and above). Citizen reports whose text
says "test" are dropped. Gauge readings: one a day; 7 duplicate station-days keep the larger value. Water levels: daily maximum.

## Uses

- **Intended.** Testing whether rain and history predict closures; giving routing studies negative labels and times; checking
  flood models against named places; planning what evidence to collect next.
- **Shown so far.** Benchmark B1 (subway closure from rain): no evidence either way, because only 3 events have both labels and
  rain (`data/results/2026-10-30-csfe-b1-addendum1/`).
- **Not suitable for.** Saying that any road or subway is safe or passable now (ADR-011); any operational use; estimating flood
  frequency (the sample follows what was reported).

## Distribution

The generated tables are **not redistributed**: CFM-DSS data has no publisher licence (research use only). What is shared: the build
script, this datasheet, the README, `summary.json`, and the hand-extracted news facts (facts with links and short quotes). OpenCity
layers keep their own terms; the road graph is ODbL.

## Maintenance

Maintained by the CityPulse team. New events are added by extending `news_facts_*.csv` (new dated file) and rebuilding into a new
dated folder; old builds are kept. Planned additions need approvals that have not been given: the OpenCity depth points, IIT Madras's
crowdsourced depth logs, GCC's drain maps, and live CFM-DSS polling.
