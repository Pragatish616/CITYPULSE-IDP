# Subway pilot plan, 9 to 15 October 2026

Written 9 October 2026 while the owner was away. A draft for the owner to change. Nothing here has been done with real volunteers.

**Goal.** By the 15 October gate, show that a few people can log named Chennai subways with times, that the data reaches the team intact,
and that it can be read at a glance (the subway board). That is a *process* result. It says nothing yet about which subways flood.

## What the gate can and cannot be answered with

`00_START_HERE/NEXT_STEPS.md` says: live feed obtained, continue the startup track; no feed, the startup track is killed and field
labels continue as research. The council meant a feed *from the city* (barrier states, flood meters, sensors). Today:

- **GCC's barrier and sensor states:** not obtained. The public flood-monitor layer list has no subway or barrier layer (ADR-031). The one
  live-data request that was approved returned HTTP 404 (wrong path), so the water-level layers are untested. Nothing has been sent to GCC's
  control centre or the traffic police.
- **Our own volunteers** are a manual, small feed. Whether that satisfies the gate is **the owner's call**. The honest reading is that it does
  not: it proves we can collect labels, not that anyone supplies them for a fee. The startup track's real test is the buyer signal
  (a written commitment naming a rupee figure), which no volunteer data can replace.

## Before anyone logs (the operator, about one day)

1. **Confirm positions.** Copy `data/watchlist/2026-10-09/CHECKSHEET.md`. Two people check at least 30 rows on the map links (21 have a pin; 10 have none). Fix or remove any position more than 100 m out. Record who and when. Then re-run `python scripts/build_subway_list.py` after updating the rules in it.
2. **Decide storage.** On Render's free tier the log is lost on a restart, a redeploy and probably when the service sleeps. Either attach a persistent disk or database (needs an account only the owner can create), or export after every logging day and keep each file with its checksum.
3. **Deploy.** Render does not auto-deploy. After the owner pushes and deploys, set `FIELDLOG_TOKENS` and `FIELDLOG_ADMIN_TOKEN` in the host's environment settings (never in the repository).
4. **Make tokens** (they are random; the code is a pseudonym):

   ```bash
   python scripts/fieldlog_ops.py token v01 v02 v03
   ```

   Send each volunteer only their own token, privately. Keep the code-to-person list outside the repository.
5. **Check the server:**

   ```bash
   python scripts/fieldlog_ops.py status https://citypulse-idp.onrender.com/ingest
   ```

   It should say logging is on, 3 or more tokens loaded, 433 sites (31 subways). It will warn that storage is not durable until you attach a disk and set `FIELDLOG_DURABLE=1`.
6. **Brief the volunteers** with `docs/FIELD_PROTOCOL.md` sections 2, 3 and 6 (safety, what to tap, the notice). Get a yes in a message you keep. Ask the institution whether outside volunteers need ethics approval before recruiting beyond the team.
7. **Install on each phone.** Open `https://citypulse-idp.onrender.com/ingest/fieldlog/`, paste the token once, switch the phone to automatic date and time.

## Dry run (any dry day this week)

Each volunteer logs 3 assigned subways once, at the site. These are the dry-day controls the protocol asks for (section 4), so they are real data, not a rehearsal. They also show:

- whether the volunteer could find each subway from its name (the 10 with no position are the test);
- the phone-to-server delay (`lag_seconds`);
- whether the export and the board work on real entries.

## Every logging day

```bash
FIELDLOG_ADMIN_TOKEN=... python scripts/fieldlog_ops.py export https://citypulse-idp.onrender.com/ingest --out exports/
python scripts/subway_board.py exports/fieldlog-export-<time>.csv --out exports/board.html
```

`exports/` is git-ignored. The export refuses to write a file whose row count does not match the server's. Keep the printed SHA-256. The board shows the newest observation per subway and its age, flags observers who disagree, and lists subways nobody has logged ("No observation").

## On a rain day

- Volunteers log every assigned subway they pass, including "can't tell". Nobody enters water or stands in the road (protocol section 2).
- Once a week, on a day with no rain for 24 hours, each assigned subway is logged once (the control).
- Twice a month two volunteers log the same subway within 30 minutes without seeing each other's answer.
- The operator exports the same evening and reads the board.

## What to report at the gate

Only what was observed, as counts, with what is missing stated next to it:

| Report | Source |
|---|---|
| Volunteers who logged, entries, subways with at least one entry (of 31; of the 16 GCC road/rail) | the board summary (`board.json`) |
| Phone-to-server delay: median, 95th percentile, longest | `board.json`, `lag_seconds` |
| Share of entries "can't tell" | the export |
| Whether the NEXT_STEPS pilot criterion was met: 3 people, 10 sites, within 24 h of rain (protocol section 7) | the export, with the rain days from ADR-027's rule |
| Check-sheet result: positions checked, how many were within 100 m | the filled check sheet |

Do **not** report a share of subways found blocked, or compare rain days with dry days, unless the reporting threshold in `docs/FIELD_PROTOCOL.md` section 8 and the addendum 8a is met. With a few volunteers in one week it will not be.

## Risks

- **Storage loss** on the free host: export daily; do not rely on the server's copy.
- **No rain** before 15 October: the pilot then shows the process only. That is still a result worth stating.
- **Phone clocks** wrong: the page warns; the export keeps both the phone time and the arrival time.
- **A token leaks:** remove it from `FIELDLOG_TOKENS` and restart; old entries stay.
- **Volunteer safety and privacy:** the protocol's safety rules and notice apply; legal status under the DPDP Act is not established.

## What the operator must decide

1. Who the volunteers are and who runs the check sheet.
2. Persistent storage, or daily exports only.
3. Whether to spend the second approved flood-monitor request (needs the correct endpoint path first) and whether to email GCC's control centre and the traffic police about barrier and sensor states.
4. How to treat a volunteer feed at the gate (above).
5. Whether the board may ever leave the team.
