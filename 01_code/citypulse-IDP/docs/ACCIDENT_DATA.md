# Accident data for Chennai: what exists (searched 11 October 2026)

**Result: no public, real, location-level and dated accident dataset for Chennai was found.** Everything open is yearly or district totals, and the one geocoded dataset named below says it is partly synthetic. A model of where accidents happen on the road network cannot be trained, or its accuracy checked, on what is publicly available today. This page lists what was looked at so that nobody repeats the search, and what would change the answer.

Pages were read through a web fetch tool; **no data file has been downloaded**. Where the tool could not show a page's content, that is stated.

| Source | What it holds | Location? Dates? | Licence | Verdict |
|---|---|---|---|---|
| [Chennai Road Crashes Data, OpenCity](https://data.opencity.in/dataset/chennai-road-crashes-data) (publisher: Greater Chennai Police; source given as tnsta.gov.in; updated 9 Feb 2026) | CSV `chennai-road-crashes-1998-2025.csv`, **1.4 KiB**: one row per **year**, columns YEAR, Fatal Accidents, Fatal Killed, Grievous Injury (accidents, injured), Minor Injury (accidents, injured), Non Injury, Total Accidents, Total persons involved ([resource page](https://data.opencity.in/dataset/chennai-road-crashes-data/resource/29162b87-f1a7-4011-b309-b14d904f9a7d)) | No location. Year only | "Other (Public Domain)" | Real and official, but **yearly totals only**. Good context; useless for routing |
| [Tamil Nadu Road Crashes 1993-2025, same dataset](https://data.opencity.in/dataset/chennai-road-crashes-data/resource/c1fe08c4-9871-4c0b-b79b-c446f24f2c03) | CSV, **1.7 KiB**, yearly state totals | None | Public domain | Same |
| [Tamil Nadu Road Accidents Reports, OpenCity](https://data.opencity.in/dataset/tamil-nadu-road-accidents-reports) (Tamil Nadu State Transport Authority) | District-wise accidents and deaths 2021 to 2023 (CSV) and a 2023 analysis (PDF) | District only | Public domain | Totals only |
| [Greater Chennai Police datasets on OpenCity](https://data.opencity.in/dataset?organization=greater-chennai-police) | Police station and jurisdiction maps, crime tables | None for crashes | Various | Nothing else on crashes |
| iRAD / eDAR (MoRTH; built by NIC Chennai; [manual](https://gisnic.tn.nic.in/irad/downloads/iRAD_User_Manual_V_2.0_draft.pdf)) | Crash-level records with the GPS position of the accident site, entered by police | Yes, inside the system | Government | **No public extract found.** Dashboards for authorities |
| IIT Madras Centre of Excellence for Road Safety ("Sanjaya", [coverage](https://www.dtnext.in/news/chennai/iit-ms-data-driven-initiative-aims-to-tackle-road-accidents-834439)) | Black-spot and hotspot analysis tools built on eDAR for state governments | Yes, inside the tool | Not public | Would need a data-sharing request |
| [DT Next, "104 black spots identified in Chennai"](https://www.dtnext.in/city/2022/09/08/104-black-spots-identified-in-chennai-steps-taken-to-reduce-deaths) (8 Sep 2022) | A count of 104 black spots; cites NCRB 2021 for city totals | **No spot is named** and the article does not say who holds the list | News | A fact to cite, not data |
| Tamil Nadu Highways Department RADMS / [e-PATHAI](https://www.tnhighways.gov.in/index.php/en/e-pathai/about-e-pathai) | GIS accident data and black-spot analysis for highways | Yes, inside the system | Government | No public download found |
| [Indian Road Accident Dataset 2022 to 2025, Kaggle](https://www.kaggle.com/datasets/sehaj1104/indian-road-accident-dataset-20222025) | About 20,000 rows over eight cities (Chennai about 13%): severity, latitude, longitude, date, hour, weather, road type, a 0 to 1 risk score. CC0 | Yes, but the listing says **some attributes, including coordinates, are synthetically generated** | CC0 | **Not evidence.** Method practice only. The page itself could not be read in full by the tool; this comes from its search-result description |
| GitHub "C.R.A.S.H." Chennai dataset | Records for Kathipara, Guindy, Koyambedu | Yes | n/a | Its own description says synthetic. Not used |
| GitHub Tamil Nadu accidents CSV | District points | One point per district, with an obvious error (Salem at longitude -123) | n/a | Not used |
| [TomTom Traffic Incidents API](https://developer.tomtom.com/traffic-api/documentation/tomtom-maps/traffic-incidents/incident-details) | **Live** incidents with coordinates and an "accident" category; India is covered | Live only, no archive | Free tier needs the team's own account; **whether incident records may be stored over time was not found in its terms** and must be asked | A possible live feed, not a history |

## What this means for a model

- **There is no accident model today.** The advice model (ADR-021) is hand-set; ADR-032 added accident inputs to it with placeholder weights. Nothing was ever trained on accidents, so there is nothing to "retrain".
- **Training needs three things this search could not find:** crash locations, dates, and a way to know a model got better. Training on the synthetic Kaggle file would produce numbers that describe the generator, not Chennai, and the project's rules forbid presenting that as evidence.
- **Yearly totals cannot place a risk on a street.** They can say whether Chennai's crashes are rising or falling, and nothing about which road.

## What would change the answer

1. **A data request** to Greater Chennai Traffic Police, the Tamil Nadu Highways Department (RADMS) or IIT Madras's road-safety centre, asking for crash locations with dates, with personal details removed. Only the team can send it (nothing was sent).
2. **Our own dated record.** Accident reports from the app, and accident events reviewed from public news and police posts through the event miner (ADR-030, which today extracts flooding, closure and "cleared" events and would need an accident condition). Small and biased toward what is reported, but real, dated and ours.
3. **TomTom's live incidents**, if the team opens an account and TomTom confirms in writing that stored records are allowed.
