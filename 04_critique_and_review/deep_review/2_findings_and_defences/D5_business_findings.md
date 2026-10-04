# Findings to defend (D5_business)

## F1 [Critical] C-1. "Fleet operators … First revenue" has no supporting evidence, and the available evidence points the other way
**Location:** plan.tex L164 (customers); L171 (revenue sequence); L185 ("fleet vehicles on the API"); L211 (WTP interviews). This also inherits COUNCIL_VERDICT.md L117–125 ("a buyer with a budget").

**Claimed problem:** No Indian fleet has been shown buying third-party flood or passability data. What fleets actually do:
  - They build in-house: Zomato runs about 650–700 weather stations and gives the data away free as CSR (V8). Blinkit "blacklists" routes from rider reports.
  - Their rain-day decision is coarse: service area on or off, dark store suspended (V14).
  - Their binding constraint is rider supply ("a sudden drop in delivery partner supply"), not route choice (V14). A passability API optimises a decision fleets mostly don't make at segment level.
  - Commodity routing is cheap: Google India Pro is US$3 per 1,000 calls after 35k free (market.md Q4). That leaves little room for a per-call add-on.
  - Fleet-native competitors already pitch waterlogging and hazard data: Delhivery Maps, Civilytix, NAYAN AI, FlowSense, MapmyIndia (V12).

## F2 [Critical] C-2. The moat claim ("nobody can buy it") is contradicted: traversal data is already owned, sold and bought by others
**Location:** plan.tex L151 ("the one input dense exactly where users are, and nobody can buy it"); L176 ("Data network effect from traversal silence").

**Claimed problem:** Traversal is exactly what probe-based traffic data measures, and others already hold it:
  - Google live speeds come from tens of millions of Android users. GCTP pays for them today through Mandark (V5).
  - Delhivery processes about 1B pings a day and sells routing APIs (V12). Every fleet holds its own riders' traces.
  - CityPulse's own data position: zero users today, and a free app that the plan itself says has zero willingness to pay (L163). Under DPDP and B2B terms, a fleet's traces would be processed for that fleet as data processor (market.md Q5). That usually forbids pooling across clients, so the "network effect" does not accrue to CityPulse.
  - The technique (treating no-report traversals as missing-not-at-random evidence) is publishable. It is not proprietary.

## F3 [Critical] C-3. Positioning sells "passability", which the product's own safety rule forbids asserting
**Location:** plan.tex L171 ("Chennai's monsoon passability layer"), L164/L171 ("paid fleet API"), versus L194 ("Never assert passability (ADR-011)") and L156 ("liability shield").

**Claimed problem:** - A B2B "passability API" that tells a dispatcher which roads riders can use is asserting passability, and to a commercial party that will route gig workers through water on the strength of it.
  - The symbolic verifier only constrains consumer explanation text. It does nothing for API outputs.
  - Bareilly shows Indian police will name a navigation provider in a culpable-homicide FIR (V11). A 3-student unincorporated team has no intermediary-status argument and no balance sheet.

## F4 [Critical] C-4. The most credible first paying customer is misplaced: the government-vendor channel is treated as slow and late
**Location:** plan.tex L166 ("grants or MoUs; 12–24 month cycles"); L171 (government licences come third); L211 ("draft GCC/TNSDMA pilot note" in weeks 8–12).

**Claimed problem:** The only verified Chennai buyers of road intelligence pay through vendors:
  - GCTP pays about ₹96 lakh/yr to Mandark for a Google-traffic dashboard, still running in Sep 2025 (V5).
  - GCC is tendering ICCC 2.0 (₹98.25 cr over 5 years) with "data integration and APIs", flood sensors and boom barriers. Its temporary O&M ends 30 Nov 2026 (V4), so a system integrator is likely chosen around Dec 2026–Q1 2027. That is inside the 90-day window.
  - GCTP has used a vendor (Lepton) to push closures to Google Maps (V6).
  - The plan postpones this channel to "weeks 8–12" and frames it as 12–24 months, when a **subcontract or add-on to an incumbent vendor** is the shortest path to money that exists.

## F5 [Significant] S-1. Consumer segment description is contradicted, and the "riders are the sensors" premise has a failed local precedent
**Location:** L163; L171 ("Free citizen app (the sensor network)"); L193 (cold start).

**Claimed problem:** - Riders do not rely only on WhatsApp. Google Maps has offered flood reporting and alerts in India since Oct 2024, with the highest flood-alert volume globally in 2025 (V1, V2). Mappls advertises on-route waterlogging alerts (V12).
  - RiskMap ran this exact crowd concept in Chennai from 2017 to 2019 with MIT and Tata backing and ended as a pilot (V7). IIT-M's chennaiwaterlogging.org reached about 1,200 reporters at the Michaung peak (chennai_india.md O7).
  - Networks failed during Michaung (market.md Q3).
  - The plan does not explain why a free CityPulse app would recruit sensors when Google already has the crowd.

## F6 [Significant] S-2. Government segment: these agencies are builders and SI buyers, and RTFF already gives street-level forecasts in the pilot corridors
**Location:** L166, L154.

**Claimed problem:** - RTFF & SDSS (₹107.2 cr, IIT-M oversight) gives "street-level inundation forecasts" for Velachery, Mudichur, Saidapet and others. It covers the Adyar, Cooum, Kosasthalaiyar and Kovalam basins and is integrated with TNSMART and TN-Alert (V3). That overlaps directly with the plan's corridors (L163) and with the "reservoir-to-corridor causality" differentiator (L154).
  - TNSDMA is unlikely to license a student layer that competes with its own system.

## F7 [Significant] S-3. Insurer hypothesis: the value mechanism is probably parking, not routing
**Location:** L167; L156.

**Claimed problem:** - Insurers' own Chennai flood actions are SMS advice not to park in low-lying areas or basements and not to crank submerged engines, plus claims desks and towing (V13).
  - Engine damage from driving into water is commonly excluded unless an add-on is bought (market.md Q3). So route-avoidance benefits accrue partly to the driver, not the insurer.
  - ICICI Lombard built its weather alert system in-house with an IIT-B startup. HDFC ERGO funds IIT-B as CSR.
  - Hypothesis: parked-vehicle submersion is the larger claim pool. I did not verify this split.

## F8 [Significant] S-4. Roadmap sequencing: willingness-to-pay comes after the pilot, the pilot lands at monsoon peak, and exams clash
**Location:** L210 (fleet pilot in weeks 4–8, i.e. about 29 Oct–26 Nov); L211 (WTP interviews in weeks 8–12); L193 ("before the first heavy rain"); L194 (register an entity).

**Claimed problem:** - Demand discovery is scheduled after the most expensive step.
  - Seeding a fleet and two RWAs before the first heavy rain leaves about 2 weeks. A DPDP processor agreement and an entity are prerequisites for a fleet pilot handling rider traces, and neither exists.
  - Ops managers have the least bandwidth during monsoon peak.
  - VIT end-semester exams typically fall in Nov–Dec, overlapping the monsoon. This is a schedule risk the plan does not list; I have not verified the exam dates.

## F9 [Significant] S-5. Regulation section misses the possible DPDP compression and the retention rule, and understates the traversal-silence consent burden
**Location:** L196 ("DPDP consent for any location use"); L209 ("traversal-silence logging with consent"); L103 ("DPDP-aware retention").

**Claimed problem:** - MeitY proposed moving the main DPDP compliance date from 13 May 2027 to **13 Nov 2026**. No instrument had been located as of 6 Sep 2026, but the risk is live (V10).
  - Rule 8(3) requires keeping personal data plus processing logs for **at least one year** for Seventh-Schedule purposes (V9). That may conflict with short-retention designs.
  - Traversal silence needs continuous location from gig workers. Done via a fleet, the fleet is the data fiduciary and CityPulse is the processor, which also blocks pooling (see C-2).

## F10 [Significant] S-6. The competitive set is incomplete and "offline" is not unique
**Location:** §5 table L115–128 (product facts marked * as not re-verified); L171–173; L176.

**Claimed problem:** - The plan omits Mappls on-route waterlogging alerts and MapmyIndia NaviMaps offline navigation (V12).
  - It omits fleet-facing hazard startups: Civilytix (offline, on-device waterlogging detection for fleets), NAYAN AI, FlowSense. It omits FloodSafe (offline-first flood-routing PWA) and Delhivery Maps.
  - It omits Google Flood Hub urban flash floods (Mar 2026, area-level, with Google aiming at hyper-local).
  - "Offline" is matched by Mappls for navigation, though not for hazard belief. "On-device AI, offline" is Civilytix's own tagline.

## F11 [Significant] S-7. The on-device "commercial" argument is immaterial at pilot scale
**Location:** L173.

**Claimed problem:** 78% of ₹10,700/month (repo `docs/APIS_AND_COSTS.md` L91) is about ₹8,300/month. No buyer chooses a vendor on that.

## F12 [Significant] S-8. No non-dilutive funding path, and no commercial-validation metrics
**Location:** §7.4 metrics L178–185; §8; §10.

**Claimed problem:** - The metrics are technical and growth vanity: there are no LOIs, no pilots signed, no data-sharing agreements and no paid conversions.
  - The plan omits the funding a ₹0 team can realistically get first:
    - TANSEED: up to ₹15 lakh for green-tech; needs Tamil Nadu registration plus DPIIT recognition; the call ran in December last year.
    - Insurer CSR (the HDFC ERGO and IIT-B precedent).
    - The next Bharat WIN, Greenovation and EcoHub cycles.
