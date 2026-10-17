# Rain from commercial microwave links (C3)

Mobile operators connect towers with point-to-point microwave links (backhaul). Rain between the antennas weakens the signal, and
operators already log the received power. Overeem et al. turned such logs into city rain (Rotterdam; Water Resources Research 2011) and
country-wide rain maps that in summer beat gauge interpolation (the Netherlands; WRR 2016). For Chennai that would mean minute-scale rain
at street-to-ward scale, far denser than gauges, as an input to the flood event state (ADR-027) and as rain context for reports.

**There is no Chennai link data.** This module is ready for it; access depends on an operator agreeing to share logs.

## What is here

`retrieval.py`: wet/dry classification (single-link rolling variance, or the neighbour rule), dry baseline, wet-antenna correction, and
the k-R power law. The link coefficients a and b (ITU-R Recommendation P.838, per frequency and polarisation) and every threshold are
required inputs: **nothing has a default value**, because none has been checked for Chennai links. The method details are the common
forms from the literature, recalled rather than copied **[UNVERIFIED: check against Overeem et al. 2011 and the open-source pycomlink
before using real data]**.

Tests (`python -m pytest ml/cml_rain -q` from `01_code/citypulse-IDP`, 8 pass) use synthetic links with made-up coefficients. They check
that the chain inverts its own forward model, that an uncorrected wet antenna inflates rain, that the neighbour rule rejects a fade one
link sees alone, and that a link with no neighbours is not guessed wet. They also record a real weakness: the single-link variance rule
misses minutes in the steady middle of an event.

## The data we would ask for

Per link (metadata, once): an anonymous link id, both end coordinates (rounded to 100 m is enough), frequency (GHz), polarisation (H or
V), and path length. Per link and time step (15 minutes is useful, 1 minute is better): minimum and maximum received power (dBm), and the
transmitted power if it is not constant. Monsoon months first (October to December). No subscriber data of any kind is involved.

## Not built

Gridding link rain into a map (interpolation between link midpoints), quality control for equipment changes, and any connection to the
event state or the router (an ADR first).
