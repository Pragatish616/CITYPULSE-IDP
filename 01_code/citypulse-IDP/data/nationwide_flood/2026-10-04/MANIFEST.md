# Nationwide district flood-event dataset (2026-10-04)

Built for the model in ADR-025. **Research use only (non-commercial):** the labels come from the India Flood Inventory (CC BY-NC 4.0).

| File | What it is |
|---|---|
| `PREREGISTRATION.md` | The analysis rule, committed before any model was trained, with addenda A (geocoding levels) and B (rainfall source) |
| `districts.csv`, `district_events.csv`, `registry_report.json` | 948 district names and 17,787 district-event pairs (1990 to 2023) from the IFI, keyed by state and name (LGD codes are not reliable keys) |
| `geocode.json`, `geocode_raw/` | A point for 592 of 948 districts (550 by level 1, 21 by level 3, 21 by level 4; 7 spelling duplicates merged; 349 unresolved), with every service answer kept for audit |
| `power_daily_precip.npz` | Daily rainfall 1990 to 2023 in mm at those 592 points, NASA POWER PRECTOTCORR (MERRA-2 reanalysis, 0.5 degree), plus elevation from the geocoding answer |

Local only (git-ignored): `power/*.json` (the 592 source files, 41 MB), and `rain/` (72 Open-Meteo files fetched before the switch, unused).

## Sources and attribution

| Source | Use | Terms |
|---|---|---|
| India Flood Inventory v4 (IMD events) | event labels | CC BY-NC 4.0 |
| Open-Meteo geocoding (GeoNames-based) | district points and elevation | attribution; non-commercial free tier |
| NASA POWER | daily rainfall | NASA open data; cite NASA POWER (MERRA-2) |

## Coverage

13,728 of 17,787 district-event pairs (77.2%) belong to a district with a point. The model covers 29 states. Arunachal Pradesh, Meghalaya, Delhi, Goa, the
Andamans, Puducherry and Dadra and Nagar Haveli have no district with a point, and several large Assam districts (Kamrup, Cachar, Marigaon) are also missing.
