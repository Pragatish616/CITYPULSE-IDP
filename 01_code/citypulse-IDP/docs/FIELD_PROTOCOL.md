# Field log protocol (ADR-028)

Written 6 October 2026. **Nothing here has been used by a volunteer yet.** The tool is built and tested locally; it is not deployed.

The aim is one thing the project does not have: a **time-stamped, street-level record of what a person saw** at a place during rain. It is research data. It is not shown to travellers and it does not change a route.

## 1. What a volunteer does

1. Opens the field-log page on their phone (`<site>/ingest/fieldlog/`) and pastes the token they were given, once.
2. Goes to an assigned site (or one near them), stays on safe ground, and looks.
3. Picks the site (search by street, area or id, or "show sites near me"), taps what they see, adds a depth band if the road is not passable, and confirms.
4. Leaves. The entry is kept on the phone and sent when there is a connection. The page shows how many are waiting.

A log takes about 20 seconds. There is nothing to type except the token the first time.

## 2. Safety (printed on the page; repeat it when you brief people)

- **Do not enter floodwater** to look, to measure, or to help a vehicle.
- Do not stand in the carriageway or on a barrier. Do not log from a moving vehicle.
- Do not log if the weather is dangerous where you are (lightning, falling trees, live wires). No entry is worth it.
- Do not photograph or record people. The tool does not accept photos in this version.

## 3. What to tap

The three answers describe **what you saw, not whether anyone should go there.**

| Tap | Use it when | Not when |
|---|---|---|
| **Passable** | You see vehicles of the usual kind getting through the wettest part, or the road has no water on it. | You assume it is fine because it looks shallow, or you only see the near edge. |
| **Not passable** | Water, a barricade or police are stopping the usual traffic; vehicles turn back or stand at the water. | You merely feel you would not cross. |
| **Can't tell** | You cannot see the road or the traffic, you are not at the place, it is dark, or you are unsure. | Never skip a visit because you are unsure: log "can't tell". |

*Depth band* (only with Not passable; your estimate against your own body; this is not a measurement):
**Ankle**, **Knee**, **Above the knee**, **Not sure**.

*Site.* The list holds 402 candidate points taken from the GCC flood-hazard zones. **None is verified**; some sit at a field edge, a flyover or an unnamed road. Log what you see at or near the point. If the site is plainly not on a road, or you are at a different flooded spot, use **Another place**, which sends that spot's position rounded to about 10 m. Do not use it for your home or for anywhere you would not want recorded.

## 4. When to log (the sampling plan)

The data is useful only if "nothing happened" is recorded as carefully as "it flooded".

- **Assigned sites.** Each volunteer gets 3 to 5 sites near where they already travel. Volunteers log their own sites only on days they pass them.
- **Rain days.** On any day it has rained heavily where you are, log every assigned site you pass.
- **Dry-day controls.** Once a week, on a day with no rain for the previous 24 hours, log each assigned site once. These are needed to know how often the answer is "passable" without rain.
- **Pairs.** Twice a month, two volunteers visit the same site within 30 minutes and each logs without seeing the other's answer. This measures how often two people disagree.
- Log "can't tell" when that is true. A missing entry means nobody looked; "can't tell" means somebody looked and could not see.

## 5. Running it (operator)

**Before the first volunteer**
1. Choose the people. Brief them (section 2 and 3 above) and give them the notice in section 6. Get a yes in a message you keep.
2. Make tokens. They are random; the code is a pseudonym you choose (no names):

   ```bash
   python scripts/fieldlog_ops.py token v01 v02 v03
   ```

   Keep your own private list of which code is which person, **outside the repository**. Send each volunteer only their own token, in a direct message, not in a group.
3. On the host, set `FIELDLOG_TOKENS` to the printed `code:token,code:token` line, set `FIELDLOG_ADMIN_TOKEN` to a different long random value, then redeploy or restart. Without `FIELDLOG_TOKENS` logging stays **off**.
4. Check the server:

   ```bash
   python scripts/fieldlog_ops.py status https://YOUR-SITE/ingest
   ```

   It reports whether logging is on, how many tokens loaded (a token under 16 characters is refused and counted), the number of sites, and whether the disk is durable.
5. Open the page yourself with a test code (`test01`) and log one entry. **Entries from codes beginning `test` are excluded from every analysis** (section 8) and are reported by count.

**While running**
- Export after **every logging day** while the host's disk is not durable (a free host wipes it on a restart, a redeploy, and probably when it sleeps):

  ```bash
  FIELDLOG_ADMIN_TOKEN=... python scripts/fieldlog_ops.py export https://YOUR-SITE/ingest --out exports/
  ```

  The file is written only if its row count equals the server's count before and after the download. Keep the printed SHA-256 with the file. Exports stay out of Git (`.gitignore`).
- To stop one person, remove their entry from `FIELDLOG_TOKENS` and restart. Their old entries remain in the log; their phone keeps its queue and gets "not accepted" on sync.
- Wrong-token guesses are slowed but a valid token is never refused because of them.
- Do not edit exports. Corrections are new entries or an analysis rule, never an edit.

## 6. What volunteers are told (notice) and what is kept

Read or send this before a volunteer starts.

> **CityPulse field log.** You will record what you see at road points during rain: passable, not passable, or can't tell, a depth estimate if blocked, and the time on your phone. The server stores that with a code that stands for you (not your name), the time the server received it, and, only if you use "Another place", the position of that spot to about 10 metres. It does not collect your name, number, photos, or track your movements. The project team uses it for research on which streets become impassable in rain. It is not shown to other people and does not change any route in the app. It is kept on the team's server and exports until the study's analysis is finished and then deleted or reduced to counts. You can stop at any time and can ask for your entries to be deleted by sending the team your code. Taking part is voluntary.

- **What is stored per entry:** entry id, site id, state, observed time (phone clock), depth band, the volunteer code, received time, lag, a client label, and the rounded position for "Another place".
- **What is not stored:** names, phone numbers, photos, free text, the phone's position for listed sites. The field log itself does not record IP addresses; the host's own web logs may, and the team does not control them.
- **Volunteer code.** A code plus a time and a place is personal data about that volunteer, because the operator can link the code to a person. The linking list lives only with the operator.
- **Deletion on request.** The service has no delete function by design (the log is append-only). Delete a volunteer's rows from the operator's exports and, if the host's disk is persistent, from the daily files on the host. Record the request and the date.
- **Retention.** Until the field analysis in section 8 is written; then delete raw exports or keep counts only. Raw exports are never published and never committed.
- **Legal status: not established.** Whether this notice and handling meet the DPDP Act 2023 has not been checked by anyone qualified. **[UNVERIFIED]** The team is not lawyers. Before recruiting anyone outside the team, the owner should ask the institution whether the study needs ethics approval (`docs/ethics/`).

## 7. What counts as a good pilot

From `00_START_HERE/NEXT_STEPS.md`: three people can log ten sites within 24 hours of rain, and logging does not lag by more than a day. Here that is measured as: on at least one day when the ADR-027 rule reads `watch` or `active` for the Chennai box, three or more volunteers together log at least 10 distinct listed sites, and the 95th percentile of `lag_seconds` on those entries is under 24 hours. Meeting it says the process works. It says nothing about the roads.

## 8. Pre-registered analysis

Fixed on 6 October 2026, **before any field data exists and before any analysis code is written.** Choices below are design choices, not derived from data; they were made to keep the first report small and hard to bend. If a rule has to change, the change is a new section dated and signed here with the reason, never an edit. Negative and null results are reported in full.

**Data and exclusions (fixed).**
- Source: the checked CSV exports. Duplicates by `entry_id` count once.
- Excluded, and reported by count: volunteer codes starting `test`; entries with `site_id = adhoc` from the site-based analyses A2 to A4 (they are reported separately in A1).
- Nothing else is excluded. No entry is dropped because it looks wrong or inconvenient.
- Time zone for days: Asia/Kolkata calendar date of `observed_at`.

**Definitions.**
- A **resolved entry** has `state` of `passable` or `not_passable`.
- A **site-day** is a (listed site, calendar day) with at least one resolved entry. It is `not_passable` if any resolved entry that day is `not_passable`, otherwise `passable`. It is **mixed** if both appear that day; mixed site-days are counted, reported, and treated as `not_passable` in the primary analysis. A sensitivity analysis uses the last resolved entry of the day instead.

**Reporting threshold (fixed).** Rates and comparisons (A2 to A5) are reported only if there are at least 5 distinct calendar days with a resolved entry, at least 100 site-days and at least 3 volunteers. Below that, only counts are reported and no conclusion is drawn.

**Analyses.**
- **A1. Descriptive, always reported.** Entries, volunteers, listed sites with at least one entry, entries per volunteer per day, the share `unknown`, the share mixed, the median, 95th percentile and maximum of `lag_seconds`, ad hoc entry count.
- **A2. How often is a candidate site not passable?** Share of site-days `not_passable`, overall and for `High` and `Very High` hazard category, with 95% intervals by **bootstrap resampling of calendar days** (consecutive entries on a day are not independent), 10,000 resamples, seed 20260918.
- **A3. Does the category separate the sites?** Difference in `not_passable` share, `Very High` minus `High`, with the same interval. Reported as "separates" only if the interval excludes 0; otherwise as "no evidence of separation". The category is the 2015 map's own label and is not verified.
- **A4. Does the satellite rain rule track the street?** For each site-day take the highest ADR-027 level over the 00, 06, 12 and 18 UTC reads that fall in that local day, computed from the IMERG archive exactly as `scripts/imerg_rule_replay.py` does (result: `data/results/2026-10-05-imerg-event-rule-replay/`). Report the table of levels (`dry`, `watch`, `active`) by site-day state, and the `not_passable` share per level with the day-bootstrap interval. The rule is said to track the street only if the share is higher at `active` than at `dry` with an interval for the difference that excludes 0. This ignores the roughly 6 hours of lag a live service has (ADR-027); it tests whether the level matches the street, not whether it is early enough.
- **A5. How often do two observers disagree?** Pairs are two resolved entries at the same site by different volunteers within 30 minutes. Report the number of pairs, percent agreement and Cohen's kappa. Fewer than 20 pairs: counts only.
- **A6. The pilot criterion** in section 7: met or not met.

**Not done in this analysis (each would be a new ADR with a new pre-registration):** mapping sites to router edges; judging or fitting the belief, the prior or any threshold; using field data to change ADR-027; training anything on it.

**Known biases to state beside every result:** volunteers log when and where they choose, rain days and reachable places are over-represented, observers differ, the clock is the phone's, sites are unverified candidates, and the candidate list comes from the same 2015 map whose usefulness is being asked about.
