# Believer: CityPulse AI

## WHO
The Chennai driver at a flooded subway at 9 pm in December, and the motor insurer who pays when that driver guesses wrong. Cranking a submerged engine is typically not covered, and an engine repair runs about Rs 1.5 lakh. Insurers lost about Rs 4,800–5,000 crore in 2015, mostly on motor claims, and saw 10,000+ motor claims after Michaung. Today people stitch together Google Maps, GCTP and GCC posts on X ("85 roads waterlogged") and WhatsApp. Hyderabad traffic police have said Maps cannot detect waterlogging. No one publishes per-segment passability with an age and a confidence attached.

## WHY NOW
The city has finally put sensors on the problem. 17 of GCC's 22 subways have water-triggered boom barriers. There are 40 flood-meter CCTVs, 46 flood sensors, and an ICCC that lists "data integration and APIs" in its scope. CFM-DSS exposes a public WFS (181 layers were mirrored on 29 Sep 2026). GCC has named 290 past waterlogging points for this monsoon. Michaung took down exchanges in Tambaram, Adyar and Velachery, so offline matters. On-device small models now make offline explanations feasible. The monsoon starts this month.

## BEST VERSION
Not another consumer map, but the Chennai passability layer. It would keep a timestamped, decaying probability per road segment, with an honest "we don't know". It would fuse GCC/GCTP text, barrier and sensor states, and vehicles that pass through without reporting. Insurers would use it to warn policyholders before they drive into water. Fleets would route on it. Phones would keep a copy for when the network dies. Police already pay a vendor (roadEase/Lepton) to push closures into maps, which proves the demand for structured feeds.

## UNFAIR ADVANTAGE
The team is local, and its engineering is real. They have the full Chennai OSM graph (193,191 nodes) and a prior built from 7,453 GCC hazard polygons. They have a 6,132-observation 2015 replay corpus, deterministic runs and about 250 tests. Their explanations fail closed and never claim a road is "safe". No incumbent documents per-segment probability, report-age decay or offline uncertainty-aware routing, and Google calls Flood Hub's urban forecasts area-level. The algorithm is not the moat; prior art covers it. The moat is being on Chennai's streets this monsoon, collecting timestamped passability labels nobody else is collecting.

## THE BET
That timestamped street-level passability signals for Chennai can be captured live this monsoon. Those signals are subway barrier states, flood meters, police closure posts and vehicles passing through without reporting. If they can, a calibrated per-segment probability will beat "Google Maps plus X posts" on the roads where engines actually drown.
