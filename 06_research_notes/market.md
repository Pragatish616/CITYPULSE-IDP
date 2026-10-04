# Commercial landscape for flood-aware / hazard-aware navigation and passability data — India (Chennai focus), as of 1 Oct 2026

Conventions used in these notes:
- **[V]** = verified from a primary or reputable press source at the URL given. **[E]** = an estimate made by the quoted party (an industry body, a press estimate), not an audited figure. **[I]** = my inference (only in the Inferences subsections).
- **[OLD]** = source dated before 2023, so it may be out of date.
- Each figure is quoted as the source states it. I did not convert currencies or extrapolate.
- Tool note: the Consensus academic search hit its monthly quota (it resets 1 Nov 2026). Willingness-to-pay (WTP) literature was found through Exa web search instead (see Q3).

---

## Q1. What do the incumbents actually ship for floods and road closures in India, and what free workaround dominates?

### Takeaway
Google Maps is the free default and already does most of what a consumer flood-reporting layer would do in India:
- crowd-sourced flood and waterlogging reports (launched October 2024);
- confirm-with-one-tap on other people's reports;
- closures fed by traffic police in 18 cities;
- a 2025 partnership with NHAI (National Highways Authority of India);
- Flood Hub, which now includes urban flash-flood forecasts up to 24 h ahead (March 2026).

Mappls (MapmyIndia) and Apple Maps also take crowd hazard reports. Day to day, the dominant workaround in Chennai is free and fragmented: Google Maps plus Greater Chennai Traffic Police (GCTP) and Greater Chennai Corporation (GCC) posts on X listing waterlogged roads and closed subways, plus WhatsApp. No incumbent publishes a per-road-segment, depth-aware passability probability, or one that keeps working offline. That is the only clear functional gap I found.

### Cited Findings

**Google Maps / Google**
- [V] At Google for India (October 2024), Google announced that Maps users in India can report and receive alerts for fog and flooding/waterlogging on roads. — [Times Now, 3 Oct 2024](https://www.timesnownews.com/technology-science/google-maps-adds-real-time-alerts-for-fog-and-flooding-in-india-how-it-works-article-113911307)
- [V] In July 2024, Google simplified incident reporting in India: a report takes a few taps, and other users can confirm a report with one tap "which helps increase confidence in these user reported incidents". Available on Android, iOS, Android Auto and CarPlay. India has "over 60 million" local contributors, which Google calls the largest such community in the world. — [Google India blog, 25 Jul 2024](https://blog.google/intl/en-in/products/explore-communicate/six-ways-were-enabling-more-efficient-and-sustainable-journeys-on-google-maps-in-india-powered-by-ai-and-local-partners/)
- [V] Google Maps partners with traffic police in **18 Indian cities** to map closures. The community surfaces **150,000 disruptions daily**. "India reported the highest number of flood-related alerts on Maps globally this year" (2025). A new NHAI partnership supplies near-real-time highway closure and repair data. Proactive Traffic Alerts launched in Delhi, Mumbai and Bangalore (Chennai not named). Google adds: "always remain alert and exercise caution." — [Google India blog, 6 Nov 2025](https://blog.google/intl/en-in/products/explore-communicate/google-maps-in-india-keeping-you-informed-with-new-safety-disruption-alerts/)
- [V] Google Maps has a crisis-only "Report road closure" flow (Explore → Crisis → Report road closure) that appears only during a declared crisis. — [Google Public Alerts help](https://support.google.com/publicalerts/answer/9561221)
- [V] **Flood Hub urban flash floods:** launched 12 Mar 2026 using Groundsource, which used Gemini to read news reports and build a set of 2.6 million historical flood events across 150+ countries. Forecasts look up to 24 h ahead, cover areas with population density above 100 people/km², and are described as area-level ("is a flash flood likely to occur in this area"), not road-level. Google says it is working to "reduce the spatial resolution for more hyper-local forecasts". — [Google Research blog, 12 Mar 2026](https://research.google/blog/protecting-cities-with-ai-driven-flash-flood-forecasting/); [Moneycontrol, 14 Mar 2026](https://www.moneycontrol.com/technology/google-brings-gemini-powered-groundsource-to-flood-hub-to-predict-urban-flash-floods-up-to-24-hours-in-advance-article-13860137.html)
- [V] Flood Hub forecasts riverine floods up to 7 days ahead in 150 countries. Google offers "a Floods API that gives organizations access to flood predictions", and forecasts appear in Search. — [Google blog, 18 Aug 2026](https://blog.google/innovation-and-ai/technology/research/flood-prediction-ai/)
- [V] Flood Hub, the Floods API and the historical dataset are aimed at "aid organizations, governments and researchers". The shareable map of river-gauge data is free for government agencies, NGOs and researchers. — [Google blog, 18 Feb 2025](https://blog.google/innovation-and-ai/products/advanced-flood-hub-features-for-aid-organizations-and-governments/)

**Waze**
- [V] The Waze Data Feed (GeoRSS, refreshed every 2 minutes) gives partners user-reported hazards, including "flooding". Partners can use water-on-road reports "to feed models that predict which roads might flood". Partnership is required to post feeds. — [Waze partner help](https://support.google.com/waze/partners/answer/10618035?hl=en); [Waze developer docs](https://developers.google.cn/waze/data-feed/constructing-a-partner-feed)
- I did not find an India-specific Waze for Cities partner or Waze flood feature (see Gaps).

**Mappls / MapmyIndia**
- [V] Users can "Post on Map" to report traffic, safety, waterlogging and road closures, with photos and anonymity. — [Indian Express, 9 Jul 2023](https://indianexpress.com/article/technology/techook/how-to-report-accidents-road-closures-waterlogging-google-maps-mappls-8821148/)
- [V] MapmyIndia's CEO (July 2023): the company maps flood damage and publishes it through the free Mappls app, and moderates crowd reports "with help of the authorities". — [LinkedIn post, 9 Jul 2023](https://www.linkedin.com/feed/update/urn:li:activity:7083740428323233792)
- [V] App listing: users can report "water logging". Safety alerts cover potholes, speed breakers and accident-prone areas. A September 2025 build disabled road-condition voice alerts by default. — [Google Play](https://play.google.com/store/apps/details?hl=en&id=com.mmi.maps); [App Store](https://apps.apple.com/in/app/mappls-mapmyindia-maps/id723492531)
- [V] Mappls' government integrations so far are traffic-related, not flood-related: live signal timers in Bengaluru with BTP and Arcadis (October 2025), and an MoU with UP Police for event traffic (2023). — [Hindustan Times, 12 Oct 2025](https://www.hindustantimes.com/cities/bengaluru-news/bengaluru-becomes-first-indian-city-to-get-live-traffic-signal-timings-on-mappls-app-101760265614252.html); [Hindustan Times, 6 Sep 2023](https://www.hindustantimes.com/cities/noida-news/gautam-budh-nagar-traffic-police-collaborates-with-mapmyindia-and-google-maps-for-major-events-traffic-management-101694023747691.html)

**Ola Maps (Krutrim)**
- [V] Ola Maps offers traffic-aware Directions API and Navigation SDKs. I found no flood or waterlogging feature. — [Ola Maps docs](https://maps.olakrutrim.com/krutrim/docs/routing-apis/directions-api)
- Pricing is covered in Q4.

**Apple Maps**
- [V] Since iOS 14.5, Apple Maps users can report Crash, Speed Check, Traffic, Roadwork, Hazard or Road Closure; the options shown vary by country. Apple shows a marker only "when there's a high level of confidence in the reports". I found no flood-specific category. — [Apple Support India](https://support.apple.com/en-in/105024)

**TomTom and HERE**
- [V] TomTom sells real-time incidents, flow and "Send real-time traffic, road and weather hazard alerts to vehicles" (automotive). I found no India flood-specific product. — [TomTom pricing page](https://developer.tomtom.com/pricing)
- HERE: pricing only (see Q4); no flood-specific evidence found.

**The Chennai "workaround stack" in practice**
- [V] During Cyclone Fengal (30 Nov 2024), GCTP issued periodic updates as text: "85 roads were waterlogged", seven subways closed, named roads closed with diversions. — [New Indian Express, 1 Dec 2024](https://www.newindianexpress.com/cities/chennai/2024/Dec/01/traffic-hit-subways-flooded-as-heavy-rains-lash-chennai)
- [V] GCC posted subway status and a count of 134 waterlogged locations on X during the same event. — [New Indian Express, 30 Nov 2024](https://www.newindianexpress.com/cities/chennai/2024/Nov/30/cyclone-fengal-134-locations-waterlogged-in-chennai-7-subways-closed-as-heavy-rains-lash-city); [Times Now](https://www.timesnownews.com/chennai/chennai-traffic-advisory-subway-closed-roads-waterlogged-amid-heavy-rains-watch-article-116247947)
- [V] [OLD] In October 2022, GCTP launched "roadEase" with Lepton Software. Police enter closures, and Lepton relays them to Google Maps "within 15 minutes" as a dotted red line. The stated motivation: press notes and social posts "are not updated on Google Maps immediately". — [The Hindu, 20 Oct 2022](https://www.thehindu.com/news/cities/chennai/chennai-police-launch-roadease-app-to-give-real-time-updates-on-traffic-diversion-road-closure/article66036822.ece)
- [V] GCC is moving toward automated physical closures. Automatic boom barriers in 17 of 22 subways close when water passes a threshold, and can also be closed manually from the Integrated Command and Control Centre (ICCC). GCC also has 40 "flood meter" CCTVs and 159 pumps with telemetry linked to the ICCC. Its in-house Early Warning System app holds "the complete database of inundation-prone areas" and is used by field teams. — [DT Next, 29 Nov 2025](https://www.dtnext.in/news/chennai/advanced-warning-system-subway-barriers-in-place-to-mitigate-ditwah-damage-854965)
- [V] For the 2026 monsoon, GCC lists **290 previous waterlogging points** and **219 vulnerable locations**, and runs a 1913 helpline plus complaint handling on social media. — [The Hindu, 23 Sep 2026](https://www.thehindu.com/news/cities/chennai/gcc-to-expedite-drain-linking-work-to-reduce-flood-risk-at-68-locations/article71495896.ece); [The Hindu, 23 Sep 2026](https://www.thehindu.com/news/national/tamil-nadu/219-vulnerable-locations-identified-ahead-of-northeast-monsoon-says-gcc-commissioner/article71500200.ece)

### Inferences
- [I] A consumer navigation app competing with Google Maps on flood reports is not credible. Google already has the crowd (60M+ contributors, India the global leader in flood alerts), confirm/upvote mechanics, and official closure feeds. A team would be competing with the free default on its home turf.
- [I] The defensible white space is narrower:
  - (a) road-segment passability with uncertainty, for operators who route fleets rather than individuals;
  - (b) working offline or on degraded networks, which matters because Michaung knocked out mobile networks across Chennai (see Q3);
  - (c) structuring GCC/GCTP's own text and sensor outputs (subway barrier states, flood meters, the 290-point list) into a machine-readable feed. The roadEase/Lepton precedent shows the police want closures pushed into maps but rely on a vendor to do it.
- [I] Google's own Flood Hub description implies urban flash-flood forecasts are area-level, not road-level. Road-level passability remains open, but Google says it is working on finer resolution, so the window may be limited.

### Gaps
- Whether Chennai is one of Google's "18 cities" with traffic police partnerships is not stated in the 2025 blog. The Lepton/roadEase relay (2022) suggests some data path exists, but I could not confirm a direct Google–GCTP agreement.
- I found no evidence of Waze for Cities partners in India, or of Waze's active-user share in India.
- I found no public Ola Maps or Mappls flood-closure statistics, and no evidence that HERE has India-specific flood data.
- I found no published accuracy or latency figures for Google's India flood alerts.

---

## Q2. Civic precedents: what has been tried (PetaBencana, RiskMap Chennai, Waze for Cities, FloodNet NYC, TN-ALERT, TNSMART, Mumbai), and who paid for it?

### Takeaway
Every comparable civic flood-reporting or sensing platform I found was funded by grants, philanthropy, CSR or a city budget, not by selling data. Two cases matter most:
- **RiskMap.in already ran in Chennai (2017–2019)**, built by MIT Urban Risk Lab on the same CogniCity software as PetaBencana, funded by Tata Trusts, with good peak usage. It ended as a pilot.
- **FloodNet NYC** shows the one sustainable model found: a city agency contract (US$7.2M over 5 years, about 500 sensors).

The Tamil Nadu government has built its own stack (TN-ALERT, TNSMART, a ₹107.2 crore real-time flood forecast system, the GCC ICCC). The state is a builder of its own systems and a buyer of system integrators, not a buyer of crowd data apps.

### Cited Findings

**PetaBencana (Jakarta)**
- [V] [OLD] Ran on CogniCity open-source software, piloted 2013–2016 as PetaJakarta, then became PetaBencana. Money came mainly from competitive grants (Australian National Data Service, Australian DFAT, University of Wollongong) and a Twitter #DataGrant. Core staff of 8. — [OECD OPSI case PDF](https://oecd-opsi.org/wp-content/uploads/2019/07/PetaBencana.id_Indonesia_2013.pdf)
- [V] [OLD] Grants and awards listed include USAID, Australian Aid, the Open Data Institute and ISIF Asia. Implementing partners: BNPB (national disaster agency) and BPBD Jakarta. — [ITU WSIS stocktaking](https://www.itu.int/net4/wsis/archive/stocktaking/Project/Details?projectId=1513949296)
- [V] [OLD] Reports feed automatically into InAWARE, the BNPB decision-support system (built by PDC, funded by USAID OFDA). Reports peaked at 1,054 on 21 Feb 2017. — [ReliefWeb](https://reliefweb.int/report/indonesia/jakarta-residents-tweet-neighborhood-flood-conditions-disaster-managers-take-notice)
- [V] It is now run by Yayasan Peta Bencana (a foundation, founded 2017). It describes itself as "intentionally designed not to be a stand-alone app": a chatbot reaches out to people posting on social media. It claims its open-source software serves "over 350 million people" across Indonesia, the Philippines, India "and beyond". — [PetaBencana About](https://info.petabencana.id/about-2)
- [V] [OLD] An academic study found "lack of transparency in Petabencana.id management especially in finance issue" and a "lack of role from the private sector". — [JKAP (UGM), 2020](https://journal.ugm.ac.id/jkap/article/view/53167)
- [V] [OLD] During Jakarta flooding on 21 Feb 2017, "over 300,000 residents used the website", and the map "was also embedded in the Uber app for drivers". — [Urban Risk Lab](https://urbanrisklab.org/riskmap)

**RiskMap.in — Chennai**
- [V] [OLD] Launched about 1–2 Nov 2017 by MIT Urban Risk Lab with Citizen Consumer and Civic Action Group (CAG), Chennai. Users reported via Twitter, Telegram or Facebook Messenger chatbots, including location, **flood depth**, a photo and a description. Supported by the MIT Tata Center and Tata Trusts. — [The Hindu, 2 Nov 2017](https://www.thehindu.com/news/cities/chennai/mit-initiative-on-flood-reporting/article19965959.ece); [MIT Tata Center](https://tatacenter.mit.edu/2017/11/03/crowdsourced-flood-mapping-platform-is-now-live-in-chennai-india/)
- [V] [OLD] On 2 Nov 2017 it peaked at 1,152 page views per minute and 111,808 page views in 24 h. Partners: CAG, Resilient Chennai (100RC), SEED India, IIT-Madras. It was "piloted in Chennai (2017 to 2019)". — [Urban Risk Lab](https://urbanrisklab.org/riskmap); [riskmap.mit.edu/india](https://riskmap.mit.edu/india)
- [V] [OLD] It later operated in Chennai, Bangalore, Mumbai, Kerala and Madhubani (Bihar). — [MIT Tata Center portfolio](https://tatacenter.mit.edu/portfolio/real-time-flood-mapping-for-disaster-management-decision-support/)

**Waze for Cities / Connected Citizens**
- [V] A "cost-free exchange": agencies receive Waze alerts, jams and irregularities and send back closure and construction data. Waze's own documentation lists flood-model use. — [National Academies (NAP) ch. 8](https://www.nationalacademies.org/read/28690/chapter/11)
- [V] [OLD] The program launched in late 2014 "at no financial cost" to governments. — [Harvard Data-Smart](https://datasmart.hks.harvard.edu/news/article/wazes-drive-towards-successful-public-partnerships-786)
- [V] Rio de Janeiro used Waze for real-time flood warnings to drivers. — [Waze case study](https://www.waze.com/wazeforcities/casestudies/how-waze-improves-traffic-management-and-safety)

**FloodNet NYC**
- [V] Funding:
  - New York City: US$7.2M to expand from 31 to 500 sites over 5 years (January 2023). — [NYU Tandon, 26 Jan 2023](https://engineering.nyu.edu/news/floodnet-tracking-system-set-large-expansion-across-all-five-boroughs-thanks-72-million-new)
  - Other sources listed in the US DOT report: City of New York US$7M (2022–2027) via the Department of Environmental Protection (DEP), Sloan Foundation US$250K, C2SMART US$90K, plus Empire State Development money. — [US DOT/ROSAP report](https://rosap.ntl.bts.gov/view/dot/67265/dot_67265_DS1.pdf)
- [V] Sensor bill of materials was **US$184.50** (September 2023), or about US$210 with mounting. 87 sensors had been installed at the time of the paper. — [Water Resources Research paper via NOAA](https://repository.library.noaa.gov/view/noaa/68675/noaa_68675_DS1.pdf)
- [V] Over 265 sensors deployed by July 2025, with 500 planned by 2028. Sensors cost "under $300 per unit". Data is open on a free dashboard. — [NYU Tandon, 25 Jul 2025](https://engineering.nyu.edu/news/new-york-citys-flood-sensors-inspire-global-networks-monitor-street-level-flooding)

**Tamil Nadu and Chennai government systems**
- [V] **TN-ALERT / TNSMART:**
  - TNSMART is a web-based multi-hazard impact-assessment and alert system.
  - The TN-ALERT app (app package id `int_.rimes.tnsmart`, i.e. built with RIMES) sends "flood risk alerts based on the forecast of their location" and overrides silent mode.
  - Version 1.0 was released 17 Jul 2023; v2.0 (12 Dec 2024) added location-based forecasts and alerts.
  - Sources: [Google Play](https://play.google.com/store/apps/details?hl=en_IN&id=int_.rimes.tnsmart); [App Store](https://apps.apple.com/in/app/tn-alert/id1559849577)
- [V] The CM announced TN-Alert as bilingual, with forecasts, rainfall, reservoir levels and public emergency reporting. A real-time flood forecasting system was to give "ward-wise and street-wise" warnings in GCC areas. — [Times of India, 30 Sep 2024](https://timesofindia.indiatimes.com/city/chennai/tn-braces-for-northeast-monsoon-tn-alert-app-to-disseminate-info-on-weather/articleshow/113824868.cms); [The Hindu, 6 Oct 2024](https://www.thehindu.com/news/cities/Madurai/tn-alert-app-will-help-in-monsoon-preparedness-say-officials/article68725132.ece)
- [V] **Chennai Real-Time Flood Forecast & Spatial Decision Support System (RTFF & SDSS):**
  - Fully operational from October 2025; estimated cost **₹107.2 crore**; World Bank financed; consultants SECON-JBA; IIT-Madras technical oversight.
  - Gives street-level inundation forecasts for vulnerable areas (Pulianthope, Velachery, Saidapet and others).
  - Integrated with TNSMART; outputs disseminated "selectively" via TN-Alert.
  - Source: [The Hindu, 22 Oct 2025](https://www.thehindu.com/news/cities/chennai/chennai-gets-indias-first-real-time-flood-forecast-system/article70186744.ece)
- [V] A public Chennai Flood Monitor dashboard ("Real Time Flood Forecasting and Spatial DSS") shows reservoir levels. — [chennaifloodmonitor.tn.gov.in](https://chennaifloodmonitor.tn.gov.in/HomePage/Dashboard)
- [V] **GCC ICCC 2.0 (Sept 2026, very recent):**
  - Proposed **₹98.25 crore over five years** (₹1.90 crore one-time, ₹96.36 crore recurring) for a single system integrator.
  - Scope: 1,256 cameras, 65 rain gauges, 46 flood sensors, 40 flood-o-meters, 101 variable message displays, 17 boom barriers, an early warning system, and "Departmental data integration and APIs".
  - The final value will be set "through an open competitive tender". The previous O&M contract ended November 2025.
  - Sources: [The Hindu, 27 Sep 2026](https://www.thehindu.com/news/cities/chennai/chennai-corporation-plans-9825-cr-overhaul-of-command-centre/article71512749.ece); [DT Next](https://www.dtnext.in/news/chennai/over-rs-98-crore-allocated-for-5-year-iccc-operations-integration)
- [V] Related GCC tenders:
  - Subway boom-barrier tender estimated at ₹63.60–92.99 lakh, with 3-year maintenance, from GCC funds. — [The Hindu, 14 Nov 2024](https://www.thehindu.com/news/cities/chennai/gcc-to-install-automatic-boom-gates-in-17-flood-prone-subways-in-chennai/article68868344.ece)
  - Regional ICCC tenders worth ₹3.8 crore (May 2025). — [New Indian Express, 16 May 2025](https://www.newindianexpress.com/cities/chennai/2025/May/16/command-centres-on-the-anvil-to-tackle-region-specific-issues-in-chennai)
- [V] GCC allocated **₹100 crore** for northeast monsoon preparedness works in 2026 and rents 670 of its 1,320 motor pumps. — [Deccan Chronicle, 24 Sep 2026](https://www.deccanchronicle.com/southern-states/tamil-nadu/chennai-corporations-multi-pronged-approach-to-monsoon-preparedness-1990108)

**Mumbai precedent (CSR-funded academic system)**
- [V] mumbaiflood.in and the Mumbai Flood app are an HDFC-ERGO IIT Bombay Innovation Lab initiative **funded by HDFC ERGO**, run with the BMC capacity-building centre and IMD. Features include crowd reports of water level (ankle/knee/waist), nine water-level stations and station-stress status. The BMC drew on it during the August 2025 rains. — [Times of India, 22 Aug 2025](https://timesofindia.indiatimes.com/city/mumbai/iitbs-hyperlocal-forecast-aids-bmc-during-flooding/articleshow/123439032.cms); [Hindustan Times, 26 Jul 2025](https://www.hindustantimes.com/cities/mumbai-news/hyperlocal-rain-and-flood-alerts-for-mumbai-by-iit-b-and-imd-101753469849871.html); [Play listing](https://play.google.com/store/apps/details?id=com.mfws_react&hl=en)
- [V] Mid-day reports the Mumbai Flood Project's real-time waterlogging reports are "synced to Google Maps". I saw only the headline and did not verify the mechanism. — [Mid-day](https://www.mid-day.com/mumbai/mumbai-news/article/mumbai-rains-crowdsourced-data-to-power-mumbais-new-flood-monitoring-system-during-heavy-rains-23590554)

### Inferences
- [I] **Investor-relevant prior failure mode:** RiskMap ran this concept in Chennai during peak floods. It had high momentary usage and an MIT/Tata brand, yet did not become a durable product after 2019. Any pitch must explain why a crowd layer would persist this time; "the crowd is empty when needed" was already the team's council worry.
- [I] The only India flood-information products with sustained operation are government-built (TN-ALERT, RTFF, GCC EWS) or CSR plus academia (mumbaiflood.in by HDFC ERGO and IIT Bombay). This points to a **CSR-funded academic pilot embedded with GCC**, not a paid consumer app, as the realistic first structure for a VIT team.
- [I] FloodNet's per-sensor cost (about US$200–300) against GCC's existing 46 flood sensors and 40 flood-o-meters suggests GCC buys sensors through system-integrator contracts, not from small vendors directly. A student team's route into ICCC 2.0 is as a subcontractor or data-integration partner to whoever wins the integrator tender. [E] This is plausible but unverified.

### Gaps
- No public figure for TN-ALERT downloads or active users.
- No evidence on whether RTFF street-level forecasts are exposed via an API or open data.
- Why RiskMap Chennai ended after 2019 (funding or partnership) is not documented in what I found.
- PetaBencana's current annual budget and revenue are not public in the sources found.

---

## Q3. Who has budgets and pays today, how much, through what process, and how large are monsoon losses?

### Takeaway
Who pays for anything close to this in Chennai today:
1. **Police / city buying traffic intelligence from startups on annual contracts.** GCTP pays **₹96 lakh/year** to an IIT-Madras-incubated firm (Mandark Technologies) for a Google-traffic-API-based live monitoring tool [2023 report].
2. **GCC buying integrated command-centre systems** through large system-integrator tenders (₹98.25 crore over 5 years, Sept 2026).
3. **Insurers funding flood information as CSR or research** (HDFC ERGO → mumbaiflood.in) or building it in-house (ICICI Lombard's alert system with an IIT Bombay-incubated startup).

Quick-commerce and food-delivery platforms clearly feel the pain: order cancellations double, dark stores shut, rider logins fall. But they solve it in-house: Zomato built 650+ weather stations and gives the data away free, and Blinkit "blacklists" routes from rider feedback. I found no evidence of any of them buying third-party road passability data.

Loss pools are large. 2015 Chennai floods: insurer hit of about ₹4,800–5,000 crore [E]. Cyclone Michaung: state request of ₹19,692 crore; ₹11,000 crore loss [E] (Association of Indian Entrepreneurs, AIE); MSME losses of at least ₹3,000 crore [E]. Motor claims were a large part of both events.

### Cited Findings

**Government / police buyers (Chennai)**
- [V] [2023] The Chennai Metropolitan Police "allocated a budget of Rs. 96 lakh per year to the partnering company" for live traffic monitoring of 300 junctions and 1,000 roads using real-time Google Maps data, developed "in collaboration with IIT Chennai and a private company". — [LiveChennai, 20 Jun 2023](https://www.livechennai.com/detailnews.asp?newsid=67604)
- [V] GCTP named the partner as Mandark Technologies, "incubated at IITM Research Park", and said the tool uses "#Google #Traffic APIs". — [GCTP LinkedIn post, 21 Jun 2023](https://www.linkedin.com/feed/update/urn:li:activity:7077216379896041472)
- [V] By September 2025 the system was described as monitoring 270 junctions and about 1,000 roads "by gathering data from the paid service of Google Maps". — [The Hindu, 28 Sep 2025](https://www.thehindu.com/news/cities/chennai/gctp-adopt-live-monitoring-system-to-streamline-traffic-management-in-city/article70101554.ece)
- [V] GCC ICCC 2.0 tender: ₹98.25 crore over 5 years via open competitive tender, including EWS, APIs and flood sensors (see Q2). — [The Hindu, 27 Sep 2026](https://www.thehindu.com/news/cities/chennai/chennai-corporation-plans-9825-cr-overhaul-of-command-centre/article71512749.ece)
- [V] The 108 ambulance service is "fully funded by the government" and operated for the state by EMRI Green Health Services (GVK). — [New Indian Express, 15 Dec 2023](https://www.newindianexpress.com/states/tamil-nadu/2023/Dec/15/108-plans-to-bring-boat-ambulances-to-tamil-nadu-2641636.html)

**Quick-commerce and food delivery (pain is real, buying is not)**
- [V] Blinkit (Oct 2024): "As soon as our delivery partners update us about affected routes, we immediately blacklist those temporarily. Also, our proprietary weather stations actively communicate weather forecasts." Zepto: "certain areas in Bengaluru and Chennai were temporarily unserviceable due to heavy rains." — [BusinessLine, 16 Oct 2024](https://www.thehindubusinessline.com/companies/dining-out-quick-commerce-operations-suffer-disruptions-due-to-heavy-rainfall-in-bengaluru/article68760245.ece)
- [V] Mumbai (Aug 2025): platforms "suspended operations for several hours" in waterlogged areas; a cloud-kitchen operator said cancellations doubled; a Blinkit store manager cited 1,000–1,200 orders against a 1,500 target. Riders demanded the rain fee rise from ₹20 to ₹40. — [Economic Times, 19 Aug 2025](https://economictimes.indiatimes.com/tech/technology/heavy-rains-flooding-disrupt-delivery-business-in-mumbai/articleshow/123391592.cms)
- [V] Bengaluru pre-monsoon (May 2025):
  - A dark store fell from about 1,000 daily orders to 580 and 680 on the two worst days; another fell from 1,200 to 700 to 500.
  - Some dark stores shut because flood water entered.
  - Aggregators switch off service areas until they become accessible.
  - Source: [Economic Times](https://economictimes.indiatimes.com/tech/startups/heavy-rains-flooding-disrupt-delivery-business-in-bengaluru/articleshow/121347385.cms)
- [V] Delhi-NCR (Aug 2024): order cancellations and non-delivery "at hundreds of pin codes". A Swiggy Instamart rider said riders can upload a photo of weather and roads, and the company checks with the dark store and suspends deliveries. — [Economic Times](https://economictimes.indiatimes.com/tech/technology/heavy-rains-water-logging-dent-quick-commerce-food-delivery-dine-ins-across-north-india/articleshow/112473154.cms); [Business Standard, 13 Aug 2024](https://www.business-standard.com/industry/news/heavy-rains-impact-food-delivery-and-quick-commerce-in-north-india-124081300425_1.html)
- [V] Zomato has "about 700 real-time weather stations in 60 cities" and more than 2,600 rain shelters (2024). Zepto passes "100% of the rain surge incentive collected from customers" to riders. — [Economic Times, 14 Aug 2024](https://economictimes.indiatimes.com/news/india/after-extreme-summer-delivery-firms-taking-steps-to-protect-workers-from-rain-fury/articleshow/112513235.cms)
- [V] Weather Union (Zomato, May 2024):
  - 650+ stations in 45 cities, built with IIT Delhi CAS (Centre for Atmospheric Sciences).
  - Free API "as a Zomato Giveback" under CSR: "This data is too valuable to keep to ourselves or monetise."
  - Real-time data only, no forecasts.
  - Terms cap free use at 60,000 API calls per profile per financial year.
  - Sources: [CNBC TV18](https://www.cnbctv18.com/business/companies/zomato-weather-union-crowd-sourced-network-weather-stations-india-19408692.htm); [Gadgets360](https://www.gadgets360.com/apps/news/zomato-weather-union-crowd-supported-real-time-weather-monitoring-system-unveiled-5623309); [Weather Union T&C PDF](https://b.zmtcdn.com/data/file_assets/4f2b1aeb48ea8c87519e7f2bd652b6811715149430.pdf)
- [V] In May 2025 Zomato and Swiggy removed the rain-fee waiver for loyalty members, so rain surcharges became revenue for all users. — [Moneycontrol, 16 May 2025](https://www.moneycontrol.com/technology/zomato-gold-and-swiggy-one-users-now-face-a-rain-surcharge-on-food-orders-article-13028849.html)

**Motor insurers — Chennai 2015 and 2023**
- [V/E] 2015: "general insurers took a massive hit of about ₹5000 crore", the motor segment was the largest, and there were about 50,000 claims in total. New India Assurance alone paid 10,000 motor and 4,000 non-motor claims. Michaung early estimate: 10,000+ motor claims industry-wide. — [BusinessLine, 8 Dec 2023](https://www.thehindubusinessline.com/money-and-banking/general-insurers-see-a-surge-in-claims-from-flood-hit-customers-total-value-may-touch-2015-level/article67619229.ece)
- [V/E] 2015 insurer hit "around Rs 4,800 crore". Michaung claims were 30–35% lower than 2015, which Bajaj Allianz attributed to a "proactive response from the public". — [Business Standard, 24 Dec 2023](https://www.business-standard.com/finance/insurance/insurance-claims-drop-30-35-during-chennai-floods-compared-to-2015-123122400503_1.html)
  - Conflict: ₹4,800 crore vs ₹5,000 crore for 2015. Both are press estimates.
- [V] On 8 Dec 2023, 13 insurers told the TN government they had received about 2,320 motor claims so far (600 bikes, 1,275 cars, 445 commercial vehicles). — [DT Next, 8 Dec 2023](https://www.dtnext.in/news/tamilnadu/fin-min-meets-insurance-companies-automobile-dealers-to-expedite-insurance-claims-753164)
- [V] IRDAI temporarily raised the motor-claim surveyor threshold from ₹50,000 to ₹1,00,000 for Michaung claims. — [TaxGuru, quoting IRDAI circular of 18 Dec 2023](https://taxguru.in/corporate-law/insurance-claims-relating-cyclone-michaung-subsequent-heavy-rains-floods.html)
- [V] Engine damage from cranking a submerged car is typically not covered. A full engine repair "can cost you around Rs 1.5 lakh". — [The News Minute, 9 Dec 2023](https://www.thenewsminute.com/tamil-nadu/tn-finance-min-urges-insurance-firms-to-quickly-settle-flood-vehicle-damage-claims); [The Hindu, 7 Dec 2023](https://www.thehindu.com/news/national/tamil-nadu/cyclone-michaung-here-is-all-you-need-to-know-about-vehicle-insurance-claims/article67613623.ece)
- [V] ICICI Lombard built an in-house Automated Weather Alert System (AWAS) with Bhugol GIS, an IIT Bombay-incubated startup, to send proactive advisories to clients. It also partners with global catastrophe-modelling firms. — [Industrial Economist, 7 Jun 2025](https://industrialeconomist.com/icici-lombard-bets-big-on-climate-risk-strategy/)
- [V] RMSI sells India flood risk analytics to insurers at pincode and lat/long level (PIER, India FloodRisk 2.0, covering 19,000+ pincodes), i.e. underwriting and catastrophe risk, not real-time road data. — [RMSI PIER](https://rmsicropalytics.com/pier/); [RMSI India FloodRisk](https://www.rmsi.com/india-floodrisk-model/)
- [V] HDFC ERGO funds mumbaiflood.in through its IIT Bombay lab (see Q2). — [Times of India, 22 Aug 2025](https://timesofindia.indiatimes.com/city/mumbai/iitbs-hyperlocal-forecast-aids-bmc-during-flooding/articleshow/123439032.cms)

**Emergency services (108)**
- [V] During Michaung on 4 Dec 2023: about 70 ambulances in Chennai city; 150 calls handled; responders reached people "wherever the areas are reachable". — [The Hindu, 4 Dec 2023](https://www.thehindu.com/news/cities/chennai/cyclone-michaung-army-108-ambulance-network-take-up-rescue-efforts-in-chennai/article67604001.ece)
- [V] From 4–6 Dec 2023, crews handled 1,019 fainting cases, 256 trauma cases and 442 pregnant women shifted from flooded hospitals. Crews improvised boats from cans and spine boards, and EMRI planned to propose boat ambulances. — [New Indian Express, 15 Dec 2023](https://www.newindianexpress.com/states/tamil-nadu/2023/Dec/15/108-plans-to-bring-boat-ambulances-to-tamil-nadu-2641636.html)
- [V] [OLD] In the 2021 floods, "the response time got delayed as the crew had to navigate through rains as well as waterlogged areas". — [New Indian Express, 13 Nov 2021](https://www.newindianexpress.com/cities/chennai/2021/Nov/13/chennai-floods-this-gritty-108-team-waded-through-hip-deep-water-to-shift-37-patients-from-gh-2382992.html)

**Monsoon / cyclone loss quantification**
- [V] TN sought ₹19,692 crore from the Centre for Michaung (₹7,033 crore interim plus ₹12,659 crore permanent). — [New Indian Express, 15 Dec 2023](https://www.newindianexpress.com/states/tamil-nadu/2023/Dec/15/michaunged-and-bruised-tnseeks-rs-20k-crore-aid-from-centre-2641648.html); [The Hindu, 14 Dec 2023](https://www.thehindu.com/news/national/tamil-nadu/cyclone-michaung-tn-cm-stalin-seeks-7033-crore-as-interim-relief-and-12659-crore-as-permanent-relief-from-centre/article67637582.ece)
- [V] TN later sued in the Supreme Court over about ₹38,000 crore of combined relief requests (Michaung plus the southern-district floods). — [The Hindu, 3 Apr 2024](https://www.thehindu.com/news/national/tamil-nadu/tn-moves-sc-against-centre-seeks-release-of-19692-crore-relief-for-cyclone-michaung-damage/article68022892.ece)
- [E] AIE estimated Michaung losses at "over Rs 11,000 crore" and said about 25 lakh people in the four affected districts were hit, including gig delivery workers and auto/taxi drivers. — [Economic Times, 10 Dec 2023](https://economictimes.indiatimes.com/news/india/loss-due-to-cyclone-michaung-expected-to-be-over-rs-11000-crore/articleshow/105882259.cms)
- [E] MSME losses of "a minimum of ₹3,000 crore" (government official, conservative); Ambattur Industrial Estate about ₹2,000 crore. — [CNBC TV18, 12 Dec 2023](https://www.cnbctv18.com/environment/cyclone-michaung-impact-msme-sector-may-have-suffered-losses-greater-than-3000-crore-18548741.htm)
- [V] GCC pegged its own Michaung damage and response cost at ₹990 crore. — [New Indian Express, 13 Dec 2023](https://www.newindianexpress.com/states/tamil-nadu/2023/Dec/13/greater-chennai-corporation-pegs-michaung-damage-at-rs-990-crore-2641073.html)
- [V] Southern Railway lost ₹35 crore in passenger revenue (605 trains disrupted). About 600+ flights were cancelled. Ports were "crippled". — [Business Today, 20 Dec 2023](https://www.businesstoday.in/magazine/the-buzz/story/cyclone-michaung-chennais-image-as-an-industrial-hub-has-taken-a-hit-410268-2023-12-20)
- [V] Telecom and power failures during Michaung: power was deliberately cut; exchanges in Tambaram, Adyar and Velachery went down; ACT Fibernet had about 35% of its base down in the first 48 h. — [New Indian Express, 5 Dec 2023](https://www.newindianexpress.com/states/tamil-nadu/2023/Dec/05/cyclone-michaung-mobile-networks-downedby-outagesin-chennai-2638740.html); [The Hindu, 24 Dec 2023](https://www.thehindu.com/news/national/tamil-nadu/internet-service-providers-work-round-the-clock-to-restore-services-in-rain-affected-areas/article67672142.ece)
- [V] TN Police rescued 1,16,592 people and received 3,034 SOS calls. — [The Hindu, 15 Dec 2023](https://www.thehindu.com/news/national/tamil-nadu/cyclone-michaung-tamil-nadu-police-rescued-116-lakh-people-stranded-in-flood-waters-says-dgp/article67642146.ece)

**Consumer willingness to pay (academic; mostly [OLD])**
- [V] [OLD] Lyon (Optymod'Lyon), 2017: "A strong majority ... were unwilling to pay, mainly for economic reasons and the availability on the market of free information." — [Paper](https://exa.ai/library/publication/3240fbv2f4g)
- [V] [OLD] Korea, 2012: mean WTP for real-time route guidance of 4,034 won/year (short trips) and 4,884 won/year (medium). — [Paper](https://exa.ai/library/publication/q89vnw7fr23)
- [V] Greece, 2026 (650 motorway drivers): open to pay a "small price per trip" for an emergency-notification app but "sensitive to cost and ... willing to accept ads as an integrated function of a free system". — [Paper](https://exa.ai/library/publication/xppvjl2g6rr)
- [V] [OLD] Taiwan, 2015: 16% zero bids for real-time freeway traffic information. — [Paper](https://exa.ai/library/publication/k8w9kc84q3b)
- I found no India-specific WTP study for flood or traffic information.

### Inferences
- [I] **Answer to "who pays, how much, through what process":**
  - Chennai's traffic police have paid about ₹1 crore/year to a local IIT-incubated startup for a traffic-intelligence dashboard built on Google APIs. This is the closest local price anchor for a city-facing road-intelligence product. Procurement appears to be a police-department vendor engagement; exact mode unknown.
  - Larger money flows through GCC system-integrator tenders (ICCC, ₹98 crore over 5 years), for which a 3-student team is ineligible as prime bidder.
  - Fleets (Zomato, Blinkit, Swiggy) internalise the problem and treat weather data as a CSR giveaway, which undercuts a "sell data to fleets" thesis.
- [I] Insurers are the most logical private payer: Michaung 2023 motor claims ran to 10,000+ (insurer estimate), and the 2023 claims drop was credited to public precaution. But the observed buying pattern is in-house builds (ICICI Lombard AWAS) or CSR plus academia (HDFC ERGO and IIT Bombay), not API purchases from startups. An insurer pilot would most likely start as CSR or innovation-lab funding.
- [I] 108/EMRI's binding constraint during Michaung was physical reachability (boats), not route information. A navigation product helps only at the margin of "reachable but which way"; it is weak as a paying customer.
- [I] Michaung's telecom collapse supports the offline-first design but also limits crowd reporting at peak. Both the team's thesis and the incumbents' crowd features degrade together.

### Gaps
- The procurement mode and current status of the GCTP–Mandark contract (renewal, tender vs nomination) are not found. The ₹96 lakh figure comes from a single 2023 local outlet and is not confirmed by a tender document.
- No evidence any quick-commerce, food-delivery, Porter, Dunzo-successor or ride-hailing firm has bought third-party flood or passability data in India.
- No Chennai-specific Swiggy/Zomato/Blinkit downtime figures for Michaung were found.
- Whether Weather Union is still operating in 2026 is unconfirmed: the site was live in search results and a March 2025 post describes it, but I found no 2026 status.
- An ICICI Lombard investor PDF lists "Cyclone Michaung 2023 120.00 25.00 …" and "Chennai floods 2015 150.00 49.40 …" in a catastrophe table, but the column headers (units, whether industry or ICICI Lombard losses) were not captured. Do not use those figures without re-reading the PDF. — [stockscans PDF](https://www.stockscans.in/document/dlv3ujbg4ycz7ncqaiveke9e.pdf)
- No figure for monsoon-specific GMV (gross merchandise value) loss at Indian delivery platforms; companies did not disclose it.

---

## Q4. Pricing benchmarks for routing, traffic and incident APIs, and for flood-risk data APIs

### Takeaway
Routing and traffic calls are cheap and commoditised in India, with large free tiers:
- **Google (India SKUs):** 70,000 free Compute Routes Essentials calls per month, then US$1.50 per 1,000; traffic-aware ("Pro") routing costs US$3.00 per 1,000 after 35,000 free.
- **Ola Maps:** 100,000 free events per month (from 1 Sept 2026).
- **TomTom:** 2,500 free incident-details calls per month.

Flood and weather-risk data is sold through enterprise contracts with "contact sales" pricing (Ambee, Tomorrow.io premium Flood Index). Tomorrow.io's public AWS Marketplace listing shows a US$1,000,000 12-month contract unit. A road-passability feed would have to be priced as a premium enterprise layer, because per-call commodity routing prices leave almost no room.

### Cited Findings
- [V] **Google Maps Platform, India pricing (from 1 Mar 2025):**
  - Routes Compute Routes Essentials (India): 70,000 free per month; US$1.50 per 1,000 up to 5M; US$0.38 per 1,000 above.
  - Compute Routes Pro (India): 35,000 free; US$3.00 / US$0.75.
  - Compute Routes Enterprise (India): 7,000 free; US$4.50 / US$1.14.
  - Roads Speed Limits (India): US$12 per 1,000.
  - Sources: [Google India pricing list](https://developers.google.cn/maps/billing-and-pricing/pricing-india); [India billing FAQ](https://developers.google.com/maps/billing-and-pricing/india)
- [V] Google's Pro SKU is triggered by `routingPreference` TRAFFIC_AWARE / TRAFFIC_AWARE_OPTIMAL. Enterprise is triggered by two-wheeler routing, tolls, and traffic information on polylines. — [SKU details](https://developers.google.com/maps/billing-and-pricing/sku-details)
- [V] India pricing applies only to developers with an Indian billing address and mostly Indian usage. — [Google Maps Platform India](https://mapsplatform.google.com/intl/en_in/pricing/)
- [V] **Ola Maps:**
  - From 1 Sept 2026, the first 100,000 monthly events cost ₹0; then tiered (e.g. Dynamic Maps at ₹0.012 per request in Tier 2); prepaid credit model. — [Ola Maps pricing](https://maps.olakrutrim.com/pricing)
  - In July 2024 it offered 5M free calls per API per month and prices at 50% of Google's. That offer has evidently been replaced. — [Ola Krutrim blog, 18 Jul 2024](https://tech.olakrutrim.com/ola-maps-made-for-india-priced-for-india/)
- [V] **TomTom (2026 pricing page):**
  - Traffic Incidents API Details: 2,500 free requests per month.
  - Traffic Flow Segment Data: 20,000 free per month.
  - Routing: 20,000 free per month.
  - Traffic tiles: 200,000 free per month.
  - Enterprise and automotive hazard alerts are custom-priced.
  - Source: [TomTom pricing](https://developer.tomtom.com/pricing)
  - Per-1,000 overage prices were not rendered on the page. A secondary aggregator cites routing at US$0.75–6.00 per 1,000 and tiles at US$0.08 per 1,000; treat as unverified. — [APIbenchmarks](https://apibenchmarks.com/maps/tomtom)
- [V] **HERE:** a "Limited Plan" without payment details allows 1,000 daily requests at capped RPS (requests per second) per service. — [HERE RPS limits page](https://www.here.com/get-started/pricing/rps-limits-excluded-use-cases)
  - Secondary aggregator only: Traffic (real-time and incidents) at US$2.50 per 1,000 after a free quota. Not verified on HERE's own pricing page, which did not render. — [pricingapis.com](https://pricingapis.com/maps/here-maps)
- [V] **Ambee** (Indian climate-data firm): flood API offered; pricing is "Enterprise agreements" and "contact sales", with no public rate card. — [Ambee pricing](https://www.getambee.com/pricing); [Ambee Flood API](https://www.getambee.com/api/flood)
- [V] **Tomorrow.io:**
  - Flood Index is "a premium feature … contact … sales". — [Tomorrow.io support](https://support.tomorrow.io/hc/en-us/articles/38449450658068-Flood-Index-Premium-Layer)
  - AWS Marketplace lists the Weather Intelligence Platform at "$1,000,000.00" per 12-month contract unit (unit definition unclear). — [AWS Marketplace](https://aws.amazon.com/marketplace/pp/prodview-f44etcmaaozly)
  - Hobby and Builder tiers are reported at US$50 and US$300 per month, but that source notes the figures were supplied by a requester and "verify before quoting". — [apis.io](https://apis.io/plans/tomorrow/tomorrow-plans-pricing/)
- [V] **Zomato Weather Union:** free, with 60,000 calls per profile per financial year; it reserves the right to charge heavy enterprise users. — [Weather Union](https://www.weatherunion.com/); [T&C PDF](https://b.zmtcdn.com/data/file_assets/4f2b1aeb48ea8c87519e7f2bd652b6811715149430.pdf)
- [V] **Google Floods API** is provided to organizations; no public price found. — [Google blog, 18 Aug 2026](https://blog.google/innovation-and-ai/technology/research/flood-prediction-ai/)
- [V] **Waze for Cities** data is free to government partners in exchange for closure data. — [NAP](https://www.nationalacademies.org/read/28690/chapter/11)
- [V] **SaaS price signal from a small Indian flood-alert vendor:** "Playtogo" lists ₹4,999/month for city corporations. Its claims (18+ cities, 2M+ alerts) are unverified marketing and the site looks low-credibility; included only as a weak signal. — [playtogo](https://playtogo.temarosa.info/)

### Inferences
- [I] At Google India's Pro rate (US$3 per 1,000 traffic-aware routes), a fleet making 1M route calls per month pays roughly US$2,900. A passability add-on priced per call would struggle to exceed that. The more realistic structure is a flat per-city, per-season subscription (an alert or feed licence), benchmarked against the ₹96 lakh/year GCTP dashboard contract at the top end and very small SaaS fees at the bottom. [E] This positioning is unvalidated.
- [I] A Rs 0 team can prototype on free tiers: Google India 70k Essentials per month, Ola 100k, TomTom 2.5k incidents. Reselling Google traffic data is constrained by Google's terms, which are not reviewed here.

### Gaps
- Primary-source HERE per-1,000 prices and TomTom per-1,000 overage prices were not retrieved (the pages did not render).
- No India-specific pricing found for Google Floods API, Ambee flood, or RMSI PIER.
- Google Maps Platform terms on caching and combining Google traffic with third-party layers were not reviewed.

---

## Q5. Regulation and liability: DPDP Act 2023 and Rules 2025 for location data; liability for navigation advice

### Takeaway
The DPDP Rules were notified on 13–14 Nov 2025. Core fiduciary obligations (notice, consent, security, data-principal rights, breach reporting) become enforceable **18 months later, i.e. about 13 May 2027**. That falls inside any startup's first 12 months, so consent-based, minimised location handling should be built in from day one.

On navigation liability, the November 2024 Bareilly/Budaun case shows Indian police will name a navigation provider in an FIR for culpable homicide after a flood-damaged bridge death. Lawyers quoted say intermediary safe harbour under the IT Act may protect platforms unless they failed to fix data after being given timely, correct information. A product that claims "passable" carries more exposure than one that issues hedged risk warnings.

### Cited Findings
- [V] The DPDP Rules 2025 were notified on 14 Nov 2025 (PIB; gazette dated 13 Nov 2025), with "an eighteen-month period for phased compliance". Every fiduciary must give a separate, clear consent notice explaining the specific purpose. Consent Managers must be India-based companies. — [PIB explainer PDF](https://static.pib.gov.in/WriteReadData/specificdocs/documents/2025/nov/doc20251117695301.pdf)
- [V] Commencement:
  - Rules 1, 2 and 17–21 (the Board) took effect immediately.
  - Rule 4 (Consent Managers) takes effect after 1 year, i.e. 13 Nov 2026.
  - Rules 3, 5–16, 22 and 23 (notice, security, breach, children, rights, cross-border) take effect after 18 months, i.e. 13 May 2027.
  - Sources: [CADP full text](https://cadp.in/resources/official-texts/dpdp-rules-2025/); [Bar & Bench, 17 Nov 2025](https://www.barandbench.com/view-point/meity-notifies-final-digital-personal-data-protection-rules-2025); [EY](https://www.ey.com/content/dam/ey-unified-site/ey-com/en-in/pdf/2025/11/dpdp-act-and-rules.pdf)
- [V] Specific obligations:
  - Breach intimation to the Board "without delay", then a detailed report within 72 hours.
  - Grievances answered within 90 days.
  - Consent Manager minimum net worth ₹2 crore.
  - Sources: [KPMG](https://assets.kpmg.com/content/dam/kpmgsites/in/pdf/2025/11/dpdp-rules-2025-guidance-to-dpdp-act-implementation.pdf); [Mondaq, 20 Nov 2025](https://www.mondaq.com/india/data-protection/1708164/digital-personal-data-protection-rules-2025-notified)
- [V] The Rules restrict tracking or behavioural monitoring of children (Rule 10 / Schedule 4 exemptions). — [Bar & Bench](https://www.barandbench.com/view-point/meity-notifies-final-digital-personal-data-protection-rules-2025)
- [V] **Bareilly/Budaun, 24 Nov 2024:**
  - Three men died when their car fell off a bridge whose front portion collapsed in floods "earlier this year … but this change had not been updated in the system".
  - An FIR under BNS section 105 (culpable homicide not amounting to murder) named 4 PWD engineers and "unknown persons"; a Google Maps regional officer was brought under investigation.
  - Google said it was "working closely with the authorities". Google removed the route four days later.
  - Sources: [The Hindu, 26 Nov 2024](https://www.thehindu.com/news/national/uttar-pradesh/bareilly-bridge-car-death-google-maps-police-case/article68912720.ece); [Economic Times](https://economictimes.indiatimes.com/news/india/pwd-google-maps-officials-booked-in-bareilly-bridge-death-case/articleshow/115668424.cms); [ETV Bharat](https://www.etvbharat.com/en/!state/bareilly-bridge-accident-google-removes-route-from-map-enn24112705234)
- [V] Legal views quoted by the BBC:
  - The IT Act gives platforms like Google Maps "intermediary" status, which protects them, "if it can be proven that the platform did not rectify its data despite being given correct, timely information, then it might be held liable for negligence."
  - Another expert says terms of service put the onus on users' judgement.
  - Source: [BBC, 28 Nov 2024](https://www.bbc.com/news/articles/cly23yknjy9o)
- [V] Incumbent disclaimers:
  - Google India: "use Google Maps as a helpful guide but … always remain alert and exercise caution". — [Google India blog, 6 Nov 2025](https://blog.google/intl/en-in/products/explore-communicate/google-maps-in-india-keeping-you-informed-with-new-safety-disruption-alerts/)
  - Weather Union T&C: "Zomato accepts no responsibility … for consequences and/or losses". — [T&C PDF](https://b.zmtcdn.com/data/file_assets/4f2b1aeb48ea8c87519e7f2bd652b6811715149430.pdf)

### Inferences
- [I] The team's earlier move from passive "Haven Mode" location learning to explicit saved places fits DPDP purpose-limitation and consent requirements.
- [I] A fleet B2B model, where the fleet operator is the data fiduciary for its riders' traces and the startup is a data processor under contract, is cleaner under DPDP than collecting consumer locations directly.
- [I] "Traversal silence", i.e. inferring passability from vehicles that drive through without reporting, needs continuous location traces. Under DPDP this requires a lawful basis, which in practice means consent through the fleet's own rider app. Riders are gig workers, and consent dynamics there may attract scrutiny.
- [I] On liability, the system's "no absolute-safety claims" verifier and fail-closed template design match the hedging incumbents use. The Bareilly case suggests the risk peaks when a known closure was reported and not reflected. A product that ingests official closures (GCC barrier states, GCTP posts) must show provable latency to keep the "timely information" negligence argument at bay.

### Gaps
- No outcome found for the Google Maps angle of the Bareilly investigation (charges or exoneration).
- No Indian court ruling found specifically on navigation-app liability.
- I found no DPDP guidance specific to location data. The Act treats it as personal data generally; there is no special category for it. Also unexamined: whether the "legitimate uses" in DPDP §7, such as disaster or medical emergencies, could cover flood-time processing. That needs a law-firm opinion.
- Consumer Protection Act exposure for paid navigation advice was not examined.

---

## Q6. Funding paths: government challenges, CSR, climate-tech grants (India, 2026)

### Takeaway
Non-dilutive money relevant to a VIT Chennai team exists in the ₹1 lakh to ₹20 lakh range, but most of it requires an incorporated, DPIIT-recognised startup and often an MVP. The most directly matched sources:
- **StartupTN TANSEED:** up to ₹15 lakh for green-tech, rural-impact or women-led startups, for 3% equity; editions run roughly annually, the 8th closed 20 Dec 2025.
- **Bharat WIN (Ministry of Jal Shakti):** an urban-flooding early-warning problem statement; ₹1 lakh proof-of-concept awards; grant-in-aid needs a 10% cash co-investment; 2026 deadline 31 Aug 2026, already passed.
- **Climate challenges:** EarthON/Greenovation and EcoHub, up to ₹20 lakh non-dilutive.
- **CSR plus academic lab model:** HDFC ERGO funding IIT Bombay's mumbaiflood.in.

### Cited Findings
- [V] **TANSEED 8.0:**
  - Up to ₹15 lakh for Green Tech, Rural Impact and Women-led startups; up to ₹10 lakh for others; StartupTN takes a 3% "support stake".
  - Requirements: registered in Tamil Nadu and with StartupTN, plus DPIIT recognition.
  - Funds may be used for prototype development, a market-ready product, or small-scale pilot production.
  - Applications ran 6–20 Dec 2025; 169 startups sanctioned since 2021.
  - Sources: [TN govt press release PDF](https://cms.tn.gov.in/cms_migrated/document/press_release/pr051225_e_2920.pdf); [BusinessLine, 5 Dec 2025](https://www.thehindubusinessline.com/news/national/startuptn-invites-applications-for-8th-edition-of-tanseed/article70362374.ece); [YourStory](https://yourstory.com/2025/12/startuptn-invites-applications-for-tanseed-rs-15-lakh-for-early-stage-startups)
  - ₹2.9 crore was disbursed to 23 TANSEED beneficiaries in February 2026. — [LinkedIn (StartupTN event)](https://www.linkedin.com/feed/update/urn:li:activity:7432010374805356544)
- [V] **Bharat WIN (DoWR, Ministry of Jal Shakti):**
  - Open call for startups and MSMEs; deadline extended to 31 Aug 2026.
  - Focus areas include urban hydrology, flood management, and an early-warning system for "GLOFs and urban flooding" (problem P07).
  - 19 hackathon teams received ₹1 lakh each for PoCs.
  - Grant-in-aid requires a 10% cash co-investment by the startup.
  - Note: this is from a third-party grant aggregator summarising the official call; verify on the Bharat WIN portal. — [GrantedAI listing](https://grantedai.com/grants/bharat-water-innovation-network-bharat-win-open-call-for-startups-and-ms-department-of-water-resources-river-deve-2a61119b)
- [V] **Greenovation Urban Climate Resilience Challenge (EarthON Foundation and Greenovation Hub, supported by Startup India / DPIIT):** up to ₹20 lakh non-dilutive plus a path to ₹1 crore investment. Includes a "climate data and finance" track. Requires full-time founders and incorporation within 10 years. 2026 deadline was 24 May 2026, now closed. — [EarthON](https://earthonfoundation.org/greenovation-urban-climate-resilience-challenge/); [StartupGrantsIndia](https://www.startupgrantsindia.com/greenovation-urban-climate-resilience-challenge)
- [V] **EcoHub.IN (Re Sustainability and Foundation for Resilience Actions):** ₹5–20 lakh non-dilutive, ₹1 lakh/month honorarium for 6 months, residential incubation in Hyderabad. Student founders are allowed if they have an MVP and an incorporated Indian company. Deadline 31 Jul 2026 (passed). — [AndPurpose EcoHub](https://andpurpose.world/eco-hub/)
- [V] **SAMRIDH Impact Accelerator 2026:** listed as up to ₹1 crore in grant, debt or equity for climate-tech at TRL 4+ (aggregator listing only). — [StartupGrantsIndia](https://www.startupgrantsindia.com/greenovation-urban-climate-resilience-challenge)
- [V] **SAAF Cities 2.0 (Villgro, headquartered at IIT Madras Research Park, with HDFC Bank Parivartan):** ₹2.4 crore shared grant pool to deploy with urban local bodies, but scoped to waste, wastewater and water bodies, and requires proven pilots. Only an adjacent fit. — [StartupGrantsIndia](https://www.startupgrantsindia.com/saaf-cities-2-0-program-by-villgro-and-hdfc-bank-parivartan-308)
- [V] **CSR / academic models:**
  - HDFC ERGO funds the IIT Bombay lab behind mumbaiflood.in (Q2).
  - Zomato's Weather Union is run under its CSR "Zomato Giveback" (Q3).
  - RiskMap Chennai was funded by Tata Trusts via the MIT Tata Center [OLD] (Q2).
- [V] **World Bank precedent:** Chennai's ₹107.2 crore RTFF was World Bank-financed through TNUIFSL. Large flood-information builds in TN have gone through multilateral-financed consultancies. — [The Hindu, 22 Oct 2025](https://www.thehindu.com/news/cities/chennai/chennai-gets-indias-first-real-time-flood-forecast-system/article70186744.ece)

### Inferences
- [I] For a team with ₹0 budget, the realistic sequence is:
  1. University or credited research funding and hackathons now.
  2. Incorporate and obtain DPIIT recognition.
  3. Apply to the next TANSEED edition (if the annual cadence holds, the call would be around December 2026; the "Green Tech" category gives the ₹15 lakh cap).
  4. Target climate challenges (next Greenovation, EcoHub and Bharat WIN cycles).

  The FloodNet and mumbaiflood.in pattern suggests a parallel track: pitch an insurer's CSR or innovation arm (HDFC ERGO, ICICI Lombard) for a Chennai pilot co-designed with GCC.
- [I] Grant money will likely precede revenue by 6–12 months, so a pitch should not count grant money as revenue.

### Gaps
- No primary MeitY TIDE 2.0, NIDHI-PRAYAS, or Smart India Hackathon 2026 flood problem statements were confirmed in this pass.
- Exact 2026–27 TANSEED (9.0) dates are not yet announced in the sources found.
- No India CSR database query was done to quantify flood or disaster-resilience CSR spend by insurers.

---

## Q7. Synthesis for the key questions: who pays today and what dominates for free; fastest credible revenue path for a 3-student, ₹0 team

### Takeaway
- **Who pays today:** Chennai's traffic police (about ₹96 lakh/year to an IIT-M-incubated traffic-intelligence vendor, 2023 report), GCC through large command-centre tenders (₹98.25 crore over 5 years, Sept 2026), the World Bank and the state (₹107.2 crore RTFF), and insurers through CSR or in-house builds.
- **Who does not pay:** consumers (free Google Maps plus WhatsApp and X; WTP studies show free alternatives suppress WTP) and delivery fleets, which build in-house and give weather data away.
- **Fastest credible revenue path** (my judgement, based on the precedents above): a paid municipal or police pilot, delivered by or with an existing GCC/GCTP vendor, that converts GCC's own flood sensors, boom-barrier states and the 290-point waterlogging list into a road-segment closure and passability feed pushed to Google, Mappls and the ICCC.

### Cited Findings (anchors re-used from above)
- ₹96 lakh/year GCTP contract with an IITM-incubated startup — [LiveChennai](https://www.livechennai.com/detailnews.asp?newsid=67604); [GCTP LinkedIn](https://www.linkedin.com/feed/update/urn:li:activity:7077216379896041472)
- GCC ICCC 2.0 includes "Departmental data integration and APIs" and an Early Warning System, single system integrator, open tender — [The Hindu, 27 Sep 2026](https://www.thehindu.com/news/cities/chennai/chennai-corporation-plans-9825-cr-overhaul-of-command-centre/article71512749.ece)
- GCTP motivation that closures "are not updated on Google Maps immediately"; Lepton relays them within 15 minutes [OLD] — [The Hindu, 20 Oct 2022](https://www.thehindu.com/news/cities/chennai/chennai-police-launch-roadease-app-to-give-real-time-updates-on-traffic-diversion-road-closure/article66036822.ece)
- Bareilly: liability hinges on failing to update known closures — [BBC](https://www.bbc.com/news/articles/cly23yknjy9o)
- Delivery firms build in-house and give data away free — [CNBC TV18](https://www.cnbctv18.com/business/companies/zomato-weather-union-crowd-sourced-network-weather-stations-india-19408692.htm); [BusinessLine](https://www.thehindubusinessline.com/companies/dining-out-quick-commerce-operations-suffer-disruptions-due-to-heavy-rainfall-in-bengaluru/article68760245.ece)
- Free alternatives suppress consumer WTP [OLD] — [Lyon study](https://exa.ai/library/publication/3240fbv2f4g)
- Prior Chennai crowd-flood-map pilot (RiskMap, 2017–19) ended as a pilot [OLD] — [riskmap.mit.edu/india](https://riskmap.mit.edu/india)

### Inferences
- [I] **Ranked revenue paths** (fastest and most credible first). These are judgements, not validated:
  1. **Municipal or police data-integration pilot**, priced as a small annual service fee under the ₹96 lakh GCTP anchor. Reach it either via a subcontract to the ICCC 2.0 system integrator (tender happening now), or as a GCTP add-on alongside the existing Mandark or Lepton vendor relationships. Value: machine-readable subway, barrier and closure state with timestamps and latency proof, pushed to maps.
     - Risks: long sales cycles; prime-bid eligibility (turnover and experience criteria are likely); the state already has RTFF and EWS.
     - Why first: the payer exists, the budget line exists, and the need is stated publicly.
  2. **Insurer CSR or innovation-lab pilot** (HDFC ERGO / ICICI Lombard model): a Chennai "move your car before it floods" advisory using the passability or exposure layer, judged on motor claims avoided.
     - Michaung motor claims of 10,000+ (insurer estimate) and the insurer comment that public precaution cut claims 30–35% make the value case legible.
     - Likely structured as a grant or research funding first, not data revenue.
  3. **Fleet passability API (the council's "flip-to-BUILD" bet).** Least supported by evidence so far: no Indian fleet is shown buying third-party flood data; Zomato gives weather data away; Blinkit blacklists routes from rider input.
     - A credible version is probably a free pilot with one mid-size Chennai logistics or quick-commerce operator: their rider traces in, passability out, with DPDP-compliant processor terms. Revenue would come later, if at all.
  4. **Consumer app.** Not credible as a revenue path (Google default, free alternatives, low WTP, RiskMap precedent).
- [I] **What a skeptical investor would accept:** the sizes of the loss pools (₹19,692 crore TN request; ₹4,800–5,000 crore 2015 insurer losses [E]; ₹11,000 crore [E] Michaung) show the problem is real. But the evidence is that budgets flow to government system integrators and in-house builds, not to startups selling passability data. The team's near-term revenue claim should be capped at one pilot contract (lakhs, not crores) plus non-dilutive grants (₹10–20 lakh scale), and should name the 2026 ICCC 2.0 tender and the GCTP vendor precedent as the specific channels.

### Gaps
- No interviews or primary evidence of demand from GCC, GCTP, any fleet or any insurer for road-segment passability specifically. This is the single biggest evidence gap for the investor case.
- ICCC 2.0 tender eligibility criteria (turnover, experience, consortium or subcontract rules) are not yet public in the sources found.
- No data on how many Chennai fleet vehicles or riders operate during the northeast monsoon, so the potential "traversal-silence" signal density cannot be sized from public sources.
