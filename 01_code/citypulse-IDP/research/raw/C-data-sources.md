# Strand C — Real, Obtainable Hazard & Mobility Data Sources (Chennai / Tamil Nadu / India)

**Research Agent C · CityPulse AI · compiled 2026-09-11**

Scope: every data source the CityPulse AI pipeline (`INGEST → ROUTE → EXPLAIN → PRESENT → OFFLINE`)
could plausibly consume, judged not on whether it exists but on whether **three students at VIT
Chennai can actually obtain it inside a 7-week build window**.

Every URL below was fetched or search-verified on 2026-09-11 unless explicitly marked
`⚠️ UNVERIFIED`. I did **not** invent endpoints. Where documentation named an endpoint but I could
not exercise it, that is stated.

---

## 0. Verification status legend

| Mark | Meaning |
|---|---|
| ✅ **VERIFIED** | Page fetched; content confirms the claim |
| 🟡 **DOC-VERIFIED** | Official documentation confirms it, but I could not exercise the endpoint (auth wall, 403 from research proxy) |
| ⚠️ **UNVERIFIED** | Could not confirm — treat as a lead requiring the team's own check |

Three fetches were blocked by the research environment's proxy/robots handling rather than by the
source itself and are marked accordingly: `chennaiwaterlogging.org`, `tnsdma.tn.gov.in`,
`cmwssb.tn.gov.in`, `data.humdata.org`. These are almost certainly reachable from a normal browser
in Chennai; the team should re-check them directly.

---

## 1. MASTER SOURCE TABLE

### 1.1 Base map, road network and routing

| # | Source | What it provides | Spatial resolution | Cadence / latency | Access method | Auth | Cost | Licence / terms | Student-obtainable? |
|---|---|---|---|---|---|---|---|---|---|
| C1 | **Geofabrik — India / Southern Zone extract** <br>https://download.geofabrik.de/asia/india/southern-zone.html ✅ | Full OSM extract covering Tamil Nadu, incl. all Chennai roads, buildings, waterways, POIs | Vector, OSM native (sub-metre nominal, real accuracy varies) | **Daily** rebuilds; also `.osc.gz` minutely/daily diffs and dated monthly snapshots back to Jan 2022 | Plain HTTPS bulk download: `.osm.pbf` (531 MB), shapefile (1.1 GB), GeoPackage (1.2 GB), `.poly` boundary | None | Free | **ODbL 1.0**, "created by OpenStreetMap Contributors". Public files strip contributor metadata (usernames/changesets) for EU privacy compliance | ✅ **Yes — trivial. This is the spine of the project.** Download today. |
| C2 | **OpenStreetMap Overpass API** <br>https://overpass-api.de/api/interpreter <br>docs: https://dev.overpass-api.de/overpass-doc/en/preface/commons.html ✅ | Ad-hoc queries for tagged features (bridges, culverts, underpasses, hospitals, fire stations, `flood_prone=yes`) | Vector / OSM native | Near-live (minutes behind the OSM edit stream) | HTTP GET/POST, Overpass QL; JSON/XML/CSV out | None (optional user key) | Free | ODbL (data); public-instance fair-use policy | ✅ **Yes, for development.** ❌ **No, as a production backend** — the commons doc explicitly lists *"Setting up an app for more than just OSM mappers and relying on the public instances as backend"* as problematic. Fair use: ≤~10,000 requests/day and ≤~1 GB/day; 180 s default timeout, 512 MiB default memory, HTTP 429 on denial, HTTP 504 on resource exhaustion. **Use Overpass to build a static cache once; never call it per user request.** |
| C3 | **HOT / HDX OSM road exports — India** <br>https://data.humdata.org/dataset/hotosm_ind_roads 🟡 (403 from research proxy; dataset page indexed and listed under HOT's 2,591-dataset HDX org) | Pre-cut OSM road layers for India (also `hotosm_ind_south_roads` / `_west_` / `_east_` / `_central_` / `_north_`) | Vector | Periodic re-export (not daily) | HDX CKAN download, GeoJSON/SHP/GPKG | None | Free | ODbL (derived from OSM) | ✅ Yes. Convenience layer only — Geofabrik (C1) is fresher. Useful because HOT applies a humanitarian schema that is easier to ingest than raw PBF. |
| C4 | **OSRM (self-hosted)** <br>https://project-osrm.org | Routing engine over OSM; contraction hierarchies, `/route`, `/table`, `/match`, `/nearest` | n/a (consumes C1) | n/a | Docker, self-hosted | None | Free | BSD-2-Clause (engine); data stays ODbL | ✅ Yes. Prepares Tamil Nadu extract in minutes on a laptop. **Caveat for CityPulse:** OSRM's CH preprocessing bakes in edge weights — dynamic per-request hazard penalties need either the MLD algorithm (`osrm-partition`/`osrm-customize`, supports cheap re-customisation) or a custom engine. This is an architectural decision, not a data one. |
| C5 | **GraphHopper (self-hosted)** <br>https://github.com/graphhopper/graphhopper | Routing engine; **custom_model** JSON lets you apply per-request edge multipliers without re-preprocessing | n/a | n/a | Java, self-hosted | None | Free (Apache 2.0 core) | Apache 2.0 | ✅ Yes — and **better suited than OSRM to hazard-weighted routing**, because `custom_model` supports runtime `priority`/`speed` rules keyed on arbitrary edge attributes. Recommend GraphHopper over OSRM for this project. |
| — | **OSM road quality in Chennai** | Kontur's global OSM road-completeness methodology (`OSM length / (OSM length + filtered Facebook AI-detected road length)`) is published, but the blog gives **no numeric figure for India or Chennai**; figures are only viewable in their interactive Disaster Ninja layer. <br>https://www.kontur.io/blog/osm-road-completeness/ ✅ | | | | | | | ⚠️ **UNVERIFIED for Chennai specifically.** Qualitative expectation: Chennai's arterial and collector network in OSM is good (long-standing local mapping community, `openstreetmap.in`); *named* minor residential lanes, one-way tagging, and turn restrictions are the weak points — which matters a lot for an EMS-routing claim. **The team must do its own spot-check** against a sample of known Chennai junctions before claiming route realism in the paper. |

---

### 1.2 Flood

| # | Source | What it provides | Spatial resolution | Cadence / latency | Access method | Auth | Cost | Licence / terms | Student-obtainable? |
|---|---|---|---|---|---|---|---|---|---|
| C6 | **Google Flood Forecasting API** <br>https://developers.google.com/flood-forecasting ✅ <br>methods: https://developers.google.com/flood-forecasting/rpc/google.research.floodforecasting.v1 ✅ | Real-time **riverine** flood forecasts + current flood severity status. Methods confirmed: `SearchGaugesByArea`, `BatchGetGauges`, `GetGauge`, `GetGaugeModel`, `BatchGetGaugeModels`, `QueryGaugeForecasts`, `QueryLatestFloodStatusByGaugeIds`, `SearchLatestFloodStatusByArea`, `SearchLatestFlashFloods`, `SearchLatestSignificantEvents`, `GetSerializedPolygon` (returns KML inundation polygons) | Gauge-point + inundation polygons; **riverine, not pluvial** | Flood statuses "updated several times a day"; forecasts issued up to several times a day, 7-day horizon, 1–24 h between forecast points ✅ | REST/RPC, Google Cloud project + API key | **Waitlist → approval → reply with GCP Project ID → enable API → API key** ✅ | **Free** ✅ | Data under **CC BY 4.0** ✅ (attribution to Google) — note this is *far* friendlier than Google Maps Platform terms | ⚠️ **HIGH RISK for a 7-week timeline.** Google's own help page states: *"Access to the flood forecasting API is currently limited to pilot participants"* and *responses may take several months*. India **is** covered by Flood Hub ✅. **Plan: apply on day 1, assume you will not get it, and scrape/screenshot the public Flood Hub UI for the demo narrative instead.** The base hostname is not published outside the approval email — ⚠️ do not hardcode a guessed endpoint. |
| C7 | **Copernicus GloFAS via CEMS Early Warning Data Store** <br>API base: `https://ewds.climate.copernicus.eu/api` ✅ <br>setup: https://ewds.climate.copernicus.eu/how-to-api ✅ | Global river discharge forecast + reanalysis (`cems-glofas-historical`, forecast & reforecast datasets) | ~0.05° (~5 km) — **too coarse for street-level urban routing** | Daily forecast runs; reanalysis historical | Python `cdsapi` client (https://github.com/ecmwf/cdsapi ✅), NetCDF/GRIB | Free registration; personal access token in `~/.cdsapirc` | Free | Must accept per-dataset Terms of Use before download; Copernicus licence is generally free reuse with attribution | ✅ **Yes — obtainable in a day.** But be honest: 5 km grid cells tell you the Adyar/Cooum basins are in flood, not which street is impassable. Use as a **regional risk prior**, not a routing input. |
| C8 | **Open-Meteo Flood API** <br>https://open-meteo.com/en/docs/flood-api ✅ <br>terms: https://open-meteo.com/en/terms ✅ | GloFAS-derived river discharge, served as a simple JSON REST API — **no registration at all** | Same ~5 km GloFAS grid | Daily | `GET https://flood-api.open-meteo.com/v1/flood?latitude=..&longitude=..&daily=river_discharge` | **None** | Free | ⚠️ **Non-commercial only**: *"You may only use the free API services for non-commercial purposes"* — explicitly excludes apps with subscriptions or ads. Data under **CC-BY 4.0**. Limits: <10,000 calls/day, 5,000/hour, 600/minute ✅ | ✅ **Yes — the fastest possible flood signal, zero friction.** Academic/educational use is explicitly permitted. Becomes a licensing problem the moment CityPulse is commercialised. |
| C9 | **NASA GPM IMERG (Early / Late / Final Run)** <br>https://gpm.nasa.gov/data/imerg ✅ <br>Early: https://www.earthdata.nasa.gov/data/catalog/ges-disc-gpm-3imergde-07 ✅ | Satellite precipitation — the best *rainfall driver* available globally without Indian-government permission | **0.1° (~11 km)**, 30-minute product | **Early Run ≈ 4 h latency**; Late ≈ 14 h; Final ≈ 3.5 months | GES DISC HTTPS/OPeNDAP; also on **AWS Open Data** (https://registry.opendata.aws/nasa-gpm3imergdf/ ✅) and **Google Earth Engine** (`NASA/GPM_L3/IMERG_V07` ✅) | Free **NASA Earthdata Login** (5-minute signup) | Free | Open / public domain, attribution requested | ✅ **Yes.** Earth Engine is the least painful route (no file wrangling). 11 km grid — again a *prior*, not a street-level signal. |
| C10 | **Central Water Commission (CWC) flood forecasts** <br>Portal family: `india-water.gov.in` / `ffs.india-water.gov.in` | Level & inflow forecasts at ~330 CWC forecast stations nationwide; the new unified **"C-FLOOD"** system was announced in 2025 (https://www.deccanherald.com/india/centre-unveils-c-flood-a-unified-flood-forecasting-system-3612789 ✅) | Gauge stations on major rivers | Typically daily/sub-daily bulletins | **No documented public API.** HTML/PDF bulletins + a WebGIS viewer; Twitter/X `@CWCOfficial_FF` ✅ | n/a / scrape | Free to view | Government of India data; reuse terms not clearly published for these bulletins | ⚠️ **Partially.** Scraping is technically feasible but brittle and of doubtful ToS standing. **Critically: CWC's Tamil Nadu coverage is on large rivers, not Chennai's urban Cooum/Adyar/Buckingham Canal drainage.** Low value for this project despite high apparent relevance. Related research resource: **GUARDIAN** sub-daily Indian river discharge dataset, published in *Scientific Data* (https://www.nature.com/articles/s41597-024-03923-8 ✅) — peer-reviewed, citable, offline. |
| C11 | **ISRO Bhuvan — Disaster Services / Flood** <br>https://bhuvan-app1.nrsc.gov.in/disaster/disaster.php ✅ <br>Flood EWS: https://bhuvan-app1.nrsc.gov.in/fews/ ✅ | Satellite-derived flood inundation maps (historical + event-based), Spatial Flood Early Warning System, cyclone/landslide/forest-fire layers | Satellite footprint (tens of metres for SAR-derived inundation) | Event-driven, not continuous | WebGIS viewer; **OGC WMS** exposed ("WMS Manager", "OGC web services") ✅; Open Data Archive | Login required for some layers ✅ | Free ("free data, open data" keywords) ✅ | ⚠️ Specific licence terms not clearly published on the disaster page — must read NRSC's disclaimer | 🟡 **Probably yes, with friction.** Indian-institution email helps. WMS is the practical integration path (add as a basemap layer in the demo). Known community frustration with obtaining bulk Bhuvan flood data (https://groups.google.com/g/datameet/c/eyg-T6w6Gl4 ✅). |
| C12 | **OpenCity — "Chennai Flooding Data" (GCC)** <br>https://data.opencity.in/dataset/chennai-flooding-data ✅ | 🔑 **The single most Chennai-specific dataset found.** Resources: *Chennai Inundation Points with Depth of Inundation (inches)*; *Chennai Flooding Points in 2015*; *Chennai Flows — 5/10/25/50/100/200-year return periods*; *Chennai Flood Hazard Zones Map* (High/Moderate/etc.) | Point + polygon, city-scale | Static / historical (last updated **2025-11-27**) | Direct KML download from CKAN, e.g. `https://data.opencity.in/dataset/022dd080-e927-40d7-897d-adf3ee98ad69/resource/e61afe07-0f52-4be9-bdf3-5eb0f62b2ed6/download/7f29da20-6621-4b49-b0cf-28b9d1de232b.kml` ✅ | **None** | Free | **"Other (Public Domain)"**, marked Open-Data compliant ✅. Source org: Greater Chennai Corporation | ✅ **Yes — download today.** This is your flood-hazard prior *and* your offline evaluation ground truth. |
| C13 | **OpenCity — "Chennai Floods 2015 Data"** <br>https://data.opencity.in/dataset/chennai-floods-2015-data ✅ | 7 KML resources: *GCC Stagnation Locations in 2015*; *Chennai 2015 Crowd-sourced Flooding Locations*; *GCC Area Flood Hotspots (Chennai SDSS)*; Tiruvallur / Vellore / Kancheepuram district hotspots; ***Chennai 2015 Floods Inundation Zone (as per NRSC)*** | Point + polygon | Static (updated 2025-11-25) | Direct KML download | None | Free | "Other (Public Domain)" ✅; source: GCC & crowd-sourced | ✅ **Yes.** **This is the backbone of the fallback plan (§4)** — real, georeferenced, crowd-sourced Chennai flood reports you can replay as a synthetic live stream. |
| C14 | **HDX — Geodata of Flood Waters Over Chennai Area, Dec 2015** <br>https://data.humdata.org/dataset/geodata-of-flood-waters-over-chennai-area-tamil-nadu-state-india-december-04-2015 🟡 | Satellite-derived flood water extent shapefile (`FL20151123IND_shp.zip`) for the 2015 Chennai event | Satellite-derived polygon | Static | HDX CKAN download | None | Free | HDX standard open terms (varies by contributor — check on the page) | 🟡 Yes (page indexed; 403 from research proxy only). Good independent validation layer against C13's NRSC inundation zone. |
| C15 | **India Flood Inventory — Impacts (IFI-Impacts), 1967–2023** <br>https://zenodo.org/records/11275211 ✅ <br>DOI 10.5281/zenodo.11275211 <br>code: https://github.com/hydrosenselab/India-Flood-Inventory ✅ | National multi-source geospatial flood event database (IMD-sourced, manually digitised): main inventory + district-level flooded area + district flood impacts | District-level | Static, v4 (Aug 2025) | Zenodo download, 3 CSVs, 1.9 MB | None | Free | **CC BY 4.0** ✅ | ✅ **Yes.** Peer-reviewed (*Natural Hazards*, https://link.springer.com/article/10.1007/s11069-021-04698-6 ✅). Use for temporal priors ("how often does Chennai district flood in NE monsoon?") and for a citable baseline in the paper. |
| C16 | **RiskMap India — `riskmap.in` (MIT Urban Risk Lab / CogniCity OSS)** <br>https://urbanrisklab.org/riskmap ✅ <br>API docs: https://urbanriskmap.github.io/cognicity-api-docs/ ✅ | Citizen flood reports + social-media harvesting + sensor levels. **Piloted in Chennai 2017–2019** ✅, listed as operational | Point reports, city-scale | Real-time when active | REST JSON; GeoJSON, TopoJSON **and CAP XML** on the `/floods` endpoint ✅. Endpoint families: `cards`, `cities`, `feeds`, `floods`, `infrastructure`, `reports` ✅. Public endpoints unauthenticated; protected ones need `x-api-key` or JWT ✅ | None for public endpoints | Free | Open-source (CogniCity OSS) | ⚠️ **Verify liveness before depending on it.** The Chennai pilot is described as 2017–2019 past-tense; the sibling Indonesian instance was handed off in 2019. **Exact `riskmap.in` base path for the data API is ⚠️ UNVERIFIED — do not hardcode.** But: **CogniCity OSS is the single best architectural model for CityPulse's crowdsourced-ingest layer**, and it is Chennai-proven. Even if the API is dark, read the code. |
| C17 | **PetaBencana.id (Jakarta) — reference model** <br>https://docs.petabencana.id/master-1 ✅ | Not a Chennai source; the canonical proof that CAP-emitting, chatbot-fed, city-scale crowdsourced flood mapping works at national scale | — | — | Open source on GitHub | — | Free | Open source | ✅ Use as **design precedent and related-work citation**, not as a data feed. Its `/floods` → CAP XML pattern is exactly what CityPulse's ingest layer should speak. |
| C18 | **Chennai Water Logging (IIT Madras crowdsourcing)** <br>https://chennaiwaterlogging.org/ ⚠️ (robots/DNS blocked from research env) | Crowdsourced waterlogging reports for Chennai, run out of IIT Madras ✅ (corroborated: https://news.careers360.com/iit-madras-enables-crowdsourcing-track-waterlogging-in-chennai) | Point reports | Event-driven (monsoon) | ⚠️ unknown — likely web form + map, API unknown | ⚠️ unknown | ⚠️ unknown | ⚠️ unknown | 🟡 **Highest-value local partnership lead.** VIT Chennai → IIT Madras is a realistic academic approach. **Action: email the project lead in week 1 asking for a research data-sharing arrangement.** Even a one-off CSV of historical reports is worth more to this project than any global API. |
| C19 | **Chennai Rains & Waterlogging Datajam (OpenCity, Jan 2024)** <br>https://opencity.in/chennai-rains-and-waterlogging-datajam-jan-2024/ ✅ | Community datajam outputs + the civic-data network around Chennai flooding | — | Static | Web | None | Free | Open | ✅ Yes — mainly a **map of who holds what** and a route to local collaborators. |
| C20 | **Fathom — India / Chennai Flood Hazard (via OasisHub)** <br>https://oasishub.co/dataset/india-chennai-flood-hazard-full-package-fathom ✅ | Commercial high-res probabilistic flood hazard (fluvial + pluvial) for Chennai | ~30 m or better | Static hazard layers | Commercial licence | Account | 💰 **Paid** | Commercial | ❌ **No.** Listed only so the team knows what the "proper" commercial layer costs and can say in the paper why they didn't use it. Some Fathom tiers have academic programmes — ⚠️ unverified, long lead time. |

---

### 1.3 Weather, heat and air quality

| # | Source | What it provides | Spatial resolution | Cadence / latency | Access method | Auth | Cost | Licence / terms | Student-obtainable? |
|---|---|---|---|---|---|---|---|---|---|
| C21 | **IMD API platform** <br>https://api.imd.gov.in/ ✅ <br>reference: https://api.imd.gov.in/public/api_reference.html ✅ <br>policy: https://mausam.imd.gov.in/responsive/apis.php ✅ | 🔑 **The richest India-specific hazard API that exists.** Endpoints confirmed in the official reference: `/api/v1/cityforecast`, `/cityforecastloc`, `/subdivision_rainfall_forecast`, `/state_district_rainfall_forecast`, `/current_wx`, **`/districtnowcast`**, **`/stationnowcast`**, **`/aws_data`** (AWS/ARG automatic stations), **`/districtwarning`** (5-day colour-coded warnings), `/subdivisionwarning`, `/districtrainfall`, `/staterainfall`, `/basinqpf` (river-basin QPF), `/portwarning`, `/seabulletin`, `/coastalbulletin`, `/cyclone_track`, **`/cyclone_wind`** (GeoJSON MultiPolygon wind zones), **`/cyclone_cou`** (GeoJSON cone of uncertainty), `/sunmoon` ✅ | District & station level — **genuinely useful granularity for Chennai** | Nowcasts hourly; warnings 5-day; AWS sub-hourly | REST JSON/GeoJSON | 🔴 **Required.** I fetched `https://api.imd.gov.in/api/v1/districtwarning` and received **HTTP 401** ✅ — the API is *not* open despite the reference page not documenting an auth scheme. IMD requires **IP whitelisting** via https://api.imd.gov.in/public/index.php ✅ and organisational onboarding via the nodal officer **Dr. Sankar Nath, Sc-E — sankar.nath@imd.gov.in, +91-9821832587** ✅ | Free (no fee published) | Terms require **proper attribution to IMD** and **client-side caching during peak weather events** ✅ | 🟡 **THE critical ask — apply in week 1.** Requires a letter from VIT Chennai and a fixed egress IP for whitelisting. Realistic lead time: weeks, not days. Serverless/dynamic-IP hosting will fail whitelisting — **budget for a fixed-IP VM.** Risk: 401 persists past the demo. |
| C22 | **IMD Mausam public site & radar** <br>https://mausam.imd.gov.in/ ✅ | Chennai DWR radar imagery, warnings, nowcast bulletins as web pages/images | Radar ~1 km | ~10 min for radar | HTML/image scrape | None | Free | ⚠️ Reuse terms for scraped imagery unclear | 🟡 Fallback if C21 whitelisting fails. Radar *images* are display-only — you cannot derive a rainfall field from a PNG without heavy assumptions. Attribution mandatory. |
| C23 | **Open-Meteo Weather Forecast API** <br>https://open-meteo.com/ ✅ | Hourly forecast: precipitation, temperature, apparent temperature (→ heat index), wind, humidity | ~1–11 km depending on model (ICON/GFS/ECMWF blend) | Hourly, low latency | `GET https://api.open-meteo.com/v1/forecast?latitude=13.08&longitude=80.27&hourly=...` | **None — no API key** ✅ | Free | ⚠️ **Non-commercial only** ✅; data **CC-BY 4.0**; <10k calls/day, 5k/hr, 600/min ✅ | ✅ **Yes, in five minutes. Best effort-to-value ratio of any source in this report.** Explicitly permits "public institutional research" and "educational applications". |
| C24 | **OpenWeather** <br>https://openweathermap.org/price ✅ | Current weather, 5-day/3-hour forecast, **Air Pollution API**, Geocoding | City / ~10 km | Free tier data refreshes **every 2 hours** ✅ | REST JSON | API key (free signup) | **Free tier: 60 calls/min, 1,000,000 calls/month** ✅. One Call API 4.0 separately: 1,000 calls/day free then pay-as-you-go ✅ | Requires visible attribution to OpenWeather ✅; 95% availability SLA | ✅ **Yes.** Commercially usable (unlike Open-Meteo), so it is the better long-term choice — but the 2-hour free-tier refresh is poor for a "2-minute-old flood signal" narrative. **Recommendation: Open-Meteo for the demo, OpenWeather as the commercial-path answer in the viva.** |
| C25 | **CPCB — National Air Quality Index** <br>https://airquality.cpcb.gov.in/AQI_India/ ✅ <br>https://cpcb.nic.in/real-time-air-qulity-data/ ✅ | Official Indian AQI + PM2.5/PM10/NO₂/SO₂/CO/O₃ from CAAQMS stations incl. Chennai | Station point | Hourly ✅ | Web dashboard. **⚠️ The data.gov.in resource page for "Real time Air Quality Index from various locations" currently states: _"The API for this resource does not exist. Please click the 'Request API' button"_** ✅ — i.e. the widely-cited data.gov.in AQI API is **not live at this resource** | data.gov.in API key if/when provisioned | Free | OGD India / NDSAP terms | 🟡 **Do not assume the CPCB API works.** Community write-ups describe an undocumented CPCB endpoint (https://medium.com/@atharva-again/cpcbs-aqi-api-everything-you-need-to-know-41f5eff85c5a ✅) — ⚠️ **unverified and not officially sanctioned; I will not reproduce a guessed endpoint here.** Use C26/C27 instead. |
| C26 | **OpenAQ v3** <br>https://docs.openaq.org/ ✅ <br>key: https://docs.openaq.org/using-the-api/api-key ✅ | Aggregated global air-quality measurements incl. Indian CPCB stations | Station point | Near-real-time (ingest lag varies by provider) | REST JSON, `X-API-Key` header | **Free API key** (registration) ✅ | Free | Open data; aggregator terms | ✅ **Yes — same day.** Cleanest path to Chennai AQI without fighting CPCB. |
| C27 | **WAQI / AQICN** <br>https://aqicn.org/api/ ✅ | Real-time AQI feed, station + city level, geo & search endpoints | Station / city | Real-time | `https://api.waqi.info/feed/<city>/?token=<token>` ✅ | Free token from the AQICN data-platform page ✅ | Free ✅ | 🔴 **Restrictive**: mandatory attribution to WAQI **and to the originating EPA**; **data may not be sold, used in paid applications, or redistributed as cached data** ✅; for-profit use requires explicit agreement, nonprofits require prior notification. Quota: 1,000 req/s ✅ | ✅ Yes for academic use. ⚠️ The **no-cached-redistribution** clause directly conflicts with CityPulse's *"pre-cached spatial graphs for offline use"* design. **Do not cache WAQI data on-device.** |

---

### 1.4 Traffic

| # | Source | What it provides | Spatial resolution | Cadence / latency | Access method | Auth | Cost | Licence / terms | Student-obtainable? |
|---|---|---|---|---|---|---|---|---|---|
| C28 | **Google Maps Platform** (Routes / Roads / Directions) <br>ToS: https://cloud.google.com/maps-platform/terms ✅ <br>service terms: https://cloud.google.com/maps-platform/terms/maps-service-terms ✅ | Best-in-class live traffic and routing for Chennai | Segment level | Live | REST | API key + billing account | Free monthly credit then paid | 🔴 **See §5 — this is the project's single biggest licensing landmine.** | ❌ **Recommend: do not use at all.** See the full clause analysis in §5.1. |
| C29 | **TomTom Traffic & Routing APIs** <br>https://docs.tomtom.com/pricing ✅ <br>https://developer.tomtom.com/traffic-api/documentation/tomtom-maps/v1/product-information/introduction ✅ | Traffic **Flow** (segment speeds), **Traffic Incidents** (accidents, closures, jams as point/linestring incidents), Routing, Snap-to-Roads, Traffic Stats | Road-segment level; India coverage good in metros | Live (~1 min class) | REST JSON/XML + raster/vector tiles | Free API key, self-service | ✅ **Free tier verified**: Traffic **Incident Details 2,500/month**; Traffic **Flow & Incident tiles 200,000/month**; Traffic Segment Data 20,000/month; **Routing API 20,000/month**; Map tiles 200,000/month; Matrix/Snap-to-Roads/Reachable Range 2,500/month ✅ | ⚠️ Storage/caching restrictions **not stated on the pricing page** — must read the full TomTom terms. Assume no-persistent-storage unless proven otherwise. | ✅ **YES — this is the realistic live-traffic source.** Self-service signup, no sales call, generous enough for a demo. 2,500 incident calls/month = ~80/day, so poll every ~18 minutes or use the tile endpoints (200k/month) for the visual layer. **Recommended traffic provider.** |
| C30 | **HERE Location Services** <br>https://docs.here.com/traffic-api/docs/introduction-to-here-traffic-api-v7 ✅ | Traffic Flow + Incidents v7, Routing v8, Matrix | Segment level | Live | REST JSON | Free developer key | Freemium tier exists (figures vary across secondary sources — ⚠️ confirm current limits on HERE's own pricing page before committing) | Commercial terms; caching restrictions apply | 🟡 Yes, as a **second opinion / redundancy** to TomTom. Do not build on it without reading the current free-tier terms directly. |
| C31 | **Mapbox** <br>https://www.mapbox.com/pricing ✅ <br>Product Terms (2025-10): https://cdn.prod.website-files.com/609ed46055e27a02ffc0749b/68dddd2815cb3d82685f0096_Mapbox%20Product%20Terms%20(October%201,%202025).pdf ✅ | Vector tiles, Directions, Map Matching, Navigation SDK, **offline map downloads** | Segment | Live | REST + SDKs | Free key | Generous free tier then paid | Commercial terms; **offline caching is an explicitly supported feature** (unlike Google) | 🟡 Yes. **Relevant to CityPulse specifically because Mapbox's Navigation SDK supports sanctioned offline tile packs**, which Google's terms do not. But Mapbox tiles are Mapbox's Produced Work — mixing them with your own ODbL-derived routing graph is fine, but you cannot re-derive data from them. |
| C32 | **Bing / Azure Maps** | Traffic flow & incidents | Segment | Live | REST | Key | Free tier | Microsoft commercial terms | 🟡 Possible, not recommended — no advantage over TomTom for India, and the Bing Maps consumer API line has been in migration to Azure Maps. ⚠️ Current India traffic quality unverified. |

---

### 1.5 Emergency / EMS / civic alerting

| # | Source | What it provides | Spatial resolution | Cadence / latency | Access method | Auth | Cost | Licence / terms | Student-obtainable? |
|---|---|---|---|---|---|---|---|---|---|
| C33 | **NDMA SACHET — National Disaster Alert Portal** <br>https://sachet.ndma.gov.in/ ✅ <br>RSS/CAP page: https://sachet.ndma.gov.in/CapFeed ✅ (page exists; **listed feed URLs could not be extracted** — the page rendered without exposing them to the fetcher, and direct curl was blocked by the research proxy) | 🔑 **India's official CAP (Common Alerting Protocol) alert aggregator** — IMD, CWC, INCOIS, state SDMAs incl. TN. Exactly the standard CityPulse's ingest layer should speak | Polygon/area-based CAP alerts, state & district | Event-driven, near-real-time | RSS/CAP feeds; an "RSS User Guide (PDF)" for agency integration is linked ✅; dashboard at https://sachet.ndma.gov.in/Dashboard ✅ | ⚠️ Registration requirement unclear from the page | Free | Government of India | 🟡 **HIGH PRIORITY, PARTIALLY UNVERIFIED.** ⚠️ **I could not verify the exact feed URLs and will not guess them.** **Action for the team: open https://sachet.ndma.gov.in/CapFeed in a browser, copy the real feed URLs, and download the RSS User Guide.** Contact: controlroom@ndma.gov.in, +91-11-26701728 ✅. If this works it is the best civic hazard feed in the entire report — official, CAP-standard, Tamil Nadu-inclusive, free. |
| C34 | **GDACS (Copernicus / JRC)** <br>https://www.gdacs.org/feed_reference.aspx ✅ | Global multi-hazard alerts. **Verified feed paths**: `xml/rss_fl_7d.xml` (floods, last week), `xml/rss_fl_3m.xml`, `xml/rss_tc_7d.xml` / `rss_tc_3m.xml` (cyclones), `xml/rss_eq_24h.xml` / `rss_eq_48h_low.xml` / `rss_eq_48h_med.xml` / `rss_eq_3M.xml` / `rss_eq_5.5_3m.xml` (earthquakes), `xml/rss_24h.xml` and `xml/rss_7d.xml` (all events) ✅ | Country/event level — **too coarse for routing** | **Updated every 6 minutes** ✅ | Plain RSS over HTTPS | **None** ✅ | Free | JRC/Copernicus open terms | ✅ **Yes, in minutes — zero friction.** The ideal **"is the ingest pipeline alive?"** heartbeat feed and a genuine cyclone-warning source for the Bay of Bengal. Python clients exist (`gdacs-api` on PyPI ✅). |
| C35 | **TNSDMA / TN-SMART (Tamil Nadu SDMA)** <br>https://tnsdma.tn.gov.in/ ⚠️ (robots/DNS blocked from research env) <br>rainfall map: https://tnsdma.tn.gov.in/app/webroot/tnsdma_map/ ✅ (indexed) | Reported by local observers to publish **hourly station rainfall and 35+ years of historic station data openly** — described as best-in-India for public transparency (https://x.com/praddy06/status/1975167590755598409 ✅, a credible TN weather account but **not an official source**) | Station-level, statewide | Hourly | Web map; ⚠️ underlying JSON endpoints unknown | ⚠️ unknown | Free | ⚠️ unknown | 🟡 **HIGH PRIORITY, MUST BE CHECKED LOCALLY.** If the hourly rainfall map is backed by a JSON endpoint (webroot map apps usually are), this is **the best Chennai-relevant live rainfall feed available to this team** — Indian, hourly, station-level, no whitelisting. **Action: open the map in a browser, open DevTools → Network, and record the actual XHR endpoints.** Also: "TN Alert" mobile app. |
| C36 | **Greater Chennai Corporation** <br>https://data.opencity.in/dataset?organization=greater-chennai-corporation ✅ | GCC's published datasets mirrored on OpenCity (see C12/C13) | Ward/point | Static | CKAN download | None | Free | Public domain (per OpenCity) | ✅ Yes for the historical layers. ❌ **No live GCC hazard API was found.** GCC's operational flood monitoring is internal. |
| C37 | **CMWSSB — Chennai reservoir / lake levels** <br>https://cmwssb.tn.gov.in/previous-lake-level ⚠️ (blocked from research env; page indexed ✅) <br>mirror: https://numerical.co.in/numerons/collection/5e127ba3545c9d1c18f23221 ✅ ("Live storage, water levels and rainfall data for Chennai Lakes") | Daily levels/storage for Poondi, Cholavaram, Red Hills, Chembarambakkam — **the four reservoirs whose releases caused the 2015 disaster** | 4 point locations | Daily | ⚠️ Likely an HTML table; scrape required | None | Free | ⚠️ Government page, terms unstated | 🟡 **Yes via scraping.** Only 4 values/day — trivially cacheable and hugely explanatory for the LLM layer ("Chembarambakkam is at 94% and releasing; the Adyar corridor is high-risk"). **High narrative value per unit of effort.** Also on data.gov.in: https://www.data.gov.in/catalog/chennai-metropolitan-water-supply-and-sewerage ✅ |
| C38 | **108 Ambulance / GVK EMRI (Tamil Nadu)** <br>https://www.emri.in/108-emergency/ ✅ | Ambulance dispatch and response operations across TN | — | — | **No public API. No open dataset.** | Institutional MoU only | — | Proprietary/operational; patient data | ❌ **NO. Treat as unobtainable.** Published research using EMRI data (e.g. https://www.sciencedirect.com/science/article/abs/pii/S1744165X15000797 ✅) exists only through formal institutional collaborations. Even aggregate response-time data would need an MoU and ethics clearance — far beyond 7 weeks. **For the demo, simulate EMS demand; in the paper, cite EMRI literature for realistic response-time distributions rather than claiming data access.** |
| C39 | **112 / ERSS (Emergency Response Support System)** <br>https://ndma.gov.in/Capacity_Building/Ops_Comm/IT_Comm_Project ✅ | National 112 emergency dispatch backbone | — | — | **No public API found** | Government only | — | Restricted | ❌ **No.** ⚠️ I could not complete a dedicated search on ERSS APIs (web-search budget exhausted) — but no public developer surface is known to exist, and none should be assumed. |
| C40 | **Waze for Cities Data Program** <br>https://support.google.com/waze/partners/answer/10453062 ✅ <br>https://www.waze.com/wazeforcities ✅ | Two-way exchange: partners give road-closure/construction data, receive Waze jam & incident alerts for their polygon | Segment/point | Near-real-time | Partner Hub feed (GeoRSS/JSON — ⚠️ format not confirmed on the eligibility page) | Partner agreement | Free to eligible partners | Partner T&Cs | ❌ **NO for a student team.** Eligibility is explicit: *"You can apply for Waze for Cities if you represent a government agency or a private road operator"* ✅ — **universities are not listed**. Only viable route: GCC or TN Highways applies and sub-shares under a research agreement. Not a 7-week path. |
| C41 | **Ushahidi (self-hosted)** <br>https://github.com/ushahidi/platform ✅ | Open-source crowdsourced incident-reporting platform with a REST API | Point reports | Real-time (your own users) | Self-host | Your own | Free (open source) | AGPL-family open source ⚠️ (exact licence has been a documented ambiguity: https://github.com/ushahidi/platform/issues/3383 ✅ — **check before embedding**) | ✅ **Yes — and this is how you get a *real* crowdsourced feed.** You cannot obtain someone else's live crowd reports, but you can stand up your own in a day and seed it with the team + a campus pilot. CogniCity (C16) is the better-fitting alternative. |

---

### 1.6 Open academic datasets for offline evaluation & reproducibility

| # | Source | What it provides | Access | Licence | Value to CityPulse |
|---|---|---|---|---|---|
| C42 | **Global Flood Database v1 (2000–2018)** <br>https://developers.google.com/earth-engine/datasets/catalog/GLOBAL_FLOOD_DB_MODIS_EVENTS_V1 ✅ <br>code: https://github.com/cloudtostreet/MODIS_GlobalFloodDatabase ✅ <br>HydroShare mirror: https://www.hydroshare.org/resource/6461528501c14f7c9d6b10d20dd4f657/ ✅ | 913 MODIS-derived flood event footprints incl. Indian events | Earth Engine / HydroShare | Open, published in *Nature* | Offline validation of hazard-zone predictions; reproducible and citable |
| C43 | **Dartmouth Flood Observatory — Global Large Flood Events (1985–2016)** <br>https://gee-community-catalog.org/projects/flood/ ✅ | Global flood event catalogue with dates, locations, severity, deaths, displaced | GEE community catalog / DFO | Open academic | Ground-truth event list for replay scenario selection |
| C44 | **Cloud to Street / Microsoft Flood and Clouds (C2S-MS Floods)** <br>https://registry.opendata.aws/c2smsfloods/ ✅ | Sentinel-1/2 flood + cloud labelled chips for ML | AWS Open Data, no auth | Open | If the team wants a learned flood-extent component, this is the training set |
| C45 | **GUARDIAN — sub-daily Indian river discharge** <br>https://www.nature.com/articles/s41597-024-03923-8 ✅ | Extended sub-daily discharge across Indian gauges | *Scientific Data* paper + repository | Open (CC BY) | Offline substitute for the CWC feed you cannot get (C10) |
| C46 | **IFI-Impacts (see C15)** | 1967–2023 district flood events & impacts | Zenodo, CC BY 4.0 | CC BY 4.0 | Temporal priors + baseline |
| C47 | **OpenCity Chennai KMLs (C12, C13)** | Real Chennai flood points, stagnation locations, hotspots, 2015 NRSC inundation zone | CKAN, public domain | Public domain | 🔑 **The replay corpus for the fallback plan (§4)** |
| C48 | **Geofabrik dated snapshots (C1)** | Monthly OSM snapshots back to Jan 2022 ✅ | HTTPS | ODbL | 🔑 **Reproducibility anchor** — pin one snapshot date so results are re-runnable a year from now |

---

## 2. RECOMMENDED MINIMUM VIABLE DATA STACK

Obtainable **in days, by three students, with no institutional negotiation**. Everything in Tier 0
can be running before the end of week 1.

### Tier 0 — Zero-friction, no auth, get it today

| Layer | Source | Why |
|---|---|---|
| **Road graph** | Geofabrik Southern Zone `.osm.pbf` (C1), pinned to a fixed snapshot date | ODbL, daily, complete for Chennai |
| **Routing engine** | GraphHopper self-hosted (C5) with `custom_model` for hazard weights | Runtime edge penalties without re-preprocessing — this is what makes hazard-aware routing actually implementable in 7 weeks |
| **Static flood prior** | OpenCity GCC flood hazard zones + return-period flows + inundation depth points (C12) | Public domain, Chennai-specific, real |
| **Historical hazard corpus** | OpenCity Chennai 2015 stagnation + crowd-sourced flooding + NRSC inundation zone (C13) | Public domain; becomes the replay stream |
| **Live rain / heat** | Open-Meteo forecast API (C23) | No key, no signup, CC-BY, hourly |
| **Live regional flood** | Open-Meteo Flood API (C8, GloFAS-derived) | No key; coarse but live and honest |
| **Multi-hazard alert heartbeat** | GDACS `xml/rss_fl_7d.xml` + `xml/rss_tc_7d.xml` (C34) | 6-minute cadence, zero auth, proves the CAP-style ingest path |
| **Air quality** | OpenAQ v3 (C26) | Free key, covers Chennai CPCB stations |

### Tier 1 — One short form or one scrape away (week 1–2)

| Layer | Source | Effort |
|---|---|---|
| **Live traffic incidents + flow** | **TomTom** (C29) — 2,500 incident calls/month + 200k tiles/month free | Self-service key, ~15 min |
| **Reservoir state** | CMWSSB lake levels (C37) — 4 values/day | A 30-line scraper; enormous explanatory payoff for the LLM layer |
| **TN station rainfall** | TNSDMA / TN-SMART map XHR endpoints (C35) | Inspect the network tab; if a JSON endpoint exists this becomes your best local signal |
| **Satellite rainfall** | IMERG Early Run via Earth Engine (C9) | Earthdata/GEE account, ~1 h |

### Tier 2 — Apply in week 1, assume failure, celebrate if granted

| Layer | Source | Realistic probability |
|---|---|---|
| **Official Indian warnings/nowcast** | IMD API whitelisting (C21) — needs VIT letter + fixed egress IP | ~40% inside 7 weeks |
| **Official CAP alerts** | NDMA SACHET feeds (C33) — may be genuinely open; verify the URLs first | ~60% |
| **Riverine forecast** | Google Flood Forecasting API waitlist (C6) | ~10% (Google says "several months") |
| **Local crowdsourced ground truth** | IIT Madras Chennai Water Logging (C18) — academic email | ~35%, but highest value if it lands |

### Explicitly out of scope — do not spend time on

Google Maps Platform (C28 — see §5.1) · Waze for Cities (C40 — ineligible) · 108/GVK EMRI (C38 —
requires MoU + ethics) · 112/ERSS (C39) · Fathom commercial hazard (C20) · CWC scraping (C10 — wrong
rivers for Chennai).

### What this stack honestly supports — and what it does not

**Supports:** a hazard-weighted router over a real Chennai OSM graph; live rainfall, AQI, traffic
incidents and reservoir state; a genuine confidence-decay model driven by real timestamps; an LLM
explanation layer with real named features ("Chembarambakkam at 94%, Adyar corridor flow above the
25-year return period, TomTom reports a closure on Kotturpuram Bridge"); and full offline operation
from a cached OSM graph.

**Does not support, and the paper must say so:** true street-level *live* inundation. No obtainable
source gives "this lane is 40 cm deep right now" for Chennai. Every live flood signal in the MVP
stack is either ≥5 km grid (GloFAS/IMERG) or a static historical prior. **The honest framing is:
CityPulse fuses a high-resolution static hazard prior with coarse live forcing and user reports —
not a live high-resolution flood sensor network.** Overclaiming here is the most likely thing to
sink the project at review.

---

## 3. INGEST CONTRACT RECOMMENDATION

Normalise every source above into a **single CAP-like internal schema** before it touches the
routing layer:

```
{ id, source, observed_at, ingested_at, geometry(GeoJSON), hazard_type,
  severity, certainty, confidence_at_ingest, decay_half_life_s, provenance_licence }
```

Two reasons this matters beyond tidiness:
1. **SACHET (C33), PetaBencana (C17) and RiskMap (C16) all already speak CAP** — adopting CAP means
   the "plug in the official feed when the whitelist lands" story is a config change, not a rewrite.
2. **`provenance_licence` must be a first-class field.** It is what lets you programmatically refuse
   to cache WAQI data on-device (C27) or to persist a proprietary traffic incident past its allowed
   window. Licence enforcement in code is a genuinely defensible novelty claim for the paper.

---

## 4. FALLBACK PLAN — replayed / simulated hazard streams

Assume **all** Tier-2 applications fail. The project must still demo and still produce a
reproducible evaluation. This plan is not a consolation prize; it is better science than a live demo
because it is deterministic and re-runnable.

### 4.1 The replay corpus

| Component | Built from | Role |
|---|---|---|
| **Event skeleton** | Chennai 2015 flood: GCC stagnation locations + crowd-sourced flooding points + NRSC inundation zone (C13) | Real georeferenced hazard locations, not invented ones |
| **Hazard severity** | Inundation depth points in inches (C12) | Gives each replayed point a defensible severity |
| **Spatial plausibility envelope** | Flood hazard zones + 5/10/25/50/100/200-year return-period flows (C12) | Constrains synthetic events to hydrologically plausible places |
| **Temporal profile** | IFI-Impacts 1967–2023 district records (C15) + IMERG for the Nov–Dec 2015 window (C9) | Real rainfall→flood timing, so decay curves are calibrated against reality |
| **Independent validation extent** | HDX Dec-2015 Chennai flood-water shapefile (C14) | Held-out check on the inundation footprint |
| **Base graph, pinned** | A single dated Geofabrik snapshot (C48) | Byte-identical re-runs |

### 4.2 The replay harness

Build a `HazardReplayServer` that speaks **exactly the same CAP-like interface** as the live
ingesters and emits events on a virtual clock (`--speed 60x`). Then:

- **Nothing downstream knows the difference.** Same decay scoring, same routing, same LLM prompts.
- **Live vs. replay becomes a runtime flag**, so any Tier-2 feed that lands late drops straight in.
- **Evaluation becomes reproducible**: fixed seed, fixed snapshot, fixed event file → identical
  metrics. State this explicitly in the paper; most student projects cannot make this claim.

### 4.3 Evaluation design that survives having no live feed

1. **Counterfactual routing**: for each of N origin–destination pairs across Chennai, compare
   hazard-naive vs. hazard-aware routes at each replay timestep. Report Δdistance, Δtime, and
   **hazard exposure** (metres of route within an active hazard polygon). This needs no live data
   at all.
2. **Decay-model ablation**: sweep half-life; show exposure vs. detour trade-off curves.
3. **Offline-parity test**: run the same replay with the network disabled; assert the on-device
   route matches the cloud route within a tolerance. **This directly evidences the project's core
   novelty claim** and requires zero external data.
4. **Explanation faithfulness**: check that every LLM-generated justification cites a hazard that
   was actually in the active set at that timestep. An automatable, publishable metric.

### 4.4 Live-demo insurance

Record a **canned 10-minute replay** with the virtual clock and ship it in the repo. Demo days have
bad wifi; a live feed that 404s on stage is worse than an honest replay labelled as such.

---

## 5. LICENSING & LEGAL RISK

### 5.1 🔴 TOP RISK — Google Maps Platform is incompatible with this project. Do not use it.

The brief asked me to check the claim that Google's terms prohibit use in a competing navigation
product. **Verified — the prohibition is real and broader than expected.** From
https://cloud.google.com/maps-platform/terms ✅ (verbatim):

> **3.2.3(d) No Re-Creating Google Products or Features.** "Customer will not use the Services to
> create a product or service with features that are substantially similar to or that re-create the
> features of another Google product or service… For example, Customer will not: … **(iv) combine
> data from the Directions API, Geolocation API, and Maps SDK for Android to create real-time
> navigation functionality substantially similar to the functionality provided by the Google Maps
> for Android mobile app.**"

That clause describes CityPulse's core function almost word for word. Four more clauses compound it:

> **3.2.3(c)(vii)** "Customer will not… **use Google Maps Content to improve machine learning and
> artificial intelligence models, including to train, test, validate or fine-tune the models.**"

— fatal for an LLM-explanation project. Feeding a Google route or traffic incident into a prompt for
evaluation is arguably "test/validate".

> **3.2.3(e) No Use With Non-Google Maps.** "Customer will not use the Google Maps Core Services
> with or near a non-Google Map in a Customer Application."

— CityPulse renders an OSM map. This alone forecloses using Google traffic alongside it.
Reinforced per-API: **§17.2 (Roads API)** and **§19.2 (Routes API)** each state "Customer must not
use Google Maps Content from the [Roads/Routes] API in conjunction with a non-Google map" ✅.

> **3.2.3(a) No Scraping** — no pre-fetching, indexing, storing, resharing or rehosting outside the
> Services; no bulk download of "geocodes, directions, distance matrix results, roads information".
> **3.2.3(b) No Caching** except as permitted by the service terms — and those permit caching
> **only latitude/longitude values, for a maximum of 30 consecutive days** (§4.3 Directions, §17.3
> Roads, §19.3 Routes) ✅.

— irreconcilable with "pre-cached spatial graphs for offline inference".

> **3.2.1(c) High Risk Activities** — customers must not use the Services "for High Risk
> Activities", defined as activities where failure "would reasonably be expected to result in death,
> serious personal injury, or severe environmental damage".

— an emergency-vehicle routing system is squarely in the danger zone of this definition.

**Verdict: keep Google Maps Platform out of the codebase entirely.** Not "use it carefully" — the
offline-caching, ML-training, non-Google-map and re-creation clauses each independently break the
architecture. A single Google API call in a committed notebook is enough to make the project's
licensing story indefensible at review. *(Google's **Flood Forecasting API** (C6) is governed
separately and is **CC BY 4.0** ✅ — that one is fine, if you can get it.)*

### 5.2 ODbL share-alike — the second-order risk

From the OSMF Licence & Legal FAQ (https://osmfoundation.org/wiki/Licence/Licence_and_Legal_FAQ ✅):

- A **Produced Work** (map images, a rendered app UI, a route *shown* to a user) may be licensed on
  your own terms, with attribution.
- A **Derivative Database** (OSM data adapted, modified or enhanced) distributed to third parties
  must be offered under ODbL.
- A **Collective Database** (OSM kept alongside "otherwise independent databases") lets the non-OSM
  parts keep their own licence; **merging** the sources into an integrated whole makes it Derivative
  and triggers share-alike on the combination.

**Concrete consequences for CityPulse:**

1. **Routes returned to users are Produced Works.** Serving routes from an OSM graph does not
   force you to open-source the app. This is settled practice.
2. **🔴 The offline cache is the danger.** CityPulse ships "pre-cached spatial graphs" to devices.
   A GraphHopper/OSRM graph file is a **Derivative Database**, and shipping it to end users is
   *distribution*. **Therefore the on-device graph must be offered under ODbL** with attribution
   and a notice of where to obtain it. Practically: publish the graph-build script + the pinned
   Geofabrik snapshot ID, and state the ODbL offer in the app's about screen. Easy if designed in;
   painful if discovered at submission.
3. **🔴 Do not fuse hazard data into the OSM graph as edge attributes in the distributed artefact.**
   Baking TomTom incidents or WAQI readings onto OSM ways creates a Derivative Database that mixes
   ODbL share-alike with providers whose terms forbid redistribution — **a genuine licence
   deadlock**. **Architectural fix: keep hazards in a *separate* PostGIS layer joined at query time
   (Collective Database), never written into the graph file that ships.** This is the single most
   important design decision in this report.
4. **Attribution is mandatory and must be on the map itself** for interactive apps: "© OpenStreetMap
   contributors".

### 5.3 Per-source licence conflicts with the offline-first architecture

| Source | Clause | Conflict | Mitigation |
|---|---|---|---|
| WAQI/AQICN (C27) | Data "cannot be… redistributed as cached data" ✅ | Direct conflict with device-side caching | Use OpenAQ (C26) for anything cached; WAQI display-only, live-fetch-only |
| Open-Meteo (C8, C23) | "**non-commercial purposes**" only ✅ | Fine for a university project; blocks any commercialisation or ad-supported release | Document this; name OpenWeather (C24) as the commercial migration path |
| TomTom (C29) | Storage/caching terms not stated on the pricing page ⚠️ | Unknown | **Read the full TomTom terms before caching any incident.** Default to TTL-bounded, non-redistributed storage |
| IMD (C21) | Attribution to IMD mandatory; client-side caching *required* during peak events ✅ | None — actually compatible | Credit IMD visibly |
| Google Flood Hub (C6) | CC BY 4.0 ✅ | None | Attribute Google |
| OpenCity GCC KMLs (C12/C13) | "Other (Public Domain)" ✅ | None | Credit GCC/OpenCity as good practice |
| Bhuvan (C11) | Terms unstated ⚠️ | Unknown | Read NRSC disclaimer before redistributing any tile |

### 5.4 Privacy — DPDP Act 2023 + DPDP Rules 2025, applied to "Haven Mode"

**Haven Mode is the highest-risk component in the brief**, because passively inferring a user's
home, work, school and family locations creates a precise profile of a natural person. Under the
DPDP Act this is unambiguously **personal data**, and the inference is **processing**.

Verified position:

- The **DPDP Rules 2025 were notified in November 2025** with an **18-month phased compliance
  period** ✅ (https://static.pib.gov.in/WriteReadData/specificdocs/documents/2025/nov/doc20251117695301.pdf).
  The project therefore sits inside the transition window — but a *deployed* product will not.
- **Notice + consent**: every Data Fiduciary must give a separate, "clear and easy to understand"
  notice stating "the specific purpose for which personal data is collected and used" ✅. Consent
  must be free, specific, informed, unconditional and unambiguous ✅.
- **Consent Managers must be companies based in India** ✅.
- **Failure to maintain reasonable security safeguards carries the highest penalty — ₹250 crore** ✅.
- **Research exemption**: the Act does provide an exemption for processing "for research, archiving
  or statistical purposes (with safeguards)" under **Section 17** ✅. ⚠️ **The precise conditions of
  the §17(2)(b) exemption are set out in the Second Schedule to the Rules, which I could not fetch
  and therefore have NOT verified.** **The team must read the actual statutory text before relying
  on it** — and note that the exemption covers *research* use, **not** a publicly released product.

**What a university project must actually do (concrete checklist):**

1. **Get institutional ethics / IRB clearance at VIT before collecting any real user location
   trace.** Non-negotiable and slow — start in week 1.
2. **Written, specific, revocable consent** for each purpose, separately for (a) routing, (b)
   passive home/work inference, (c) any retention beyond the session. Bundled consent is invalid.
3. **Default Haven Mode OFF.** Opt-in, never opt-out. Inferring someone's home without an explicit
   affirmative act is the exact harm the Act targets.
4. **Process locally.** The brief already promises on-device inference — use it. **If home/work
   inference never leaves the handset, most of the Fiduciary obligations never attach.** This is
   both the strongest privacy design and the strongest paper claim.
5. **If anything must be uploaded**: coarsen it (H3 cell ≥ ~1 km, not a lat/lng), set an explicit
   retention limit, and implement erasure-on-request.
6. **Never persist a raw GPS trace to the server for the demo.** A leaked demo database of three
   students' home addresses is a real, non-hypothetical incident.
7. **Publish a plain-language privacy notice in the repo and in the app.**
8. **Pseudonymise the evaluation set**, and use replayed synthetic trajectories (§4) rather than
   real user traces wherever the evaluation permits — which, for the metrics in §4.3, it entirely
   does.

⚠️ **Not verified:** whether the DPDP Rules' Second Schedule research conditions would cover a
campus pilot with external users; whether "location data" is called out explicitly anywhere in the
Act (the definition of personal data is broad enough that it plainly is covered, but I could not
fetch the statutory text to quote it). **Get a written view from VIT's legal/ethics office rather
than relying on this report.**

### 5.5 Ranked licensing risk register

| Rank | Risk | Severity | Likelihood as pitched | Mitigation |
|---|---|---|---|---|
| 1 | **Any Google Maps Platform use** — breaches 3.2.3(d)(iv) re-creation, 3.2.3(c)(vii) no-ML-training, 3.2.3(e)/17.2/19.2 non-Google-map, 3.2.3(b) no-caching, 3.2.1(c) high-risk | **Critical** | High (it is the default reflex) | **Ban it in the repo.** Use TomTom (C29). Add a CI grep for `googleapis.com/maps`. |
| 2 | **Hazard data fused into the distributed OSM graph** → ODbL share-alike collides with proprietary provider terms | **Critical** | High (it is the obvious implementation) | Keep hazards in a separate PostGIS layer; join at query time (Collective Database) |
| 3 | **Haven Mode home/work inference without ethics clearance or valid consent** | **Critical** (₹250 cr exposure class; reputational for VIT) | Medium-high | On-device only, opt-in, IRB first |
| 4 | **Shipping the on-device routing graph without the ODbL offer** | High | High | Publish build script + pinned snapshot; ODbL notice in-app |
| 5 | **Caching WAQI data on-device** (explicitly forbidden) | Medium | Medium | Use OpenAQ for cached AQI |
| 6 | **Open-Meteo non-commercial clause** | Medium (only on commercialisation) | Low now | Document the OpenWeather migration path |
| 7 | **Scraping CWC / CMWSSB / IMD web pages without stated permission** | Medium | Medium | Prefer official APIs; keep scrape volumes trivial; attribute; ask permission by email |
| 8 | **TomTom storage terms unread** | Medium | Medium | Read the full terms before week 3 |

---

## 6. THINGS I COULD NOT VERIFY — explicit flags

1. **SACHET CAP feed URLs** (C33). Page exists; the specific RSS/CAP endpoint list was not
   extractable and direct fetching was blocked by the research proxy. **Do not guess these URLs.**
2. **TNSDMA / TN-SMART underlying data endpoints** (C35). Site unreachable from this environment.
   The claim of open hourly + 35-year historic station rainfall comes from a credible but
   **unofficial** X account and is unconfirmed.
3. **`riskmap.in` current liveness and its data-API base path** (C16). Documentation confirms the
   instance and the endpoint *families*; the deployed base URL is unverified.
4. **CMWSSB lake-level page structure** (C37) — blocked; scrape feasibility assumed, not proven.
5. **chennaiwaterlogging.org** (C18) — DNS/robots failure; entire access model unknown.
6. **Google Flood Forecasting API hostname** (C6) — not published outside the approval email.
7. **HERE current free-tier limits** (C31) — secondary sources disagree; confirm on HERE's own page.
8. **TomTom caching/storage terms** (C29) — absent from the pricing page.
9. **Bhuvan licence terms** (C11) — not stated on the disaster services page.
10. **OSM road-network completeness figures for Chennai** — no published numeric value found; only
    Kontur's methodology. **Team must measure this themselves.**
11. **DPDP Rules 2025 Second Schedule research-exemption conditions** — PDF not retrievable.
12. **112 / ERSS public API** (C39) — dedicated search not completed (web-search budget exhausted);
    no public developer surface is known to exist.
13. **Bing/Azure Maps India traffic quality** (C32) — not assessed.

---

## 7. WEEK-1 ACTION LIST (ordered by expected value ÷ effort)

1. Download Geofabrik Southern Zone PBF; **record the snapshot date in the repo** (C1, C48).
2. Download all OpenCity Chennai flood KMLs (C12, C13); load into PostGIS. **This is the dataset the
   whole evaluation rests on.**
3. Stand up GraphHopper with a `custom_model` hazard-penalty hook (C5).
4. Wire Open-Meteo forecast + flood and the GDACS flood/cyclone RSS — four endpoints, no keys,
   ingest pipeline alive by day 2 (C8, C23, C34).
5. Register a TomTom developer key; poll Traffic Incident Details every ~18 min to stay inside
   2,500/month (C29).
6. **Submit the IMD whitelisting request** — needs a VIT letterhead request and a fixed egress IP.
   Email Dr. Sankar Nath (C21). *Longest lead time of anything worth having; start it first.*
7. **Open https://sachet.ndma.gov.in/CapFeed in a browser, record the real feed URLs, download the
   RSS User Guide** (C33).
8. **Open the TNSDMA rainfall map with DevTools open and capture the XHR endpoints** (C35).
9. Join the Google Flood Forecasting waitlist; assume it will not land (C6).
10. Email the IIT Madras Chennai Water Logging team requesting historical reports for academic use
    (C18).
11. **Start the VIT ethics/IRB application for Haven Mode.** It will outlast every technical task.
12. Add a CI check that fails the build on any `maps.googleapis.com` reference (§5.5 risk 1).

---

## Sources

[Flood Forecasting API | Google for Developers](https://developers.google.com/flood-forecasting) ·
[Flood Forecasting API v1 RPC reference](https://developers.google.com/flood-forecasting/rpc/google.research.floodforecasting.v1) ·
[Flood Hub — What is the Flood Forecasting API?](https://support.google.com/flood-hub/answer/16364206?hl=en) ·
[Flood Hub — Access & Set-up](https://support.google.com/flood-hub/answer/16364306?hl=en) ·
[Flood Hub — Which countries are covered](https://support.google.com/flood-hub/answer/16508958?hl=en) ·
[Google Flood Forecasting research site](https://sites.research.google/gr/floodforecasting/) ·
[Google Maps Platform Terms of Service](https://cloud.google.com/maps-platform/terms) ·
[Google Maps Platform Service Specific Terms](https://cloud.google.com/maps-platform/terms/maps-service-terms) ·
[Geofabrik — India](https://download.geofabrik.de/asia/india.html) ·
[Geofabrik — Southern Zone](https://download.geofabrik.de/asia/india/southern-zone.html) ·
[Overpass API commons / usage policy](https://dev.overpass-api.de/overpass-doc/en/preface/commons.html) ·
[Overpass API — OSM Wiki](https://wiki.openstreetmap.org/wiki/Overpass_API) ·
[OSMF Licence and Legal FAQ](https://osmfoundation.org/wiki/Licence/Licence_and_Legal_FAQ) ·
[OSMF Attribution Guidelines](https://osmfoundation.org/wiki/Licence/Attribution_Guidelines) ·
[OSM Collective Database Guideline](https://wiki.openstreetmap.org/wiki/Collective_Database_Guideline) ·
[HOTOSM India Roads on HDX](https://data.humdata.org/dataset/hotosm_ind_roads) ·
[HDX — Geodata of Flood Waters Over Chennai, Dec 2015](https://data.humdata.org/dataset/geodata-of-flood-waters-over-chennai-area-tamil-nadu-state-india-december-04-2015) ·
[Kontur — Measuring OSM road completeness](https://www.kontur.io/blog/osm-road-completeness/) ·
[GloFAS — Data Access](https://global-flood.emergency.copernicus.eu/general-information/data-access/) ·
[GloFAS — Data and Services](https://global-flood.emergency.copernicus.eu/general-information/data-and-services/) ·
[CEMS Early Warning Data Store — how to API](https://ewds.climate.copernicus.eu/how-to-api) ·
[ECMWF cdsapi](https://github.com/ecmwf/cdsapi) ·
[Open-Meteo Flood API](https://open-meteo.com/en/docs/flood-api) ·
[Open-Meteo Terms](https://open-meteo.com/en/terms) ·
[Open-Meteo](https://open-meteo.com/) ·
[NASA GPM IMERG](https://gpm.nasa.gov/data/imerg) ·
[GPM IMERG Early V07 at GES DISC](https://www.earthdata.nasa.gov/data/catalog/ges-disc-gpm-3imergde-07) ·
[IMERG on AWS Open Data](https://registry.opendata.aws/nasa-gpm3imergdf/) ·
[IMERG V07 in Earth Engine](https://developers.google.com/earth-engine/datasets/catalog/NASA_GPM_L3_IMERG_V07) ·
[IMD APIs page](https://mausam.imd.gov.in/responsive/apis.php) ·
[IMD API Management portal](https://api.imd.gov.in/) ·
[IMD API reference](https://api.imd.gov.in/public/api_reference.html) ·
[IMD API documentation PDF](https://mausam.imd.gov.in/Forecast/marquee_data/API_doc.pdf) ·
[IMD Mausam](https://mausam.imd.gov.in/index_en.php) ·
[OpenWeather pricing](https://openweathermap.org/price) ·
[OpenWeather full price table](https://openweathermap.org/full-price) ·
[OpenAQ Docs](https://docs.openaq.org/) ·
[OpenAQ API key](https://docs.openaq.org/using-the-api/api-key) ·
[AQICN / WAQI API](https://aqicn.org/api/) ·
[CPCB National Air Quality Index](https://airquality.cpcb.gov.in/AQI_India/) ·
[CPCB real-time air quality data](https://cpcb.nic.in/real-time-air-qulity-data/) ·
[data.gov.in — Real time AQI from various locations](https://www.data.gov.in/resource/real-time-air-quality-index-various-locations) ·
[TomTom pricing](https://docs.tomtom.com/pricing) ·
[TomTom Traffic API introduction](https://docs.tomtom.com/traffic-api/documentation/tomtom-maps/v1/product-information/introduction) ·
[HERE Traffic API v7](https://docs.here.com/traffic-api/docs/introduction-to-here-traffic-api-v7) ·
[Mapbox pricing](https://www.mapbox.com/pricing) ·
[Mapbox Product Terms (Oct 2025)](https://cdn.prod.website-files.com/609ed46055e27a02ffc0749b/68dddd2815cb3d82685f0096_Mapbox%20Product%20Terms%20(October%201,%202025).pdf) ·
[NDMA SACHET portal](https://sachet.ndma.gov.in/) ·
[SACHET CAP/RSS feed page](https://sachet.ndma.gov.in/CapFeed) ·
[SACHET dashboard](https://sachet.ndma.gov.in/Dashboard) ·
[SACHET help](https://sachet.ndma.gov.in/Help) ·
[NDMA IT & Communication Projects](https://ndma.gov.in/Capacity_Building/Ops_Comm/IT_Comm_Project) ·
[GDACS feed reference](https://www.gdacs.org/feed_reference.aspx) ·
[GDACS MHEWS guide 2025](https://www.gdacs.org/documents/2025/GDACS_MHEWS_guide.pdf) ·
[gdacs-api on PyPI](https://pypi.org/project/gdacs-api/) ·
[TNSDMA](https://tnsdma.tn.gov.in/pages/view/) ·
[TNSDMA rainfall map](https://tnsdma.tn.gov.in/app/webroot/tnsdma_map/) ·
[CMWSSB lake level](https://cmwssb.tn.gov.in/previous-lake-level) ·
[data.gov.in — CMWSSB catalog](https://www.data.gov.in/catalog/chennai-metropolitan-water-supply-and-sewerage) ·
[Chennai lake live storage mirror](https://numerical.co.in/numerons/collection/5e127ba3545c9d1c18f23221) ·
[OpenCity — Chennai Flooding Data](https://data.opencity.in/dataset/chennai-flooding-data) ·
[OpenCity — Chennai Floods 2015 Data](https://data.opencity.in/dataset/chennai-floods-2015-data) ·
[OpenCity — GCC datasets](https://data.opencity.in/dataset?organization=greater-chennai-corporation) ·
[OpenCity — Chennai Rains & Waterlogging Datajam 2024](https://opencity.in/chennai-rains-and-waterlogging-datajam-jan-2024/) ·
[Chennai Water Logging (IIT Madras)](https://chennaiwaterlogging.org/) ·
[IIT-M crowdsourcing waterlogging coverage](https://news.careers360.com/iit-madras-enables-crowdsourcing-track-waterlogging-in-chennai) ·
[Bhuvan Disaster Services](https://bhuvan-app1.nrsc.gov.in/disaster/disaster.php) ·
[Bhuvan Spatial Flood Early Warning System](https://bhuvan-app1.nrsc.gov.in/fews/) ·
[NRSC Disaster Management Support](https://www.nrsc.gov.in/nrscnew/Apps_DMS.php) ·
[MOSDAC](https://www.mosdac.gov.in/) ·
[MOSDAC registration](https://www.mosdac.gov.in/registration) ·
[MIT Urban Risk Lab — RiskMap](https://urbanrisklab.org/riskmap) ·
[CogniCity API docs](https://urbanriskmap.github.io/cognicity-api-docs/) ·
[PetaBencana docs](https://docs.petabencana.id/master-1) ·
[Ushahidi Platform](https://github.com/ushahidi/platform) ·
[Ushahidi licence issue #3383](https://github.com/ushahidi/platform/issues/3383) ·
[Waze for Cities — apply](https://support.google.com/waze/partners/answer/10453062?hl=en) ·
[Waze for Cities — about](https://support.google.com/waze/partners/answer/10618477?hl=en) ·
[Waze for Cities](https://www.waze.com/wazeforcities) ·
[GVK EMRI 108](https://www.emri.in/108-emergency/) ·
[EMRI maternal/neonatal transport study](https://www.sciencedirect.com/science/article/abs/pii/S1744165X15000797) ·
[India Flood Inventory — Impacts (Zenodo)](https://zenodo.org/records/11275211) ·
[India Flood Inventory GitHub](https://github.com/hydrosenselab/India-Flood-Inventory) ·
[India flood inventory paper (Natural Hazards)](https://link.springer.com/article/10.1007/s11069-021-04698-6) ·
[GUARDIAN sub-daily Indian river discharge (Scientific Data)](https://www.nature.com/articles/s41597-024-03923-8) ·
[Global Flood Database v1 in Earth Engine](https://developers.google.com/earth-engine/datasets/catalog/GLOBAL_FLOOD_DB_MODIS_EVENTS_V1) ·
[Global Flood Database code](https://github.com/cloudtostreet/MODIS_GlobalFloodDatabase) ·
[Global Flood Database on HydroShare](https://www.hydroshare.org/resource/6461528501c14f7c9d6b10d20dd4f657/) ·
[Dartmouth Flood Observatory events (GEE catalog)](https://gee-community-catalog.org/projects/flood/) ·
[C2S-MS Floods on AWS](https://registry.opendata.aws/c2smsfloods/) ·
[Fathom Chennai flood hazard (OasisHub)](https://oasishub.co/dataset/india-chennai-flood-hazard-full-package-fathom) ·
[Near real-time flood inundation from social media, 2015 Chennai (Geoenvironmental Disasters)](https://link.springer.com/article/10.1186/s40677-021-00195-x) ·
[DPDP Rules 2025 notified (PIB)](https://static.pib.gov.in/WriteReadData/specificdocs/documents/2025/nov/doc20251117695301.pdf) ·
[EY — DPDP Act 2023 & Rules 2025](https://www.ey.com/en_in/insights/cybersecurity/decoding-the-digital-personal-data-protection-act-2023) ·
[DPDPA FAQ](https://www.dpdpa.com/dpdpa-faq.html) ·
[Digital Personal Data Protection Rules 2025 (Wikipedia)](https://en.wikipedia.org/wiki/Digital_Personal_Data_Protection_Rules,_2025) ·
[Tamil Nadu Open Government Data Portal](https://tn.data.gov.in/) ·
[C-FLOOD unified flood forecasting system](https://www.deccanherald.com/india/centre-unveils-c-flood-a-unified-flood-forecasting-system-3612789) ·
[CWC Official Flood Forecast (X)](https://x.com/CWCOfficial_FF)
