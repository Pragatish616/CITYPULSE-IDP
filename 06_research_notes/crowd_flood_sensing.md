# Crowdsourced and multi-source urban flood sensing for roads: evidence fusion, negative evidence, decay and calibration

Scope note: 49 works are listed in the table at the end. None of them appears in `/home/claude/citypulse_context/refs.tsv` (checked against its DOIs and titles). Praharaj 2021 *TRR*, Safaei-Moghadam 2023 *NHESS*, Amin-Naseri 2018, Sadler 2018, Wang 2018, Rosser 2017, Assumpção 2018 and Kasmalkar 2020 are already in refs.tsv. Here they appear only as context, never as new entries.

Verification method: I resolved every new entry against its Crossref record, through `api.crossref.org/works?query.bibliographic=…&select=…` or `filter=doi:…`, fetched with Exa web_fetch. A direct curl to Crossref was blocked by the egress proxy. I took authors (in order), title, venue, volume, issue, pages, year and DOI from that record.
- **VERIFIED** means all of those fields came from the Crossref record.
- **VERIFIED (authors partial)** means the record view was cut off in the author list, so the list ends in "et al.".

Summaries come from the abstracts I read through Consensus, Exa highlights, the publisher page or the Crossref abstract. Where I only read highlights, the summary says so.

---

## Q1. What signals detect street-level flooding in near real time, and how accurate are they?

### Takeaway
Six signal families have published accuracy numbers:
- probe or floating-car data (speed drops, loss of samples or traffic)
- navigation-app reports (Waze)
- social media text and images
- CCTV or street-photo computer vision
- low-cost IoT depth sensors
- data fusion with models

Reported accuracy is moderate. Floating-car-data (FCD) detectors give 68–90 % detection at a 1.5–2 % false-alarm rate. Image depth estimates have errors of about 0.1–0.3 m, and AUCs fall around 0.8–0.95. Almost every study is a single-city, single-event case study, and ground truth is usually weak (news reports, model output, or other crowd data).

### Cited Findings
**Probe-vehicle and floating-car data (FCD) as flood sensors**
- Hu et al. (CICTP 2018) detect waterlogging from precipitation plus FCD speed, using two thresholds set from the lower confidence limits of normal-state speeds. In Shenzhen on 13 June 2017 they report a 68–90 % detection rate and a 1.5–2 % false-alarm rate. — [Hu et al. 2018](https://doi.org/10.1061/9780784481523.187)
- Song et al. (IET ITS 2015) detect flooding under grade-separation bridges in Beijing.
  - An improved CUSUM method fails when every lane is blocked.
  - Their method uses three FCD decision parameters: *sample losing rate*, speed, and accumulated discrepancy.
  - The disappearance of probe samples is itself treated as evidence of flooding. — [Song et al. 2015](https://doi.org/10.1049/iet-its.2014.0228)
- Hiramoto et al. (IJDRR 2025) compare vehicle probe data with modelled inundation depth for the July 2020 Kuma River flood in Japan.
  - Whether a road area carries traffic tracks the expansion and contraction of the inundated area.
  - Vehicle speed correlates negatively with inundation depth and flow velocity.
  - Links with no traffic, or with speeds below 20 km/h on selected road classes, are classed as inundated on a 250 m mesh. — [Hiramoto et al. 2025](https://doi.org/10.1016/j.ijdrr.2025.105373)
- Kong et al. (J Flood Risk Manag 2022) use a significant drop in the *taxi passing rate* on each road segment in Shenzhen, plus a logistic regression on whether the drop is precipitation-related, to recognise "flood-affected roads" after an event. They describe taxi GPS as an "unsolicited" crowdsourced source. — [Kong et al. 2022](https://doi.org/10.1111/jfr3.12799)
- She et al. (IJGI 2019) build per-road time series of taxi GPS point density by map matching, fused with a density grid, to extract when and how badly roads in Wuchang, Wuhan were flooded.
  - Validation was only against news reports, which matched with "high similarity".
  - The method also found flooded roads the news did not report. — [She et al. 2019](https://doi.org/10.3390/ijgi8090407)
- Kawasaki et al. (IJITS-R 2024) detect traffic anomalies during heavy rain from probe data, specifically vehicles making U-turns in front of damaged areas. They calibrate on past disasters and test transfer to other events (from Exa highlights). — [Kawasaki et al. 2024](https://doi.org/10.1007/s13177-023-00382-0)
- Yuan et al. (CEUS 2022) use fine-grained segment speed data from Hurricane Harvey (Harris County) to predict each road segment's flood status 2–4 h ahead with spatio-temporal graph convolutional networks (STGCNs). Precision is above 98 % and recall above 96 %. Note that "status" was derived from the traffic data itself. — [Yuan et al. 2022](https://doi.org/10.1016/j.compenvurbsys.2022.101870)
- Yuan et al. (Comput Urban Sci 2023) use crowdsourced reports and fine-grained traffic data as the road-inundation label. Random forest reaches AUC 0.860 (Harvey) and 0.790 (Imelda); AdaBoost reaches 0.810 and 0.720. — [Yuan et al. 2023](https://doi.org/10.1007/s43762-023-00082-1)
- Rajput et al. (SCS 2023), Harvey traffic data: flooding of 1.3 % of road segments caused an 8 % "temporal expansion" of the whole network. Travel-time increases persisted for weeks and did not decay with distance from inundated areas. In other words, speed effects spill well beyond flooded links. — [Rajput et al. 2023](https://doi.org/10.1016/j.scs.2023.104693)
- Dong et al. (Commun Earth Environ 2022): a 2.2 % flood-induced compound failure (flooding plus congestion) shrank the giant component by 17.7 %. — [Dong et al. 2022](https://doi.org/10.1038/s43247-022-00366-0)
- Bartos et al. (Sci Rep 2019) show connected-vehicle *windshield-wiper* signals from about 70 vehicles predict binary rain state better than gauges or radar. They update radar fields with wiper data in a Bayesian filter. This is a vehicle-as-sensor precedent for rainfall, not for depth. — [Bartos et al. 2019](https://doi.org/10.1038/s41598-018-36282-7)

**Navigation-app (Waze) reports**
- Lowrie et al. (Sci Rep 2022) derive spatial and temporal clustering parameters for Waze flood reports by associating them with authoritative reports during Hurricane Harvey. They then use those parameters to find previously unreported likely flash-flood events. — [Lowrie et al. 2022](https://doi.org/10.1038/s41598-022-08751-7)
- Walker et al. (TRIP 2024) build a logistic-regression Roadway Flood-Severity Index with Waze flood reports as the target.
  - Roadway flooding is "relatively uncommon", which makes prediction hard.
  - Speed and mobility data were too variable to use as model inputs. — [Walker et al. 2024](https://doi.org/10.1016/j.trip.2024.101218)
- Safaei-Moghadam et al. (J Hydrol 2024) combine a graph-based flood-spreading model, historical vulnerabilities and real-time Waze alerts (Dallas; 15 training storms, 5 test storms). They correctly predict 73 % of risk observations in the test storms. — [Safaei-Moghadam et al. 2024](https://doi.org/10.1016/j.jhydrol.2024.131406)
- Praharaj et al. (Nat Hazards 2021), Norfolk: flood events reduced 24 h city-wide vehicle-hours travelled (VHT) by 3 % on average. Locally, on weekday afternoons and evenings, VHT fell 7 % and vehicle-miles travelled fell 12 % in Waze-flagged areas. — [Praharaj et al. 2021](https://doi.org/10.1007/s11069-020-04427-5)

**Social media text and images**
- Karmegam et al. (Geoenviron Disasters 2021), **Chennai 2015**: 95 water-height points were extracted from Twitter and Facebook (72 inside Chennai) and interpolated into a depth map. RMSE against field data was ±0.3 m. Filtering was keyword and MySQL based and largely manual. — [Karmegam et al. 2021](https://doi.org/10.1186/s40677-021-00195-x)
- Tripathy et al. (Urban Climate 2024), Mumbai: Twitter flood reports, cross-checked with volunteered geographic information (VGI) and a height-above-nearest-drainage (HAND) map, identify hotspots. Flood *reporting* fell in recent years even as extreme rain rose, which they attribute to mitigation works. — [Tripathy et al. 2024](https://doi.org/10.1016/j.uclim.2024.101815)
- Smith et al. (J Flood Risk Manag 2017; online 2015) compare Newcastle GPU hydrodynamic simulations with Twitter-identified flooding to infer inundation elsewhere. They found "good agreement" even with few geocoded tweets. — [Smith et al. 2017](https://doi.org/10.1111/jfr3.12154)

**Camera, CCTV and photo depth estimation**
- Kharazi & Behzadan (CEUS 2021) estimate depth from submerged stop signs by measuring pole length. Mean absolute error (MAE) is 12.63 in. — [Alizadeh Kharazi & Behzadan 2021](https://doi.org/10.1016/j.compenvurbsys.2021.101628)
- Alizadeh & Behzadan (Comput Urban Sci 2023) apply the same pre/post-flood pole-length idea to crowdsourced photos, with tilt correction. MAE is 4.710 in. — [Alizadeh & Behzadan 2023](https://doi.org/10.1007/s43762-023-00090-1)
- Song & Tuo (Sensors 2021), FloodMask (Mask R-CNN on traffic signs): average error 0.11 m against human visual estimates. — [Song & Tuo 2021](https://doi.org/10.3390/s21165614)
- Zhong et al. (Water Resour Manag 2024) apply YOLOv4 to submerged references (pedestrian legs, vehicle exhaust pipes) in 1,177 images. Mean average precision (mAP) is 89.29 %, and vehicles are better references than people. — [Zhong et al. 2024](https://doi.org/10.1007/s11269-023-03669-9)
- Akinboyewa et al. (Comput Urban Sci 2024) use GPT-4V to estimate depth from photos using reference objects. They claim "consistent and reliable" estimates, but the abstract gives no numeric error. — [Akinboyewa et al. 2024](https://doi.org/10.1007/s43762-024-00123-3)
- Wu et al. (ESWA 2024) use a CBAM-ResNet50 depth-level classifier on 6,294 images, with 92.45 % test accuracy, deployed in a WeChat mini-program. — [Wu et al. 2024](https://doi.org/10.1016/j.eswa.2024.124382)
- Du et al. (Measurement 2025) use CA-ResNet on 5,676 Weibo images from the 2021 Henan event, with 83.14 % accuracy for levels 0–8 within an error range. — [Du et al. 2025](https://doi.org/10.1016/j.measurement.2024.116114)
- Moy de Vitry et al. (HESS 2019) introduce SOFI, the fraction of the frame covered by water in surveillance video. It reaches a 75 % average Spearman correlation with water-level trend, or 85 % after fine-tuning on as few as seven frames. It needs no per-camera calibration but gives trend only, not absolute depth. — [Moy de Vitry et al. 2019](https://doi.org/10.5194/hess-23-4621-2019)
- Hao et al. (Water Resour Manag 2022) run YOLOv3 sedan detection in street surveillance video (Dalian) to estimate ponding level, followed by outlier removal and inverse-distance-weighted (IDW) interpolation. mAP is 78 %, and outlier detection raised cross-validated accuracy to 88 %. — [Hao et al. 2022](https://doi.org/10.1007/s11269-022-03107-2)
- Wang et al. (Environ Model Softw 2024) segment flood extent in real surveillance images with deep convolutional neural networks (DCNNs). Mean F1 on validation is above 0.9. Failure modes: specular still water, wet roads, low light, storm visibility, and raindrops on the lens. — [Wang et al. 2024](https://doi.org/10.1016/j.envsoft.2023.105939)
- Vandaele et al. (HESS 2021) apply transfer-learning water segmentation to river cameras. Annotation accuracy is above 91 %, and a year-long series correlates with nearby gauges at Pearson r > 0.94. — [Vandaele et al. 2021](https://doi.org/10.5194/hess-25-4435-2021)

**IoT water-level sensors**
- Mydlarz et al. (WRR 2024), FloodNet: 87 low-cost ultrasonic street-level depth sensors across New York City, independent of grid power and network. They record presence, depth and duration of floods. — [Mydlarz et al. 2024](https://doi.org/10.1029/2023WR036806)
- Silverman et al. (Water Research 2022) describe FloodNet use cases worked out with NYC stakeholders: model inputs, real-time alerts, recovery, and design. — [Silverman et al. 2022](https://doi.org/10.1016/j.watres.2022.118648)
- Loftis et al. (MTS J 2018), StormSense (Hampton Roads): ultrasonic and radar IoT sensors used to validate a 5 m street-level hydrodynamic model. They are cross-checked against a temporary USGS gauge and crowdsourced GPS max-extent points from the Sea Level Rise app. — [Loftis et al. 2018](https://doi.org/10.4031/mtsj.52.2.7)

**Multi-source fusion frameworks**
- Panakkal & Padgett (RESS 2024) fuse physical, social and visual sensors with physics-based models to infer flood impacts at link and network level in Houston. They call it only a "limited case study". — [Panakkal & Padgett 2024](https://doi.org/10.1016/j.ress.2024.110368)
- Yuan et al. (ERIS 2022) set out a "smart flood resilience" framework (Harvey):
  - flood sensors to predict road inundation
  - social-media machine learning
  - traffic data for network-theoretic nowcasting of flood propagation on roads — [Yuan et al. 2022](https://doi.org/10.1088/2634-4505/ac7251)
- Du et al. (Remote Sens 2024) fuse Weibo water-depth points with physical sensing, using IDW attenuation plus Gaussian weighting, to produce an inundation *probability* map (Xinxiang, 2021). Thresholded accuracy is 88.77 % against radar points and 75 % against social points. — [Du et al. 2024](https://doi.org/10.3390/rs16152734)
- Huang et al. (Annals of GIS 2018) build a VGI-anchored probability index from the DEM, weighted by the satellite normalized difference water index (NDWI), as a near-real-time flood-probability map (Columbia, SC, 2015). — [Huang et al. 2018](https://doi.org/10.1080/19475683.2018.1450787)
- Helmrich et al. (EMS 2021) review webcams, social media and citizen science for urban flood monitoring. They conclude that integrating sources could ease each source's quality and completeness problems, but "substantial weaknesses" remain. — [Helmrich et al. 2021](https://doi.org/10.1016/j.envsoft.2021.105124)

### Inferences
- For road passability, probe and traffic signals are the most scalable and the only ones that observe *every* traversed segment. However, they measure traffic disruption, not water depth. Kong et al. state this explicitly: "flood-affected road" ≠ "flooded road".
- Image methods give depth but are sparse, and need a reference object (sign, car) or a calibrated camera.
- For Chennai, the only street-scale crowd-depth precedent I found is Karmegam et al. 2021 (±0.3 m, 72 points).

### Gaps
- None of the image or probe studies were run in India, apart from Karmegam (social text and images). I found no study of FCD, taxi or ride-hailing flood detection in Chennai or any other Indian city.
- No study reports detection *latency* (time from inundation onset to detection) as a primary metric for probe data.

---

## Q2. Does traversal-silence or probe-vehicle passability inference already exist?

### Takeaway
**Yes, the core idea exists**, both in the general form ("the probe traffic observed is unlikely under an open road, so the road is closed") and in flood-specific forms:
- loss of taxi passing rate or GPS density means flooded
- no traffic, or speed below 20 km/h, means inundated
- sample loss under bridges means flooded
- U-turns in front of a damaged area

The *converse* ("vehicles traversed, so the segment is passable") is implicit in the same likelihood ratio and is stated qualitatively by Hiramoto et al. 2025.

What I did **not** find is a published method with all four of the following:
- treats unreported traversals as explicit negative evidence
- fuses that evidence with decaying crowd reports and a static prior in log-odds
- models missing-not-at-random reporting
- validates calibration of the resulting per-segment probability against independent ground truth

That combination, not "traversal silence" itself, is the defensible novelty. Even this is limited by the search depth: about 10 searches and 49 verified papers.

### Cited Findings
- **General road-closure detection from probe absence (HERE Technologies).** "The algorithm compares the likelihood that every road segment … is closed or open, and it triggers an alert whenever the likelihood of the observed probe activity is too small given a historical model." Tested in 12 Western European metro areas: precision 92 % on lower-volume roads and 80 % overall. — [Pietrobon, Lewis & Heverly-Coulson 2019, ACM TSAS](https://doi.org/10.1145/3325912)
- **Flood-specific, taxi passing-rate drop.** A "significant reduction in the taxi passing rate" plus a logistic regression on precipitation linkage identifies flood-affected roads in Shenzhen. — [Kong et al. 2022](https://doi.org/10.1111/jfr3.12799)
- **Flood-specific, GPS point-density time series per road.** Wuhan; validated only against news. — [She et al. 2019](https://doi.org/10.3390/ijgi8090407)
- **Flood-specific, "presence or absence of vehicle traffic area corresponds to the expansion or contraction of the inundation area".** Speed is negatively correlated with depth. Links with no traffic or speed below 20 km/h are classed as inundated. Validation is against a numerical inundation model, not observed depth. — [Hiramoto et al. 2025](https://doi.org/10.1016/j.ijdrr.2025.105373)
- **Flood-specific, "sample losing rate" as a decision parameter** under flooded bridges in Beijing. — [Song et al. 2015](https://doi.org/10.1049/iet-its.2014.0228)
- **FCD speed thresholds:** 68–90 % detection, 1.5–2 % false alarms. — [Hu et al. 2018](https://doi.org/10.1061/9780784481523.187)
- **U-turn anomalies from probe data during heavy rain**, with calibration transferred across disasters. — [Kawasaki et al. 2024](https://doi.org/10.1007/s13177-023-00382-0)
- **Opportunistic sensing route choice:** Wang et al. (Front Comput Sci 2024) choose routes for "opportunity-sensing" so that partial waterlogging observations best predict city-wide waterlogging. This is close to choosing which traversals to collect. I read the highlights only. — [Wang et al. 2024](https://doi.org/10.1007/s11704-023-2714-8)
- **Traffic speed as an inundation label or predictor** (Harvey STGCN; random forest / AdaBoost). — [Yuan et al. 2022](https://doi.org/10.1016/j.compenvurbsys.2022.101870); [Yuan et al. 2023](https://doi.org/10.1007/s43762-023-00082-1)
- **Unverified leads, not opened as primary records:**
  - HERE patent EP3822939A1, "automatic road closure detection during probe anomaly". The Google Patents snippet notes that probe-volume anomalies can create false closures.
  - Japanese grey literature on sharing road-availability information from probe vehicles after disasters (ITS Japan / WCEE papers, which mention turn-around points as an unavailability signal).
  - Brennan et al. 2024 on probe-data metrics at flood-prone rural bridges.

### Inferences
- A CityPulse claim like "we propose using traversals without reports as negative evidence" would be pre-empted by Pietrobon 2019, Kong 2022 and Hiramoto 2025 if framed as new. A defensible framing is "we integrate probe-traversal likelihoods (per prior art) into a calibrated log-odds belief with decaying reports and a static prior, and handle MNAR reporting".
- Probe silence is confounded. Low traffic can mean closure, demand collapse (people stay home in heavy rain), congestion spillover, or simply a low-volume road. Pietrobon optimise specifically for *lower-volume* roads against a historical model. Kong add a precipitation-linkage regression to separate flood effects. Rajput et al. 2023 show speed effects spreading far beyond flooded links. A traversal-based likelihood therefore needs a road-class and time-of-day baseline, and a demand-shock term.
- Traversal implies passability only for the class of vehicle that traversed. Hiramoto find speed falls with depth, so a truck or bus traversing does not imply a two-wheeler or pedestrian can pass. This interacts with CityPulse's per-user-class z and depth thresholds.

### Gaps
- I found no paper that explicitly validates traversal-as-passability (positive evidence) against observed depth on the same segment and time.
- I found no peer-reviewed probe-flood study using Indian fleet data (Ola, Uber, Swiggy, Zomato, Dunzo, bus GPS). Whether such data are obtainable for Chennai was not researched.

---

## Q3. How are crowd-report reliability, temporal decay, duplicates and missing-not-at-random reporting modelled?

### Takeaway
Reliability is mostly modelled with per-report classifiers (logistic regression, fuzzy logic, random forest) on metadata, terrain and agreement with authoritative data. Duplicates are handled with spatio-temporal clustering windows. Temporal decay is almost never modelled explicitly for flood reports. Studies note only that the effect of an assimilated crowd observation is "short-lived" or "persistent", and that Waze coverage drifts over time.

Under-reporting is the best-developed newer line: Bayesian spatial positive-unlabeled models on NYC flooding reports, and demographic-bias analyses. This directly supports treating "no report" as missing-not-at-random rather than as "no flood".

### Cited Findings
- **Reliability classification:**
  - Songchon et al. (CEUS 2021) compare binary logistic regression with fuzzy logic for Twitter flood-data quality (Phetchaburi, Thailand, 2016–2018). Fuzzy logic performs better but is more subjective. — [Songchon et al. 2021](https://doi.org/10.1016/j.compenvurbsys.2021.101690)
  - Already in refs: Praharaj 2021 *TRR* (71.7 % of Waze reports trustworthy).
- **Waze report accuracy against video ground truth (non-flood):**
  - Crashes: 33 % confirmed first reports, 5 % false alarms.
  - Disabled vehicles: 22 % confirmed, **23 % false alarms**.
  - "Neither a Waze report's reliability score nor an incident's duration was correlated with report accuracy."
  - Agencies were usually aware of incidents before the first Waze report. — [Goodall & Lee 2019](https://doi.org/10.1016/j.trip.2019.100019)
- **Coverage drift over time:** Waze report coverage, timeliness and location accuracy against official records (Tennessee, 2018–2021) are not constant. The crash matching rate tracked traffic volume, falling at the start of COVID-19 in March 2020 and recovering gradually in 2021. — [Liu et al. 2023 (TRR)](https://doi.org/10.1177/03611981231185144)
- **Duplicates and clustering:** Spatial and temporal clustering parameters were learned by matching Waze clusters to authoritative reports. — [Lowrie et al. 2022](https://doi.org/10.1038/s41598-022-08751-7)
- **Persistence of crowd information in model state:**
  - Songchon et al. (J Hydrol 2023) assimilate social-media data into a 2D model (Phetchaburi 2017). A local state update gives a "short-lived" improvement. Lasting improvement needs both state and boundary updates. — [Songchon et al. 2023](https://doi.org/10.1016/j.jhydrol.2023.129703)
  - Annis & Nardi (GSIS 2019) assimilate VGI into a 2D hydraulic model (Tiber, 2012). They report "a significant persistence of the model updating after the integration of the VGI". — [Annis & Nardi 2019](https://doi.org/10.1080/10095020.2019.1626135)
- **Missing-not-at-random / under-reporting:**
  - Agostini, Pierson & Garg (AAAI 2024) frame NYC storm-flooding reports as positive-unlabeled data. "There is no way to distinguish events that occur but are not reported from events that truly did not occur" without extra assumptions.
    - A Bayesian spatial latent-variable model that exploits spatial correlation predicts future reports better.
    - Reporting rates are higher in tracts with larger populations and higher shares of white and owner-occupier residents. — [Agostini et al. 2024](https://doi.org/10.1609/aaai.v38i20.30190)
  - Liu, Bhandaram & Garg (Nat Comput Sci 2024), "Quantifying spatial under-reporting disparities in resident crowdsourcing". I verified the title and venue only; the abstract was not read. — [Liu et al. 2024](https://doi.org/10.1038/s43588-023-00572-6)
  - Esparza et al. (IJDRR 2023) find that 3-1-1 and Waze flood reports (Imelda 2019, Ida 2021) show data imbalance in areas where minority populations live, and that aggregating to tract level reduces the imbalance. — [Esparza et al. 2023](https://doi.org/10.1016/j.ijdrr.2023.103825)
  - Tripathy et al. 2024: falling report counts in Mumbai were attributed to mitigation. Report volume is not stationary. — [Tripathy et al. 2024](https://doi.org/10.1016/j.uclim.2024.101815)
- **Correlated errors:** Moy de Vitry & Leitão (Water Research 2020) found that with ideal proxy data, half of the calibration configurations improved model performance by at least 70 % over sensor data. Real image-based proxy data, however, "can contain complex correlated errors, which have a complex and predominantly negative effect on performance". — [Moy de Vitry & Leitão 2020](https://doi.org/10.1016/j.watres.2020.115669)
- **Citizen-science design:** Le Coz et al. (J Hydrol 2016) draw on projects in Argentina, France and New Zealand. Success factors: a simple procedure, suitable tools, communication, local-stakeholder support, and public awareness. — [Le Coz et al. 2016](https://doi.org/10.1016/j.jhydrol.2016.07.036)

### Inferences
- Goodall & Lee's finding that Waze's own reliability score did not predict accuracy argues against trusting platform-supplied confidence. It favours learning source weights from data, as Dawid–Skene and truth discovery (already in refs.tsv) do.
- Agostini et al. give the formal citation for "absence of reports ≠ absence of flood" (positive-unlabeled framing). It should be cited wherever CityPulse argues for MNAR handling.
- Duplicates from one viral photo or one WhatsApp forward are correlated observations. Under log-odds fusion they would be double-counted unless clustered, as Lowrie do, or down-weighted. Moy de Vitry & Leitão 2020 show that correlated errors actively hurt calibration.

### Gaps
- I found **no flood-specific empirical study of how long a crowd flood report stays valid**, for example a half-life of report-to-truth agreement. Hazard-class-specific decay rates in CityPulse therefore lack a direct empirical source. The nearest pieces of evidence are Goodall & Lee (duration not correlated with accuracy), Songchon 2023 ("short-lived" update benefit) and Annis & Nardi 2019 ("persistence").
- I did not find published expiry rules for Waze or Google Maps flood alerts in the peer-reviewed literature.

---

## Q4. Which studies report calibration or validation against independent ground truth?

### Takeaway
Independent validation is rare and usually weak. The ground truths used are:
- news reports (She 2019)
- numerical model output (Hiramoto 2025)
- authoritative incident logs (Lowrie 2022; Walker 2024)
- field data (Karmegam 2021: ±0.3 m)
- co-located gauges or sensors (Vandaele 2021: r > 0.94; Moy de Vitry 2019: Spearman 0.75–0.85)
- video (Goodall & Lee 2019)

Discrimination metrics (AUC, precision/recall, accuracy) dominate. **I found no flood-sensing study among these that reports reliability diagrams, Brier decomposition or expected calibration error (ECE)** for per-segment flood probabilities. The closest "probability map" papers are Du 2024 and Huang 2018 (already in refs: Rosser 2017, AUC 0.95/0.93), and they validate by thresholded accuracy or AUC only.

### Cited Findings
- Accuracy after thresholding the probability map: 88.77 % against radar and 75 % against social points. No calibration metric is reported. — [Du et al. 2024](https://doi.org/10.3390/rs16152734)
- AUCs of 0.86 (Harvey) and 0.79 (Imelda), with unstable transfer to Imelda. — [Yuan et al. 2023](https://doi.org/10.1007/s43762-023-00082-1)
- Field-validated depth: RMSE ±0.3 m (Chennai). — [Karmegam et al. 2021](https://doi.org/10.1186/s40677-021-00195-x)
- Gauge-validated camera levels: Pearson r > 0.94. — [Vandaele et al. 2021](https://doi.org/10.5194/hess-25-4435-2021)
- Video ground truth for Waze: 23 % false alarms for disabled vehicles. — [Goodall & Lee 2019](https://doi.org/10.1016/j.trip.2019.100019)
- Probe closure precision of 92 % and 80 % (against what ground truth is not stated in the abstract). — [Pietrobon et al. 2019](https://doi.org/10.1145/3325912)
- Model-based validation only (inundation model as truth). — [Hiramoto et al. 2025](https://doi.org/10.1016/j.ijdrr.2025.105373)
- Walker et al. say future work "should integrate additional validation, or ground-truth, datasets of flooding that is disrupting roadways". — [Walker et al. 2024](https://doi.org/10.1016/j.trip.2024.101218)
- StormSense sensors were cross-validated against a USGS temporary gauge and crowdsourced max-extent GPS points. — [Loftis et al. 2018](https://doi.org/10.4031/mtsj.52.2.7)

### Inferences
- CityPulse's Study 2 (Brier, reliability, ECE) is already methodologically ahead of most of this literature on calibration reporting. Its weakness is the proxy label (official-feed reports) and the single timestamp, not the choice of metric.
- The obvious independent ground truth for Chennai would be low-cost depth sensors (the FloodNet-style design is open), or geotagged photos with depth extracted by the image methods above. Either would give a label not derived from the crowd or prior being calibrated.

### Gaps
- I found no study combining probe traversals and crowd reports with calibration metrics. No India-specific flood ground-truth dataset at segment and time resolution was found in this pass.

---

## Verified reference table (49 new works; none in refs.tsv)

| # | Suggested key | Authors (order) | Title | Venue | Vol(Iss) | Pages / art. | Year | DOI | Status | Summary |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | hu2018fcd | Songhua Hu; Jianjun Dai; Jiandong Qiu; Hangfei Lin | Identification of Urban Road Waterlogging Using Floating Car Data | CICTP 2018 (ASCE) | – | 1885–1894 | 2018 | 10.1061/9780784481523.187 | VERIFIED | Dual precipitation + FCD-speed thresholds. Shenzhen: 68–90 % detection, 1.5–2 % false alarms. |
| 2 | song2015bridges | Guohua Song; Fan Zhang; Jun Liu; Liu Yu; Yong Gao; Lei Yu | Floating car data-based method for detecting flooding incident under grade separation bridges in Beijing | IET Intelligent Transport Systems | 9(8) | 817–823 | 2015 | 10.1049/iet-its.2014.0228 | VERIFIED | CUSUM fails when all lanes are blocked. Sample-losing rate, speed and accumulated discrepancy detect underpass flooding. |
| 3 | hiramoto2025probe | Tatsunori Hiramoto; Riku Kubota; Jin Kashiwada; Mayumi Mizuno; Koji Nishi; Mamoru Tanaka; Yasuo Nihei | Relationship between vehicle probe data and flooding conditions for developing flood inundation monitoring method | Int. J. Disaster Risk Reduction | 120 | 105373 | 2025 | 10.1016/j.ijdrr.2025.105373 | VERIFIED | Kuma River 2020. Traffic presence tracks inundation extent; speed falls with depth. No traffic or <20 km/h means inundated (250 m mesh). Validated against a model. |
| 4 | panakkal2024eyes | Pranavesh Panakkal; Jamie Ellen Padgett | More eyes on the road: Sensing flooded roads by fusing real-time observations from public data sources | Reliability Engineering & System Safety | 251 | 110368 | 2024 | 10.1016/j.ress.2024.110368 | VERIFIED | Fuses physical, social and visual sensors with physics models at link and network level. Limited Houston case study. |
| 5 | kong2022taxi | Xiangfu Kong; Jiawen Yang; Jiandong Qiu; Qin Zhang; Xunlai Chen; Mingjie Wang; Shan Jiang | Post-event flood mapping for road networks using taxi GPS data | J. Flood Risk Management | 15(2) | e12799 (art. no. not in record) | 2022 | 10.1111/jfr3.12799 | VERIFIED | Significant drop in taxi passing rate plus logistic regression on precipitation linkage gives flood-affected roads (Shenzhen). |
| 6 | she2019gps | Shiying She; Haoyu Zhong; Zhixiang Fang; Meng Zheng; Yan Zhou | Extracting Flooded Roads by Fusing GPS Trajectories and Road Network | ISPRS Int. J. Geo-Information | 8(9) | 407 | 2019 | 10.3390/ijgi8090407 | VERIFIED | Per-road taxi GPS density time series plus a grid layer give flooded-road timing and degree (Wuhan). Validated against news only. |
| 7 | pietrobon2019closure | Davide Pietrobon; Andrew P. Lewis; Gavin S. Heverly-Coulson | An Algorithm for Road Closure Detection from Vehicle Probe Data | ACM Trans. Spatial Algorithms and Systems | 5(2) | 1–13 | 2019 | 10.1145/3325912 | VERIFIED | Closed-vs-open likelihood of observed probe activity against a historical model. 12 EU metros; precision 92 % on low-volume roads, 80 % overall. |
| 8 | kawasaki2024uturn | Yosuke Kawasaki; Kensuke Hirata; Hiroshi Ootake | Evaluation of the Versatility of a Traffic Anomaly Detection Method during Heavy Rainfall | Int. J. ITS Research | 22(1) | 69–80 | 2024 (online 2023-12-30) | 10.1007/s13177-023-00382-0 | VERIFIED | Probe-data U-turn anomaly model for heavy-rain disasters, calibrated on past events and tested for transfer (from highlights). |
| 9 | wang2024opportunity | Jingbin Wang; Weijie Zhang; Zhiyong Yu; Fangwan Huang; Weiping Zhu; Longbiao Chen | Route selection for opportunity-sensing and prediction of waterlogging | Frontiers of Computer Science | 18(4) | (art. no. not in record) | 2024 (online 2023-12-18) | 10.1007/s11704-023-2714-8 | VERIFIED | Selects routes to opportunistically sense partial waterlogging and predict city-wide status (from highlights). |
| 10 | yuan2022stgcn | Faxi Yuan; Yuanchang Xu; Qingchun Li; Ali Mostafavi | Spatio-temporal graph convolutional networks for road network inundation status prediction during urban flooding | Computers, Environment and Urban Systems | 97 | 101870 | 2022 | 10.1016/j.compenvurbsys.2022.101870 | VERIFIED | Harvey segment speeds feed an STGCN that predicts road inundation 2–4 h ahead. Precision >98 %, recall >96 %. |
| 11 | yuan2023roadrisk | Faxi Yuan; Cheng-Chun Lee; William Mobley; Hamed Farahmand; Yuanchang Xu; Russell Blessing; Shangjia Dong; Ali Mostafavi; Samuel D. Brody | Predicting road flooding risk with crowdsourced reports and fine-grained traffic data | Computational Urban Science | 3(1) | (art. no. not in record) | 2023 | 10.1007/s43762-023-00082-1 | VERIFIED | Crowd and traffic-derived inundation labels; random forest AUC 0.86 (Harvey) and 0.79 (Imelda). |
| 12 | yuan2022smart | Faxi Yuan et al. (full author list not read in journal record) | Smart flood resilience: harnessing community-scale big data for predictive flood risk monitoring, rapid impact assessment, and situational awareness | Environmental Research: Infrastructure and Sustainability | 2(2) | 025006 | 2022 | 10.1088/2634-4505/ac7251 | VERIFIED (authors partial) | Framework using flood sensors, social media, traffic-based network nowcasting and transaction data (Harvey). |
| 13 | dong2022modest | Shangjia Dong; Xinyu Gao; Ali Mostafavi; Jianxi Gao | Modest flooding can trigger catastrophic road network collapse due to compound failure | Communications Earth & Environment | 3(1) | (art. no. not in record) | 2022 | 10.1038/s43247-022-00366-0 | VERIFIED | Percolation analysis of Harvey traffic: 2.2 % compound failure shrinks the giant component by 17.7 %. |
| 14 | rajput2023anatomy | Akhil Anil Rajput; Sanjay Nayak; Shangjia Dong; Ali Mostafavi | Anatomy of perturbed traffic networks during urban flooding | Sustainable Cities and Society | 97 | 104693 | 2023 | 10.1016/j.scs.2023.104693 | VERIFIED (authors from SSRN record; journal record cut off after 3rd author) | 1.3 % flooded segments cause 8 % network temporal expansion. Effects persist for weeks and do not decay with distance. |
| 15 | kharazi2021stopsign | Bahareh Alizadeh Kharazi; Amir H. Behzadan | Flood depth mapping in street photos with image processing and deep neural networks | Computers, Environment and Urban Systems | 88 | 101628 | 2021 | 10.1016/j.compenvurbsys.2021.101628 | VERIFIED | Submerged stop-sign pole length gives depth; MAE 12.63 in. |
| 16 | alizadeh2023signage | Bahareh Alizadeh; Amir H. Behzadan | Scalable flood inundation mapping using deep convolutional networks and traffic signage | Computational Urban Science | 3(1) | (art. no. not in record) | 2023 | 10.1007/s43762-023-00090-1 | VERIFIED | Crowdsourced sign photos with tilt correction; depth MAE 4.710 in. |
| 17 | zhong2024traffic | Pengcheng Zhong; Yueyi Liu; Hang Zheng; Jianshi Zhao (from Research Square preprint record) | Detection of Urban Flood Inundation from Traffic Images Using Deep Learning Methods | Water Resources Management | 38(1) | 287–301 | 2024 (online 2023-12-02) | 10.1007/s11269-023-03669-9 | VERIFIED (authors from preprint record) | YOLOv4 on submerged legs and exhaust pipes; mAP 89.29 % on 1,177 images. |
| 18 | akinboyewa2024gpt4v | Temitope Akinboyewa; Huan Ning; M. Naser Lessani; Zhenlong Li | Automated floodwater depth estimation using large multimodal model for rapid flood mapping | Computational Urban Science | 4(1) | (art. no. not in record) | 2024 | 10.1007/s43762-024-00123-3 | VERIFIED | GPT-4V estimates depth from reference objects; no numeric error in the abstract. |
| 19 | song2021floodmask | Zhiqing Song; Ye Tuo | Automated Flood Depth Estimates from Online Traffic Sign Images: Explorations of a Convolutional Neural Network-Based Method | Sensors | 21(16) | 5614 | 2021 | 10.3390/s21165614 | VERIFIED | Mask R-CNN on traffic signs; 0.11 m mean error against human estimates. |
| 20 | wu2024cbam | Luyuan Wu; Yunxiu Liu; Jianwei Zhang; Boyang Zhang; Zifa Wang; Jingbo Tong; Meng Li; Anqi Zhang | Identification of flood depth levels in urban waterlogging disaster caused by rainstorm using a CBAM-improved ResNet50 | Expert Systems with Applications | 255 | 124382 | 2024 | 10.1016/j.eswa.2024.124382 | VERIFIED | Depth-level classifier on 6,294 images; 92.45 % test accuracy; public WeChat app. |
| 21 | du2025caresnet | Wenying Du; Mengchen Qian; Sijia He; Lei Xu; Xiang Zhang; Min Huang; Nengcheng Chen | An improved ResNet method for urban flooding water depth estimation from social media images | Measurement | 242 | 116114 | 2025 | 10.1016/j.measurement.2024.116114 | VERIFIED | Coordinate-attention ResNet on 5,676 Weibo images (Henan 2021); 83.14 % within error range. |
| 22 | moydevitry2019sofi | Matthew Moy de Vitry; Simon Kramer; Jan Dirk Wegner; João P. Leitão | Scalable flood level trend monitoring with surveillance cameras using a deep convolutional neural network | Hydrology and Earth System Sciences | 23(11) | 4621–4634 | 2019 | 10.5194/hess-23-4621-2019 | VERIFIED | SOFI index from CCTV; Spearman 0.75 with level trend (0.85 fine-tuned); no per-camera calibration. |
| 23 | moydevitry2020proxy | Matthew Moy de Vitry; João P. Leitão | The potential of proxy water level measurements for calibrating urban pluvial flood models | Water Research | 175 | 115669 | 2020 | 10.1016/j.watres.2020.115669 | VERIFIED | Ideal proxies help calibration a lot; real image proxies have correlated errors that mostly hurt. |
| 24 | vandaele2021river | Remy Vandaele; Sarah L. Dance; Varun Ojha | Deep learning for automated river-level monitoring through river-camera images: an approach based on water segmentation and transfer learning | Hydrology and Earth System Sciences | 25(8) | 4435–4453 | 2021 | 10.5194/hess-25-4435-2021 | VERIFIED | Transfer-learned water segmentation; >91 % annotation accuracy; r > 0.94 with gauges. |
| 25 | hao2022ponding | Xin Hao; Heng Lyu; Ze Wang; Shengnan Fu; Chi Zhang | Estimating the spatial-temporal distribution of urban street ponding levels from surveillance videos based on computer vision | Water Resources Management | 36(6) | 1799–1812 | 2022 | 10.1007/s11269-022-03107-2 | VERIFIED | YOLOv3 sedans in CCTV give ponding level plus IDW; mAP 78 %, about 88 % after outlier removal. |
| 26 | wang2024cctvseg | Yidi Wang; Yawen Shen; Behrouz Salahshour; Mecit Cetin; Khan Iftekharuddin; Navid Tahvildari; Guoping Huang; Devin K. Harris; Kwame Ampofo; Jonathan L. Goodall (from SSRN preprint record) | Urban flood extent segmentation and evaluation from real-world surveillance camera images using deep convolutional neural network | Environmental Modelling & Software | 173 | 105939 | 2024 | 10.1016/j.envsoft.2023.105939 | VERIFIED (authors from preprint record) | DCNN flood-extent F1 >0.9 on validation; real-camera failure modes listed. |
| 27 | mydlarz2024floodnet | Charlie Mydlarz; P. Challagonda; B. Steers; J. Rucker; T. Brain; Brett Branco; Hannah Eisler Burnett; et al. | FloodNet: Low-Cost Ultrasonic Sensors for Real-Time Measurement of Hyperlocal, Street-Level Floods in New York City | Water Resources Research | 60(5) | (art. no. not in record) | 2024 | 10.1029/2023WR036806 | VERIFIED (authors partial, from ESSOAr preprint record) | 87 low-cost ultrasonic street-flood depth sensors in NYC. |
| 28 | silverman2022waves | Andrea I. Silverman; Tega Brain; Brett Branco; Praneeth Sai Venkat Challagonda; Petra Choi; Rebecca Fischman; Kathryn Graziano; et al. | Making waves: Uses of real-time, hyperlocal flood sensor data for emergency management, resiliency planning, and flood impact mitigation | Water Research | 220 | 118648 | 2022 | 10.1016/j.watres.2022.118648 | VERIFIED (authors partial) | Stakeholder-derived use cases for street-level sensor data. |
| 29 | loftis2018stormsense | Jon Derek Loftis; David Forrest; Sridhar Katragadda; Kyle Spencer; Tammie Organski; Cuong Nguyen; Sokwoo Rhee | StormSense: A New Integrated Network of IoT Water Level Sensors in the Smart Cities of Hampton Roads, VA | Marine Technology Society Journal | 52(2) | 56–67 | 2018 | 10.4031/mtsj.52.2.7 | VERIFIED | IoT sensors validate a 5 m street-level model; cross-checked against USGS and crowd GPS extents. |
| 30 | bartos2019wipers | Matthew Bartos; Hyongju Park; Tian Zhou; Branko Kerkez; Ramanarayan Vasudevan | Windshield wipers on connected vehicles produce high-accuracy rainfall maps | Scientific Reports | 9(1) | (art. no. not in record) | 2019 | 10.1038/s41598-018-36282-7 | VERIFIED | About 70 connected vehicles; wiper state beats gauges and radar for binary rain; Bayesian filter fusion with radar. |
| 31 | songchon2023assim | Chanin Songchon; Grant Wright; Lindsay Beevers | The use of crowdsourced social media data to improve flood forecasting | Journal of Hydrology | 622 | 129703 | 2023 | 10.1016/j.jhydrol.2023.129703 | VERIFIED | Social-media data assimilated into a 2D model; local state-update gains are short-lived. |
| 32 | songchon2021quality | Chanin Songchon; Grant Wright; Lindsay Beevers | Quality assessment of crowdsourced social media data for urban flood management | Computers, Environment and Urban Systems | 90 | 101690 | 2021 | 10.1016/j.compenvurbsys.2021.101690 | VERIFIED | Logistic regression vs fuzzy logic for tweet quality; fuzzy better but subjective. |
| 33 | helmrich2021opportunities | Alysha M. Helmrich; Benjamin L. Ruddell; Kelly Bessem; Mikhail V. Chester; Nicholas Chohan; Eck Doerry; Joseph Eppinger; Margaret Garcia; Jonathan L. Goodall; Christopher Lowry; et al. | Opportunities for crowdsourcing in urban flood monitoring | Environmental Modelling & Software | 143 | 105124 | 2021 | 10.1016/j.envsoft.2021.105124 | VERIFIED (authors partial) | Review of webcams, social media and citizen science; multi-source integration recommended. |
| 34 | annis2019vgi | Antonio Annis; Fernando Nardi | Integrating VGI and 2D hydraulic models into a data assimilation framework for real time flood forecasting and mapping | Geo-spatial Information Science | 22(4) | 223–236 | 2019 | 10.1080/10095020.2019.1626135 | VERIFIED | VGI data assimilation with observation uncertainty; update persists (Tiber 2012). |
| 35 | smith2017social | L. Smith; Q. Liang; P. James; W. Lin | Assessing the utility of social media as a data source for flood risk management using a real-time modelling framework | J. Flood Risk Management | 10(3) | 370–380 | 2017 (online 2015) | 10.1111/jfr3.12154 | VERIFIED | GPU hydrodynamic runs matched to tweets to infer inundation (Newcastle). |
| 36 | du2024ips | Wenying Du; Qingyun Xia; Bingqing Cheng; Lei Xu; et al. | Flood Inundation Probability Estimation by Integrating Physical and Social Sensing Data: Case Study of 2021 Heavy Rainfall in Henan, China | Remote Sensing | 16(15) | 2734 | 2024 | 10.3390/rs16152734 | VERIFIED (authors partial) | Weibo depth points plus physical sensing give an inundation probability map; 88.77 % / 75 % thresholded accuracy. |
| 37 | huang2018vgi | Xiao Huang; Cuizhen Wang; Zhenlong Li | A near real-time flood-mapping approach by integrating social media and post-event satellite imagery | Annals of GIS | 24(2) | 113–123 | 2018 | 10.1080/19475683.2018.1450787 | VERIFIED | VGI-anchored DEM probability index weighted by NDWI gives a flood probability map. |
| 38 | lecoz2016citizen | Jérôme Le Coz; Antoine Patalano; Daniel Collins; Nicolás Federico Guillén; Carlos Marcelo García; Graeme M. Smart; Jochen Bind; Antoine Chiaverini; Raphaël Le Boursicaud; et al. | Crowdsourced data for flood hydrology: Feedback from recent citizen science projects in Argentina, France and New Zealand | Journal of Hydrology | 541 | 766–777 | 2016 | 10.1016/j.jhydrol.2016.07.036 | VERIFIED (authors partial) | Lessons from three citizen-science flood projects and their key success factors. |
| 39 | walker2024rfsi | Curtis L. Walker; Amanda Siems-Anderson; Erin Towler; Aubrey Dugger; Andrew Gaydos; Gerry Wiener | Towards development of a roadway flood severity index | Transportation Research Interdisciplinary Perspectives | 27 | 101218 | 2024 | 10.1016/j.trip.2024.101218 | VERIFIED | Logistic Roadway Flood-Severity Index on hydromet inputs with Waze target; flooding is rare and more ground truth is needed. |
| 40 | lowrie2022waze | Chris Lowrie; Andrew Kruczkiewicz; Shanna N. McClain; Miriam Nielsen; Simon J. Mason | Evaluating the usefulness of VGI from Waze for the reporting of flash floods | Scientific Reports | 12(1) | (art. no. not in record) | 2022 | 10.1038/s41598-022-08751-7 | VERIFIED (authors from Author Correction record 10.1038/s41598-022-13306-x) | Spatio-temporal clustering of Waze flood reports matched to authoritative reports (Harvey). |
| 41 | praharaj2021impacts | Shraddha Praharaj; T. Donna Chen; Faria T. Zahura; Madhur Behl; Jonathan L. Goodall | Estimating impacts of recurring flooding on roadway networks: a Norfolk, Virginia case study | Natural Hazards | 107(3) | 2363–2387 | 2021 | 10.1007/s11069-020-04427-5 | VERIFIED | Random forest scales traffic counts; Waze-flagged flooding cuts local VHT 7 % and VMT 12 %. |
| 42 | safaei2024hybrid | Arefeh Safaei-Moghadam; Azadeh Hosseinzadeh; Barbara Minsker | Predicting real-time roadway pluvial flood risk: A hybrid machine learning approach coupling a graph-based flood spreading model, historical vulnerabilities, and Waze data | Journal of Hydrology | 637 | 131406 | 2024 | 10.1016/j.jhydrol.2024.131406 | VERIFIED | Graph flood spreading plus history plus Waze; 73 % of test risk observations predicted (Dallas). |
| 43 | esparza2023imbalance | Miguel Esparza; Hamed Farahmand; Samuel Brody; Ali Mostafavi | Examining data imbalance in crowdsourced reports for improving flash flood situational awareness | Int. J. Disaster Risk Reduction | 95 | 103825 | 2023 | 10.1016/j.ijdrr.2023.103825 | VERIFIED | 3-1-1 and Waze flood reports under-represent minority areas; aggregation reduces the imbalance. |
| 44 | agostini2024underreport | Gabriel Agostini; Emma Pierson; Nikhil Garg | A Bayesian Spatial Model to Correct Under-Reporting in Urban Crowdsourcing | Proc. AAAI Conf. Artificial Intelligence | 38(20) | 21888–21896 | 2024 | 10.1609/aaai.v38i20.30190 | VERIFIED | Positive-unlabeled NYC flood reports; spatial latent model corrects under-reporting; reporting rates vary with demographics. |
| 45 | liu2024disparities | Zhi Liu; Uma Bhandaram; Nikhil Garg; et al. (list cut off) | Quantifying spatial under-reporting disparities in resident crowdsourcing | Nature Computational Science | 4(1) | 57–65 | 2024 (online 2023-12-05) | 10.1038/s43588-023-00572-6 | VERIFIED (authors partial; abstract not read) | Title only: measures spatial under-reporting disparities in resident crowdsourcing. |
| 46 | tripathy2024mumbai | Shrabani Sailaja Tripathy; Sautrik Chaudhuri; Raghu Murtugudde; Vedant Mhatre; Dulari Parmar; Manasi Pinto; P.E. Zope; Vishal Dixit; Subhankar Karmakar; Subimal Ghosh; et al. | Analysis of Mumbai floods in recent years with crowdsourced data | Urban Climate | 53 | 101815 | 2024 | 10.1016/j.uclim.2024.101815 | VERIFIED (authors partial) | Twitter, VGI and HAND hotspot mapping in Mumbai; reporting fell after mitigation. |
| 47 | karmegam2021chennai | Dhivya Karmegam; Sivakumar Ramamoorthy; Bagavandas Mappillairaju | Near real time flood inundation mapping using social media data as an information source: a case study of 2015 Chennai flood | Geoenvironmental Disasters | 8(1) | (art. no. not in record) | 2021 | 10.1186/s40677-021-00195-x | VERIFIED | 95 social-media depth points (72 in Chennai) interpolated; RMSE ±0.3 m against field data. |
| 48 | goodall2019waze | Noah Goodall; Eun Lee | Comparison of Waze crash and disabled vehicle records with video ground truth | Transportation Research Interdisciplinary Perspectives | 1 | 100019 | 2019 | 10.1016/j.trip.2019.100019 | VERIFIED | Video-validated Waze reports: 5 % and 23 % false alarms; Waze reliability score and duration not correlated with accuracy. |
| 49 | liu2023wazecoverage | Yuandong Liu; Nima Hoseinzadeh; Yangsong Gu; Lee D. Han; Candace Brakewood; Zhihua Zhang | Evaluating the Coverage and Spatiotemporal Accuracy of Crowdsourced Reports Over Time: A Case Study of Waze Event Reports in Tennessee | Transportation Research Record | 2678(4) | 468–481 | 2024 (online 2023-08-08) | 10.1177/03611981231185144 | VERIFIED | Waze coverage and accuracy drift over 2018–2021 and track traffic volume (COVID dip). |

**UNVERIFIED leads (not opened as primary records; do not cite without checking):**
- HERE patent EP3822939A1, "Method, apparatus, and system for automatic road closure detection during probe anomaly". Seen only as a Google Patents mirror snippet.
- "Road Information Gathering and Sharing during Disasters Using Probe Vehicles" (ITS Japan PDF).
- "Road Information Sharing Using Probe Vehicle Data in Disasters" (14th WCEE paper).
- Brennan, Bechtel & Venigalla 2024, "Characterising major storm event impacts on rural routes".
- "Understanding Infrastructure Resiliency in Chennai, India Using Twitter's Geotags and Texts" (Engineering, 2018; ScienceDirect pii S2095809918303047). It reports that very few tweets came from less-populated flooded areas in Chennai 2015, which supports MNAR for Chennai. Authors and DOI were not read.
- Panakkal et al. "Safer this way" preprint.
- FRED flooded-road autonomous-driving dataset (arXiv 2026, Malone et al.); arXiv id not checked.

**Consensus usage note (required by tool):** 3 searches left this month; resets to 30 on November 1st. Upgrade to Consensus Pro to get 500 searches per month, return 20 results per search instead of 10, and include more data like study design and key takeaways for every result: https://consensus.app/pricing/?utm_source=claude_desktop
