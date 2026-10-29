# Building our own Chennai street-flood dataset: fragmented sources (29 Oct 2026)

Goal: find data that already exists in pieces (news lists, PDFs, portal layers, one-off surveys, crowd forms) and that, joined together,
gives what the project lacks: **time-stamped, street- or subway-level evidence of flooding and passability**, with depth where possible.
Everything below was found with web searches on 29 Oct 2026. "Opened" means I read the page itself; "search summary" means I saw it only
in search results and it needs checking. Nothing has been downloaded.

## What we already hold (not repeated below)

OSM road graph; GCC hazard zones; the 2015 OpenCity corpus (stagnation points, hotspots, crowd-sourced flooding, NRSC zone); CFM-DSS
layers (drains, 2015 and 2020 hotspots, flood spot heights, NRSC 2015 extent, stations); India flood events and GFD maps; Copernicus 90 m
DEM; yearly Chennai crash totals; the 31-subway watchlist; IMERG rain; NYC FloodNet.

## 1. Sources, by what they give us

### A. Depth at a place (the scarcest thing)

| Source | What it is | Time-stamped? | Access | Status |
|---|---|---|---|---|
| [OpenCity: Chennai Inundation Points with Depth of Inundation](https://data.opencity.in/dataset/chennai-flooding-data/resource/ceddf53f-03c0-4866-8ba8-5e84c8007a85) | GCC points with inundation depth in inches; KML, 107 KB; credit Vaidyanathan R. | Event year **not stated** | Public domain | **Opened.** Not in our corpus. Download needs approval |
| CFM-DSS `hotspots_gcc_2015` (have) | 327 points with depth classes (<2 ft, 2–3, 3–5, >5 ft) | 2015 event | Held locally | Already used in C4 step 1; **not yet in the replay corpus** |
| CFM-DSS `flood_spot_heights` (have) | 368 points with inundation height in feet | Event unclear | Held locally | Not yet used |
| [IIT Madras chennaiwaterlogging.org](https://citizenmatters.in/iitm-team-log-flood-water-levels-chennai-residents-forecasting-37955) | Residents logged depths (about 2,000; ~1,200 on 4–5 Dec 2023), with photos; via website and WhatsApp | Yes, per report | Not public; ask the team (Prof. Balaji Narasimhan is quoted) | Search summary |
| [Care Earth Trust form](https://citizenmatters.in/chennai-flooding-gis-mapping-care-earth-trust-36212) | Google Form: date, time, location, water level | Yes | Not public; ask | Search summary; may predate Michaung |
| [Adyar floodplain depth measurements](https://link.springer.com/10.1007/s44327-026-00238-8) | Field depths used to validate a model for the 2005 and 2015 floods | Per event | Ask authors | Search summary |

### B. Closures and reopenings (passability, the label we most need)

| Source | What it is | Notes |
|---|---|---|
| News live lists of closed subways, e.g. [TNM, Michaung](https://www.thenewsminute.com/tamil-nadu/chennai-rains-list-of-subways-closed-and-traffic-updates), [TNM, 6 Dec 2023](https://www.thenewsminute.com/tamil-nadu/chennai-floods-traffic-subways-and-train-updates-for-dec-6), [DT Next](https://www.dtnext.in/news/chennai/cyclone-michaung-8-people-died-subways-roads-closed-cm-stalin-inspects-relief-camps-in-chennai-752471), "[subways not waterlogged](https://www.thenewsminute.com/tamil-nadu/chennai-rains-list-subways-are-not-waterlogged-169445)" | Named subways closed or open at a stated time; counts change through the day (17, then 14, then 11 in Dec 2023) | **The most valuable fragmented source.** Nobody has assembled a subway-by-subway closure timeline across events. Also gives **negative** labels ("not waterlogged"), which our corpus has none of. The event miner (ADR-030) was built for this |
| Greater Chennai Traffic Police posts on X | Closures, diversions, reopenings | X API is paid and scraping breaks its terms; capture by hand during events (time, text, link) |
| Road closures from lake releases (e.g. Manjambakkam–Vadaperumbakkam Road, Puzhal release, Dec 2023) | Closures with a cause | In the same news items; pair with reservoir data (D) |
| GCC daily figures ("471 places waterlogged", "1,212 complaints in 24 h", 21–22 Oct 2026) | Counts per event, sometimes named areas | [newstodaynet](https://newstodaynet.com/2026/10/22/chennai-logs-1212-rain-complaints/), [DT Next](https://www.dtnext.in/news/chennai/overnight-heavy-rain-spell-in-chennai-over-1200-complaints-received-in-24-hours-says-gcc-commissioner). Location-level complaints only via RTI, anonymised |
| [Groundsource](https://zenodo.org/records/18647054) (Google, Mar 2026) | 2.6 million flood events extracted from news by Gemini, >150 countries | **Opened:** CC BY 4.0, one 667 MB Parquet; India coverage and location precision not stated. A ready-made index of dated Chennai flood mentions, if it covers India. Needs approval to download |
| [GDELT](https://blog.gdeltproject.org/gdelt-worlds-largest-event-dataset-now-publicly-available-in-google-bigquery/) | Geocoded news events, free in BigQuery | Useful only to *find* Chennai articles; the facts still come from the articles |

### C. Rain at street-to-ward scale

| Source | Notes |
|---|---|
| **VIT Chennai's own IMD weather station and rain gauge** ([VIT page](https://chennai.vit.ac.in/automatic-weather-station-aws-automatic-rain-gauge-system-arg/)) | Our university; an internal request is the cheapest path to hourly gauge data |
| IMD AWS/ARG portal | [Locked to the public since about May 2025](https://www.downtoearth.org.in/amp/story/climate-change/imd-locking-up-its-awsarg-data-portal-hampers-public-weather-alerts-experts); RTI is the route |
| [OpenCity Chennai daily rainfall 1991–2023](https://data.opencity.in/dataset/chennai-rainfall-data/resource/chennai-daily-rainfall-data-from-1991-2023) | Public domain, daily; good for event calendars, too coarse for hours |
| Weather bloggers' personal stations ([chennairains.com](https://www.chennairains.com/bloggers-rain/), [Citizen Matters](https://citizenmatters.in/evolution-of-weather-blogging-in-chennai-21704)) | Scattered gauges across the city; ask the bloggers. Official network is about 12 stations |
| CFM-DSS / Real-Time Flood Forecasting system (live since Oct 2025: [water level recorders, gate sensors](https://amkresourceinfo.com/chennai-becomes-indias-first-city-to-launch-a-fully-operational-real-time-flood-forecasting-and-spatial-decision-support-system/)) | Live only; **not archived by anyone** we found. Polling and keeping our own archive would create a dataset that does not exist (needs your approval for a third-party server) |

### D. Water arriving from upstream

| Source | Notes |
|---|---|
| [Kaggle: Chennai Water Management](https://baselight.app/u/kaggle/dataset/sudalairajkumar_chennai_water_management) (CMWSSB) | Daily storage of Poondi, Cholavaram, Red Hills (Puzhal), Chembarambakkam; 6,182 rows; last update unclear |
| [OpenCity lake levels since 2003](https://data.opencity.in/dataset/chennai-lake-leves-since-2003) | Monthly |
| [OpenCity ward-wise monthly groundwater depth 2021–2023](https://data.opencity.in/dataset/chennai-ward-wise-groundwater-levels) | How saturated the ground is before an event, per ward |

### E. Drains, terrain and buildings (why a street floods)

| Source | Notes |
|---|---|
| OpenCity ward storm-water-drain base maps (e.g. [ward 96](https://data.opencity.in/dataset/7aefb28f-db8a-4bca-8f0f-51b4a3702902/resource/26fe1e28-43be-4c09-9f49-534ddda887e0/download/ward-96.pdf)) | Per-ward PDFs from a World Bank-funded flood forecasting project, surveyed Feb 2021, **with flow direction and invert levels**. Digitising them gives a street-drain layer nobody has as data. Caveat: residents found drains missing on the ground ([NGT filing](https://www.greentribunal.gov.in/sites/default/files/news_updates/24420_1.pdf)) |
| [OpenCity Chennai Flows, 5 to 200-year return periods](https://data.opencity.in/dataset/chennai-flooding-data) | Modelled flood layers; a better prior than hazard categories, if usable |
| [Google Open Buildings 2.5D Temporal](https://developers.google.com/earth-engine/datasets/catalog/GOOGLE_Research_open-buildings-temporal_v1?hl=en) | Building presence and height, yearly 2016–2023, CC BY 4.0 or ODbL; paved area per catchment |
| GCC drone survey of 44 canals ([DT Next](https://www.dtnext.in/news/chennai/chennai-corporation-uses-drones-to-survey-44-canals-ahead-of-northeast-monsoon)) | Not public; ask |

### F. Flood extent from space

| Source | Notes |
|---|---|
| NRSC Michaung maps ([part 1](https://www.nrsc.gov.in/sites/default/files/pdf/DMSP/TN_7_12_2023_Michaung_Cyclone1of2.pdf), [part 2](https://www.nrsc.gov.in/sites/default/files/pdf/DMSP/TN_7_12_2023_Michaung_Cyclone2of2.pdf)) | RISAT-1A, 7 Dec 2023, as PDFs; "for official use", rain and paddy water counted as flood; digitise with care |
| [UNOSAT flood waters over Chennai, 4 Dec 2015](https://cloud.csiss.gmu.edu/uddi/dataset/geodata-of-flood-waters-over-chennai-area-tamil-nadu-state-india-december-04-2015) | Geodata via the Centre for Humanitarian Data |
| [NISAR L-band, free since 20 Jul 2026](https://asf.alaska.edu/notices/nisar-l-band-data-now-publicly-available/) | **Time-sensitive:** the first monsoon NISAR sees is the one happening now. L-band sees through cloud and partly into built-up areas. Pair passes with our ground reports this season |
| Sentinel-1 | Free; we would produce Chennai event extents ourselves (none found for Michaung) |

### G. Crashes and signals (secondary use cases)

| Source | Notes |
|---|---|
| [RTI reply hosted by CAG](https://www.cag.org.in/sites/default/files/database/RTI_black%20spot_scrb-.pdf): state-highway black spots **with GPS**, 2012–2015 | Search summary; only point-level crash locations found |
| [OpenCity Tamil Nadu crash reports](https://data.opencity.in/dataset/groups/tamil-nadu-road-accidents-reports) | Check for coordinates (our copy is yearly totals) |
| Parliament answers on black spots (e.g. [Lok Sabha](https://eparlib.nic.in/bitstream/123456789/2972860/1/AU3188.pdf)) | Sometimes list spots by name |
| Chennai ITS: [165 adaptive junctions, incident detection at 58 locations](https://www.deccanherald.com/india/tamil-nadu/centre-approves-rs-530-crore-for-intelligent-transport-system-in-chennai-4051930) | Junction list and timings via GCTP or RTI; would validate C8 |
| MTC: [3,233 buses, 602 routes, all GPS-tracked](https://www.thenewsminute.com/tamil-nadu/chennai-bus-app-finally-launched-mtc-heres-all-you-need-know-163624) | No public API; a new app is due. Bus diversions during floods are public in news and could be logged |

### H. Social media (for labels and images)

| Source | Notes |
|---|---|
| [Chennai 2015 flood image posts, 2,676](https://arxiv.org/pdf/2509.08003) | Twitter images, Dec 2015; check the licence and where it is released |
| [CrisisNLP / CrisisBench](https://qcai.qcri.org/datasets/crisisnlp) | Whether Chennai is included is unconfirmed |
| [Chong et al. 2018](https://www.engineering.org.cn/engi/EN/10.1016/j.eng.2018.03.010): Chennai flood tweets with geotags | Data release unknown; ask authors |

## 2. The dataset to build: one table, many sources

Name (working): **Chennai Street Flood Evidence (CSFE)**. One row per observation; the sources above are only feeders.

| Field | Meaning |
|---|---|
| `obs_id`, `event_id` | Unique id; the flood event it belongs to (events defined by rain dates, e.g. `2023-12-michaung`) |
| `t_observed`, `t_precision` | When the condition was true, and how precise the time is (minute, hour, day, event-only) |
| `place` | Point, OSM way, subway id (watchlist), or ward; snapped to graph edges both directions |
| `kind` | `closed`, `open`, `depth`, `waterlogged`, `not_waterlogged`, `complaint_count`, `extent` |
| `value`, `unit` | e.g. depth 45 cm; complaint count 1,212 |
| `source_type` | official, news, crowd, sensor, satellite |
| `source_ref`, `archived_at` | URL plus a saved copy's hash (pages change); **facts only, never the article text** |
| `licence`, `extraction` | Licence of the source; manual, event miner, digitised |
| `reviewer`, `confidence` | Who checked it (the miner's review queue already enforces this) |

Rules: split train and test **by event**, never by row; keep negatives (`open`, `not_waterlogged`); no personal data (no names, faces or
number plates in stored photos); depth stays in the source's unit plus a converted value.

## 3. What to do first (cheapest proof first)

1. **This week, while it is fresh:** the 21–22 Oct 2026 rain is the first real event since the tooling was built. Collect every news
   subway list, GCC figure and GCTP post with timestamps into CSFE, by hand or with the event miner. Same for any rain in Nov–Dec.
2. **Downloads that need your approval** (all small or free): OpenCity depth points (107 KB KML), OpenCity drain maps (PDFs), Kaggle
   reservoir levels, Groundsource (667 MB).
3. **Back-fill past events from news:** Dec 2015, Nov 2021, Dec 2023 (Michaung), Oct 2024, Oct 2026. Subway timelines first.
4. **Requests (only you or a faculty member can send these):** IIT Madras waterlogging logs; Care Earth form data; VIT's IMD
   gauge data; GCC complaint locations (RTI, anonymised); ITS junction list; MTC GPS access.
5. **Satellite this season:** list NISAR and Sentinel-1 passes over Chennai during Nov–Dec 2026 rain and archive them with our ground
   reports for the same days.
6. **Digitise** the drain PDFs for the C4 boxes first (T. Nagar, Mylapore, Anna Nagar, Adyar), to test whether drains explain the
   hotspots the DSM could not.

## 4. Limits

One day of searching; search summaries can be wrong (the ones marked "search summary" need checking). Licences for news content, X posts
and crowd photos restrict reuse: store extracted facts with links, not copies. Any server polling, download or outreach waits for your
approval.
