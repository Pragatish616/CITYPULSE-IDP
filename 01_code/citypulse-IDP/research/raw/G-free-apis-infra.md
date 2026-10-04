# Strand G — Free-Tier & Minimum-Cost APIs, Services and Infrastructure

**Research Agent G · CityPulse AI · compiled 2026-09-12**

Scope: the **cost and infrastructure layer** around the hazard-data work already completed in
[Strand C](./C-data-sources.md). Strand C answered *what data can we get*. This strand answers
*what can we run it on, and what does it cost three students with no budget*.

**I did not re-research hazard data sources.** Where this report names a hazard API (TomTom,
Open-Meteo, IMD) it only cites Strand C's finding and adds the cost/infra consequence.

Every figure below was taken from the **vendor's own current pricing or docs page**, fetched on
**2026-09-12**, unless marked otherwise. Blog posts, "free tier roundup" sites and my own prior
knowledge were **not** treated as evidence. Where a vendor no longer publishes a number publicly,
I say so rather than substituting a remembered figure.

**FX rate used throughout:** **₹94.49 = US$1**, the US Federal Reserve H.10 release rate for
2026-09-04 ([source](https://www.federalreserve.gov/releases/h10/current/)). INR figures are
rounded. EUR figures are left in EUR — I could not verify a EUR/INR rate from a primary source, so
I do not convert them.

---

## 0. Verification legend

| Mark | Meaning |
|---|---|
| ✅ **VERIFIED** | Vendor's own page fetched today; the quoted number appears on it |
| 🟡 **PARTIAL** | Vendor page fetched but the specific number was not on it; figure comes from a secondary source and is labelled as such |
| ⚠️ **UNVERIFIED** | Could not confirm from a primary source — treat as a lead, not a fact |
| 🔴 **TRAP** | Verified, and it will hurt you — see §9 |

**Three things changed in 2025–2026 that invalidate most "free tier" advice online, including the
premises in my own task brief.** They are the most important findings in this report:

1. **AWS no longer has a 12-month t2/t3.micro free tier.** It is now a credit model:
   **$100 on signup, up to $100 more, max $200, account closes after 6 months.** ✅
2. **Oracle Cloud halved the Always Free Ampere A1 allowance** from 4 OCPU / 24 GB to
   **2 OCPU / 12 GB**, with no public announcement (July 2026). ✅
3. **Google's Gemini free tier explicitly trains on your prompts.** The paid tier does not. For an
   app that puts a user's live location into a prompt, this is a design-level decision, not a
   billing one. ✅ (§9, Trap 1)

---

## 1. CLOUD LLM APIs — the online explanation path

### 1.1 Free tiers (self-serve, no application)

| # | Service | Free-tier quota (exact) | Data / training terms | Paid entry price | Self-serve? | Verdict |
|---|---|---|---|---|---|---|
| G1 | **Google Gemini API** <br>https://ai.google.dev/gemini-api/docs/pricing ✅ <br>https://ai.google.dev/gemini-api/terms ✅ | Free tier exists and covers **Gemini 3.8/3.7/3.6 Flash, 3.5 Flash-Lite and 2.5 Pro** ("Free of charge" for input and output) ✅. **Gemini 3.1 Pro Preview: not available on free tier** ✅. <br>🔴 **Google no longer publishes per-model free RPM/TPM/RPD in the docs.** The rate-limits page says only: *"Rate limits depend on a variety of factors (such as your usage tier) and can be viewed in Google AI Studio"* ✅. Every "1,500 RPD" figure you will find online is a **secondary source**. ⚠️ **The team must read their own limits at https://aistudio.google.com/rate-limit and screenshot them for the paper.** | 🔴 **Free tier: "Content used to improve our products."** The Terms state Google uses Unpaid Services content *"to provide, improve, and develop Google products and services and machine learning technologies"* and that *"human reviewers may read, annotate, and process your API input and output"* ✅. <br>✅ **Paid tier: "Google doesn't use your prompts... or responses to improve our products"**; logs kept only for abuse detection ✅. | Tier 1 = link a billing account (instant). Gemini 3.5 Flash-Lite **$0.30/M in, $2.50/M out**; Gemini 3.8 Flash **$0.75/M in, $3.75/M out**; Gemini 2.5 Pro **$1.25/M in, $10/M out** ✅ | ✅ Self-serve. India is a supported country ✅ (https://ai.google.dev/gemini-api/docs/available-regions) | **Best free model quality available to this team — and the single most dangerous free tier in the report.** Use it for development against synthetic/replayed data; **switch on billing before any real user location touches a prompt.** |
| G2 | **Groq** <br>https://console.groq.com/docs/rate-limits ✅ | Free Plan, per model ✅: <br>`openai/gpt-oss-120b`, `gpt-oss-20b`, `qwen/qwen3.6-27b`, `qwen/qwen3.8-27b`: **30 RPM · 1,000 RPD · 8K TPM · 200K TPD** <br>`groq/compound`, `compound-mini`: **30 RPM · 250 RPD · 70K TPM** <br>`whisper-large-v3(-turbo)`: **20 RPM · 2,000 RPD** | ⚠️ **UNVERIFIED.** Groq's public Privacy Policy explicitly excludes GroqCloud API data: *"This Policy does not apply to the information that we process as a 'data processor' on behalf of customers... of our business offerings such as GroqCloud"* ✅, and points to a Services Agreement + DPA that I could not retrieve. **Do not claim Groq is zero-retention without reading those two documents.** | "Developer plan" (price not on the rate-limits page ⚠️) | ✅ Self-serve, no card | **The best free tier for a live demo.** 30 RPM is genuinely fast and 1,000 RPD is more than a demo needs. **200K tokens/day is the real ceiling** — at ~1.5K tokens per explanation that is ~130 explanations/day. Fine for a demo; not for a pilot. |
| G3 | **Cerebras** <br>https://inference-docs.cerebras.ai/support/rate-limits ✅ | Docs list a **"Free Trial"** tier: `gpt-oss-120b` and `qwen-3.8-27b` at **5 RPM · 30K TPM · 1M TPH · 1M TPD**, described alongside **"$5 in credits, 30-day expiration"** ✅ | ⚠️ Not stated on the rate-limits page | Developer (pay-as-you-go): "no hourly and daily restrictions" ✅; price not on this page ⚠️ | ✅ Self-serve | ⚠️ **Ambiguous and I will not paper over it.** The docs show a 1M-tokens/day allowance *and* a 30-day $5 trial on the same page. Secondary sources claim a permanent 1M tok/day free tier; **the vendor page does not clearly say "permanent".** Treat as a 30-day resource. **5 RPM makes it useless as a demo primary** — one burst of parallel requests and you are throttled. |
| G4 | **Cloudflare Workers AI** <br>https://developers.cloudflare.com/workers-ai/platform/pricing/ ✅ | **10,000 Neurons/day** on both Free and Paid Workers plans ✅ | ⚠️ Not on the pricing page | **$0.011 per 1,000 Neurons** beyond the daily allowance (Workers Paid, $5/mo ≈ ₹473) ✅ | ✅ Self-serve | 🔴 **Kimi, GLM and DeepSeek models "require a paid billing method" and cannot be used on the free tier** ✅. The free 10k neurons/day only buys the small open models. Useful as a *fallback* LLM, not a primary. Big plus: it runs inside the same Worker as your API, so no extra egress. |
| G5 | **GitHub Models** <br>https://docs.github.com/en/github-models/use-github-models/prototyping-with-ai-models ✅ | **Copilot Free** tier ✅: <br>Low-tier models: **15 req/min · 150 req/day · 8,000 in / 4,000 out tokens per request** <br>High-tier models: **10 req/min · 50 req/day · 8,000 in / 4,000 out** <br>Embeddings: 15 req/min · 150 req/day · 64,000 tokens/request <br>Premium models (o1, o3, Grok-3, DeepSeek-R1): **not applicable on free** | ✅ Best verified privacy statement of any free LLM tier here: GitHub's own docs state **"Your data remains within GitHub and Azure and is not shared with model providers."** (https://docs.github.com/en/github-models/github-models-at-scale/use-models-at-scale ✅). ⚠️ Does *not* say whether Microsoft/GitHub itself trains on it — unverified. | Opt in to paid usage for "production grade rate limits" ✅ | ✅ Self-serve with a GitHub account (which they need anyway) | **The best data-terms story among free tiers**, and 8,000 input tokens is enough for a hazard-context prompt. **But 50 req/day on the good models is a demo-only budget.** Excellent as the *documented fallback* in the paper. |
| G6 | **OpenRouter (`:free` models)** <br>https://openrouter.ai/docs/api-reference/limits ✅ | **20 requests/minute** on free models ✅ <br>**50 requests/day** if you have never purchased credits ✅ <br>**1,000 requests/day** once you have purchased **≥ $10** of credits (≈ ₹945, one-time) ✅ | ⚠️ **Not clearly documented for `:free` variants.** The privacy doc says only: *"Providers that do log, or where we have been unable to confirm their policy, will not be routed to unless the model training toggle is switched on"* ✅, and that there are *"separate settings for paid and free models"* ✅ without saying what they are. **Assume free-model prompts are logged by the upstream provider until proven otherwise.** | Credits, pay as you go | ✅ Self-serve | **The best ₹945 the team could spend.** A one-time $10 credit purchase permanently raises the free-model ceiling from 50 → 1,000 req/day *and* gives fallback across many models behind one API. **Model-routing redundancy is worth more than any single provider's quota** for a live demo. |
| G7 | **Mistral La Plateforme** <br>https://mistral.ai/pricing ✅ | Free plan includes **"$10/mo in API credits"** ✅. ⚠️ Per-second/per-minute rate limits are **not published**; the docs page says to read them in the console (https://console.mistral.ai/limits/) ✅ | ⚠️ Not verified. Mistral has historically had a "free tier = data used for improvement" model; **I could not confirm this today — the team must read the current ToS.** | Mistral Large **$0.5/M in, $1.5/M out** ✅ | ✅ Self-serve | Decent European fallback, and $10/mo recurring credit is generous. **Unverified rate limits make it unsuitable as the demo primary.** |
| G8 | **Hugging Face Inference Providers** <br>https://huggingface.co/docs/inference-providers/pricing ✅ | **Free accounts: $0.10/month** in credits ✅ <br>**PRO accounts: $2.00/month** in credits ✅ (PRO subscription price not stated on that page ⚠️) | ⚠️ Varies by upstream provider | Buy credits | ✅ Self-serve | ❌ **$0.10/month is not a free tier, it is a demo button.** Rule it out for the explanation path. HF's value to this project is **Spaces** (§4), not inference. |
| G9 | **Together AI** <br>https://docs.together.ai/docs/rate-limits ✅ | ⚠️ **No published numbers.** The docs state: *"Dynamic rate limits adjust with usage, so there are no fixed per-model limits published"* ✅. The pricing page contains no free-credit figure ✅. | ⚠️ Unverified | Pay as you go | ✅ Self-serve | ❌ **Unquotable.** Every "$1 free credit" claim online is secondary. Do not build a dependency on a limit the vendor refuses to publish. |

### 1.2 Student / academic credits

| # | Programme | What you get | Self-serve or apply? | Verdict |
|---|---|---|---|---|
| G10 | **Microsoft Azure for Students** <br>https://azure.microsoft.com/en-us/free/students ✅ | **$100 Azure credit, 12 months** ✅ + *"free monthly amounts of 20+ popular services for 12 months"* + *"65+ always-free services"* ✅. **"No credit card required"** ✅. **Renewable annually while you remain a student** ✅. Requires a **school email** and full-time enrolment ✅ | ✅ Self-serve with a `@vitstudent.ac.in`-class address | 🔑 **The single highest-value student programme in this report, and the only cloud credit that needs no card.** $100 ≈ ₹9,449. Also reachable via the GitHub Student Pack ✅ |
| G11 | **GitHub Student Developer Pack** <br>https://education.github.com/pack ✅ | Verified offers relevant here ✅: **Azure $100 + 25 services**; **Heroku $13/mo for 24 months** (≈ $312 total); **MongoDB Atlas $50 credits**; **Sentry** (50K errors, 100K transactions, 1 GB attachments); **Appwrite** Education plan ($40/mo value); **Namecheap** free `.me` domain + SSL for 1 yr; **.TECH** domain 1 yr; **Name.com** free domain; **Clerk** Pro free while a student; **GitHub Copilot** free Student plan | ✅ Self-serve; requires student-status verification (school email / student ID) | 🔑 **Apply in week 1. Zero downside.** The Heroku $13/mo × 24 months line alone is worth ~₹29,500 and is a legitimate always-on host for the FastAPI backend. |
| G12 | **Google Cloud free tier + trial** <br>https://docs.cloud.google.com/free/docs/free-cloud-features ✅ | **Always Free:** 1 non-preemptible **e2-micro** VM/month, **US regions only (Oregon, Iowa, South Carolina)**, **30 GB standard PD**, **1 GB North-America egress/month** ✅. <br>**Trial:** **$300 credit, 90 days** ✅ | 🔴 **Credit card required** for the trial ✅ (temporary $0–$1 auth hold) | ⚠️ **The Always Free e2-micro is US-only and has 1 GB of free egress — it is not a viable backend for a Chennai demo** (≈250 ms RTT, and the egress allowance is trivial). The $300/90-day trial *is* enough to run a real GraphHopper box for the whole 7-week build, but it expires and needs a card. |
| G13 | **AWS Free Tier** <br>https://aws.amazon.com/free/ ✅ | 🔴 **Structurally changed.** Now: **"$100 in credits immediately"**, **"$100 more"** for exploring services, **max $200 over 6 months**, and *"[the account] closes on its own 6 months after you open it or when your credits run out, whichever comes first"* ✅. 30+ services retain "always free" monthly limits ✅ | Self-serve | 🔴 **The "12 months of t3.micro" model the team is probably planning around no longer exists.** $200/6 months is real money, but the auto-closing account makes it a bad home for anything that must survive to the viva. |
| G14 | **AWS Educate** <br>https://aws.amazon.com/education/awseducate/ ✅ | Free hands-on labs, self-paced training, digital badges, job board (18+). Open to anyone 13+, **no institutional requirement, "No credit card needed"** ✅. ⚠️ **The page does not state that participants receive AWS credits or a usable AWS account.** | ✅ Self-serve | ❌ **Training product, not infrastructure.** Do not plan to host anything on it. |
| G15 | **Anthropic AI for Science** <br>https://support.claude.com/en/articles/11199177 ✅ | **Up to $20,000 in API credits for a 6-month period** ✅. Fields include *environmental science, computer science, earth sciences* ✅. Reviewed on the **first Monday of each month** ✅; no feedback if rejected ✅ | 🔴 **Application required** (Google Form) | 🟡 **Long-shot but cheap to try — one form, ~30 minutes.** Aimed at researchers at academic/nonprofit institutions; the page does not explicitly exclude students. A VIT-affiliated, climate-resilience framing is a plausible fit. **Apply week 1, plan as if rejected.** Expected value is high because the downside is one form. |
| G16 | **OpenAI academic programme** | ⚠️ **No first-party academic/student credit programme found.** All results were secondary blogs. **I will not quote a number I could not source from OpenAI.** | — | ⚠️ Assume none exists. Do not plan around it. |

### 1.3 LLM recommendation

**Primary (demo): Groq** — 30 RPM is the only free tier fast enough that a live demo will not visibly
stall. **Secondary: OpenRouter** with a one-off $10 credit purchase (1,000 req/day, multi-provider
failover). **Quality reference / paper baseline: Gemini with billing enabled.** **Never** send a real
user location to Gemini's free tier.

---

## 2. MAP TILES

| # | Service | Free-tier quota (exact) | Paid entry | Self-serve? | Verdict |
|---|---|---|---|---|---|
| G17 | 🔑 **OpenFreeMap** <br>https://openfreemap.org/ ✅ | *"completely free: there are no limits on the number of map views or requests"*; **"no registration, no user database, no API keys, and no cookies"** ✅. Commercial use explicitly permitted ✅. Weekly full-planet dumps (Btrfs + MBTiles) for self-hosting ✅ | Donations only | ✅ No signup at all | 🔑 **The zero-rupee tile answer.** ⚠️ **Honest caveat the vendor states itself:** funded by donations, *"We aim to cover the running costs of our public instance through donations"*, **no SLA**. For a graded demo, **self-host the same data from a PMTiles file (G18) as the fallback** rather than betting the viva on a donation-funded public instance. |
| G18 | 🔑 **Protomaps / PMTiles + Cloudflare R2** <br>https://docs.protomaps.com/basemaps/downloads ✅ <br>https://developers.cloudflare.com/r2/pricing/ ✅ | Full planet PMTiles ≈ **120 GB**, z0–15, **ODbL**, daily builds at maps.protomaps.com/builds ✅. `pmtiles extract` cuts a city-sized region; *"each additional zoom level roughly doubles the size"* ✅. <br>**R2 free tier: 10 GB-month storage, 1M Class A ops/month, 10M Class B ops/month, egress free** ✅ | R2: $0.015/GB-mo, $4.50/M Class A, $0.36/M Class B ✅ | ✅ Self-serve (Cloudflare account, no card for the free tier) | 🔑 **This is the architecturally correct answer and it is free.** A Chennai extract at z0–15 is comfortably inside R2's free 10 GB. PMTiles serves via HTTP range requests straight from object storage — **no tile server, no compute, no egress bill.** ⚠️ Protomaps explicitly says *"hotlinking to these downloads are discouraged. Instead, you should copy the tileset to your own Cloud Storage"* ✅ — so copy it to R2, don't hotlink. |
| G19 | **VersaTiles** <br>https://versatiles.org/ ✅ | Public tile server at `tiles.versatiles.org`; *"no API keys, charges no usage fees, and does not track your users"*; fully self-hostable; FLOSS ✅. ⚠️ **No published rate limits** | Sponsorship only | ✅ No signup | 🟡 Good third option and a nice "we're not locked in" line for the paper. Same donation-funding fragility as OpenFreeMap, with less public traction. |
| G20 | **MapTiler Cloud** <br>https://www.maptiler.com/cloud/pricing/ ✅ | Free: **5,000 map sessions/mo**, **1,000 search sessions/mo**, **2,000 3D sessions/mo**, **100,000 API requests/mo**, 5 GB storage (1 file), 5 custom styles, 100 uploads/mo ✅. **MapTiler logo on the map is mandatory on free** ✅ | **Flex $30/mo** ≈ ₹2,835 (25k sessions, 500k API req) ✅ | ✅ Self-serve | 🟡 Fine for a demo; 5,000 sessions/month dies instantly at pilot scale. The forced logo is a poster/screenshot problem. **No reason to pick it over G17/G18.** |
| G21 | **Stadia Maps** <br>https://stadiamaps.com/pricing/ ✅ | **200,000 credits/month**, **"No additional usage"** (hard stop, no overage) ✅. Credit costs: basemap tile **1**, satellite tile **4**, geocoding request **20**, standard routing request **20** ✅. **No credit card required** ✅ | **Starter $20/mo** ≈ ₹1,890 (1M credits, commercial allowed) ✅ | ✅ Self-serve | 🟡 **Genuinely useful and under-rated — but read the licence.** 🔴 **"Commercial use not allowed"** on free ✅. For an academic project that is fine; for the commercialisation section of the paper it is not. 200k credits = 200k tiles **or** 10,000 routing requests **or** 10,000 geocodes — one free key covering tiles, geocoding *and* routing is rare. |
| G22 | **Thunderforest** <br>https://www.thunderforest.com/pricing/ ✅ | **150,000 tile requests/month** free ✅. Attribution mandatory: *"it's not permitted to remove the attribution"* ✅ | **Solo Developer $125/mo** ≈ ₹11,811 ✅ | ✅ Self-serve | ❌ The cliff from free to $125/mo is brutal. Styling is nice; nothing else recommends it here. |
| G23 | **CARTO** <br>https://carto.com/pricing ✅ | **14-day trial only — not a free tier.** *"Trials are for evaluation purposes only — production use is not permitted during a trial period"* ✅. ⚠️ No academic/student programme documented on the pricing page | Sales-led | 🔴 Sales contact | ❌ **Rule out.** Enterprise geospatial platform; wrong shape and wrong price for this team. |
| G24 | 🔴 **OSM standard tile server (`tile.openstreetmap.org`)** <br>https://operations.osmfoundation.org/policies/tiles/ ✅ | Free, but the policy is a set of prohibitions, not a quota. **No published maximum request rate** ✅ | n/a | n/a | 🔴 **DO NOT USE IN THE APP — see §9, Trap 4.** The policy verbatim forbids the project's core feature: *"Bulk downloading is any pre-emptive fetching of tiles other than those a user is actively viewing"* and *"Download city/country for offline use"* or similar prefetching capabilities *"are therefore prohibited"* ✅. **CityPulse is an offline-first app. This licence and this architecture are incompatible.** Requires a unique User-Agent (generic ones *"will be blocked"* ✅), 7-day cache honouring, and HTTPS only. |

---

## 3. GEOCODING

| # | Service | Free-tier quota (exact) | Paid entry | Self-serve? | Verdict |
|---|---|---|---|---|---|
| G25 | 🔴 **Nominatim (public osm.org instance)** <br>https://operations.osmfoundation.org/policies/nominatim/ ✅ | **Absolute maximum 1 request/second** ✅. Long-running / scheduled scripts: **4 requests/minute** ✅. Must send a real `User-Agent` or `Referer` ✅. **"Results must be cached on your side"** ✅. Single thread only; **"no distributed scripts"** ✅ | n/a | n/a | 🔴 **Forbidden for this app's actual use.** The policy explicitly bans: **auto-complete search** (*"This is not yet supported by Nominatim"*), **systematic queries** including grid-based reverse geocoding, and services *"whose primary function involves geocoding"* ✅. A search box in CityPulse that queries public Nominatim on keystroke **violates the policy on day one.** Use it for one-off development lookups only. |
| G26 | 🔑 **Self-hosted Nominatim / Photon** <br>https://github.com/komoot/photon ✅ | Free (Apache 2.0) ✅. Public `photon.komoot.io` endpoint exists but: *"You are welcome to use the API for your project as long as the number of requests stay in a reasonable limit. Extensive usage will be throttled or completely banned"* ✅ — **no numbers, no guarantees** ✅. <br>Self-host worldwide: **~95 GB disk**, **64 GB RAM recommended** (tunable via `java -Xmx8G`), Java 21+ ✅. Prebuilt weekly dumps incl. **selected country datasets** at `download1.graphhopper.com/public` ✅ | Your own compute | ✅ | 🔑 **The right answer for a Chennai-only app.** The worldwide index is 95 GB, but an **India-only Photon dump is a small fraction of that** and will run in a few GB alongside GraphHopper. ⚠️ **I did not verify the India-extract size — the team must check `download1.graphhopper.com/public` directly.** |
| G27 | **LocationIQ** <br>https://locationiq.com/pricing ✅ | **5,000 requests/day**, **2 req/sec** (and a stated **60 req/min**) ✅. Includes **Geocoding, Routing, Street & Static Maps** ✅. 1 access token ✅. **"Limited Commercial Use"** with mandatory attribution link ✅ | **Maps Lite $45/mo** ≈ ₹4,252 ✅ | ✅ Self-serve (⚠️ card requirement not stated) | 🔑 **The best hosted geocoding free tier for this project.** 5,000/day is 30× Nominatim's sustainable rate, it is licence-clean for app use, and **it bundles routing and tiles into the same key** — a genuine single-dependency fallback. |
| G28 | **Geoapify** <br>https://www.geoapify.com/pricing/ ✅ | **3,000 credits/day**, **up to 5 requests/second** ✅. **Commercial use permitted on free** with attribution ✅. Isochrones limited to 15 min / isodistances 10 km on free ✅ | **API 10 $59/mo** ≈ ₹5,575 ✅ | ✅ Self-serve | 🔑 **The only free tier here that permits commercial use** — which matters for the paper's commercialisation section, where Open-Meteo and Stadia both fail (Strand C §5.3). ⚠️ The pricing page does not enumerate which APIs are included; verify before depending on routing. |
| G29 | **OpenCage** <br>https://opencagedata.com/pricing ✅ | **2,500 requests/day, 1 request/sec** ✅. **"no credit card required"** ✅. Trial lasts *"as long as you need for testing"*, but **inactive accounts are deleted after three months** ✅. ⚠️ **No academic/open-source free tier** ✅ | **X-Small $50/mo** ≈ ₹4,725 ✅ | ✅ Self-serve, no card | 🟡 Clean terms, honest company, no card. 1 req/sec is the binding constraint. Good as a **second geocoder for cross-validation** in the evaluation. |
| G30 | **Mapbox Geocoding** <br>https://www.mapbox.com/pricing ✅ | **Temporary Geocoding: 100,000 req/month free**, then $0.75/1,000 ✅. **Permanent Geocoding: no free tier**, $5.00/1,000 ✅ | see above | ⚠️ Card requirement not stated on the pricing page | 🔴 **The "Temporary" vs "Permanent" split is a licence trap, not a pricing one.** *Temporary* results may not be stored. CityPulse caches geocodes for offline use → that is **Permanent** geocoding → **no free tier and $5 per 1,000.** Same structural conflict as Strand C §5.3. |

---

## 4. HOSTED ROUTING APIs (online fallback / baseline)

| # | Service | Free-tier quota (exact) | Paid entry | Self-serve? | Verdict |
|---|---|---|---|---|---|
| G31 | **OpenRouteService (HeiGIT)** <br>https://giscience.github.io/openrouteservice/frequently-asked-questions.html ✅ | ⚠️ **Partially published only.** The FAQ gives the `directions` endpoint *"default limit of 2000 requests per day"* and *"Any consecutive period of 60 seconds may only contain 40 directions requests"* ✅. **Per-endpoint quotas for isochrones/matrix/geocoding are not published on any page I could fetch** — the plans page (account.heigit.org/info/plans) renders client-side and returned no content ✅. <br>🔴 **"an API key must not be used client-side in an application"** ✅ | Enterprise, contact HeiGIT | ✅ Self-serve key | 🔑 **2,000 directions/day is the most generous free routing quota in this table**, and ORS is academically respectable (Heidelberg Institute for Geoinformation Technology) — a good citation for the paper. ⚠️ **Server-side proxy is mandatory**; a Flutter app calling ORS directly with an embedded key breaches the terms. |
| G32 | **GraphHopper Directions API** <br>https://www.graphhopper.com/pricing/ ✅ | **500 credits/day**, max **5 locations/request**, max **1 vehicle/request** ✅. Includes Routing, Route Optimization, Geocoding, Map Matching ✅. **Isochrone and Matrix APIs are paid-only** ✅. **"No credit card required"** ✅ | **Basic €69/mo** (5,000 credits/day) ✅ | ✅ Self-serve, no card | 🟡 **500/day is fine as a correctness baseline for the evaluation** — route the same OD pairs through hosted GraphHopper and through your self-hosted instance and show they agree. 🔴 **"The Free Plan is for non-commercial use only"** ✅. The €69 → €479 paid ladder is out of reach; **this is an argument for self-hosting GraphHopper, which is Apache 2.0 and free** (Strand C, C5). |
| G33 | **Mapbox Directions** <br>https://www.mapbox.com/pricing ✅ | **100,000 requests/month free**, then **$2.00/1,000** ✅. Navigation SDK v3.x: **100 MAU and 1,000 trips/month free**, then $0.30/user + $0.08/1,000 trips ✅ | see above | ⚠️ Card requirement not documented ✅ | 🟡 **Numerically the most generous routing free tier here (100k/month ≈ 3,300/day).** But Strand C already flagged Mapbox's Produced-Work terms, and the free Navigation SDK cap of **100 monthly active users** kills the 1,000-user pilot. Useful as a baseline; not as the architecture. |
| G34 | **TomTom Routing** | **20,000 requests/month** free (verified in Strand C, C29) | — | ✅ Self-serve | Already the recommended traffic provider (Strand C). The routing quota is a free bonus — **20,000/month ≈ 660/day**, a good second opinion. |
| G35 | **HERE** <br>https://www.here.com/get-started/pricing ✅ | ⚠️ **Not published on the page.** Meta description says *"Sign up for free and pay-as-you-grow"*; **no transaction counts, no prices, no card policy on the public pricing page** ✅ | ⚠️ | ⚠️ | ⚠️ **Unquotable — same conclusion Strand C reached (C30).** Do not cite a HERE free-tier number from any secondary source. |
| G36 | **FOSSGIS public Valhalla** <br>https://valhalla.openstreetmap.de/ ✅ | ⚠️ **Could not verify.** The demo page is a client-side JS app and returned no policy text ✅; the OSM wiki *Routing/online routers* page lists the instance but *"does not provide explicit API base URLs, rate limiting specifications, or fair-use policies"* ✅ | Free (donation-funded) | n/a | ⚠️ **Do not hardcode an endpoint or a rate limit for this.** FOSSGIS runs it as a community service on donated infrastructure; hammering it from a student app is both rude and fragile. **Self-host Valhalla or GraphHopper instead** — that is the whole point of §5. |

**Routing verdict:** the free hosted quotas (ORS 2,000/day, TomTom 660/day, GraphHopper 500/day)
are collectively enough for a demo and an evaluation baseline, and **worthless for a 1,000-user
pilot**. Strand C already concluded GraphHopper self-hosted is the right engine. This strand adds:
**self-hosting is also the only version that costs ₹0 at any scale.**

---

## 5. COMPUTE / HOSTING — the hardest problem in this report

**The requirement:** GraphHopper over a Chennai/Tamil Nadu OSM extract (~2–4 GB RAM) **plus** a
FastAPI process, **always on**, **reachable from a phone in Chennai**, **for ₹0**.

That combination eliminates almost every PaaS free tier in existence, because they all cap RAM at
512 MB and sleep when idle.

| # | Service | Free-tier quota (exact) | Enough RAM? | Sleeps? | Paid entry | Verdict |
|---|---|---|---|---|---|---|
| G37 | 🔑 **Oracle Cloud Always Free** <br>https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm ✅ | 🔴 **HALVED IN 2026.** Ampere A1: *"1,500 OCPU hours and 9,000 GB hours per month"*, *"For Always Free tenancies, this is equivalent to **2 OCPUs and 12 GB of memory**"* ✅ (was 4 OCPU / 24 GB). <br>Also: **2 × VM.Standard.E2.1.Micro** (1/8 OCPU, 1 GB each) ✅; **200 GB block storage total** ✅; **20 GB object storage + 50,000 API req/mo** ✅; 🔑 **10 TB/month outbound data transfer** ✅; 2 × Autonomous DB (1 OCPU, 20 GB) ✅; 1 Flexible Load Balancer at 10 Mbps ✅ | ✅ **Yes — 12 GB is 3× what GraphHopper needs** | ❌ No | Pay-as-you-go beyond the allowance | 🔑 **Still the best free compute on Earth, even after the cut**, and **10 TB/month of free egress is not matched by anything else in this report.** 2 OCPU / 12 GB runs GraphHopper + FastAPI + Redis + PostGIS on one box with room to spare. <br>🔴 **Two traps: (a) the halving was unannounced (confirmed by InfoQ, Linuxiac, heise, and Oracle's own Cloud Customer Connect thread) — it can happen again; (b) "Out of host capacity" errors on A1 shapes in the Mumbai/Hyderabad regions are a long-standing, widely-reported problem.** ⚠️ **I could not verify current A1 capacity availability for new India signups — the team must attempt a real provisioning in week 1, not week 5.** |
| G38 | 🔑 **Hugging Face Spaces (CPU basic)** <br>https://huggingface.co/docs/hub/spaces-overview ✅ <br>https://huggingface.co/docs/hub/spaces-gpus ✅ | **2 vCPU, 16 GB RAM, 50 GB disk (not persistent) — FREE** ✅. Docker SDK Spaces allowed. Free accounts also get up to **2 Gradio Spaces on ZeroGPU** ✅ | ✅ **16 GB — the most free RAM of any option here** | 🔴 **Yes: sleeps after 48 hours of inactivity**, *"currently, 48 hours"*, **not configurable on free hardware** ✅ | CPU Upgrade **$0.03/hr** = ~$21.90/mo ≈ ₹2,070 ✅ | 🔑 **The surprise of this report.** 16 GB of RAM, free, no card, no sleep for 48 h. **Any visitor restarts it automatically** ✅, so a UptimeRobot 5-minute ping (G53) keeps it awake indefinitely at zero cost. ⚠️ **Disk is not persistent** — the OSM graph must be rebuilt or re-downloaded on restart (budget 2–5 min). **This is the best free home for the GraphHopper engine if Oracle capacity fails.** |
| G39 | **Google Cloud e2-micro** ✅ | See G12: 1 e2-micro, **US regions only**, 30 GB PD, **1 GB/month egress** | 🔴 No (1 GB RAM) | No | — | ❌ **1 GB RAM and 1 GB monthly egress.** Not a candidate. |
| G40 | **AWS** ✅ | See G13: $100–$200 credits, **account auto-closes at 6 months** | ✅ (whatever you pay for) | No | — | 🔴 **The auto-closing account is disqualifying** for a project that must be demonstrable at a viva. |
| G41 | **Azure for Students** ✅ | $100 credit / 12 months, **no card**, renewable ✅ | ✅ | No | Credit-funded | 🔑 **The best *funded* option.** A B1s (1 vCPU, 1 GB) is too small; a B2s (2 vCPU, 4 GB) at roughly $30/mo would burn the $100 in ~3 months — **which is exactly the length of the build + demo window.** ⚠️ I did not verify current Azure India VM prices; the team should price a B2s in the Azure calculator before committing. |
| G42 | **Fly.io** <br>https://fly.io/docs/about/pricing/ ✅ <br>https://fly.io/docs/about/free-trial/ ✅ | 🔴 **No free allowance.** Trial = **"2 hours of machine runtime or 7 days of access, whichever comes first"** ✅. **"All organizations... require a credit card on file"** ✅ | — | — | **shared-cpu-1x 256 MB = $1.94/mo** (₹183); **1 GB = $5.70/mo** (₹539) ✅ | ❌ **Not a free option any more.** ✅ **But it is the cheapest *paid* option in this report** — see the ₹500 path (§7). |
| G43 | **Render** <br>https://render.com/docs/free ✅ <br>https://render.com/pricing ✅ | Free web service: **512 MB RAM, <1 CPU** ✅; **750 free instance hours/month per workspace** ✅; **spins down after 15 minutes of inactivity** and *"takes about one minute"* to wake ✅. Free Postgres: **1 GB, expires 30 days after creation**, 14-day grace ✅, one per workspace ✅ | 🔴 No (512 MB) | 🔴 **Yes — 15 min, ~60 s cold start** | Starter **$7/mo** (512 MB) ≈ ₹661; Postgres **$6/mo** (256 MB) ≈ ₹567 ✅ | 🔴 **A 60-second cold start will destroy a live demo** (§9, Trap 2). Render's own docs say *"do not use them for production applications"* ✅. **The 30-day-expiring free Postgres is a data-loss trap.** |
| G44 | **Railway** <br>https://railway.com/pricing ✅ | **30-day trial with $5 credits**, no credit card to start ✅. Trial-phase limits **0.5 GB RAM / 1 vCPU** ✅ | 🔴 No | — | **Hobby $5/mo** ≈ ₹473, includes $5 usage credit ✅ | 🟡 Genuinely pleasant DX and $5/mo is affordable, but **0.5 GB on the free trial cannot hold a routing graph**, and it is a 30-day trial, not a free tier. |
| G45 | **Koyeb** <br>https://www.koyeb.com/docs/reference/instances ✅ | Free instance: **512 MB RAM, 0.1 vCPU, 2 GB SSD** per organization ✅. Frankfurt or Washington DC only ✅. No volumes, no custom scaling ✅. 🔴 **"They scale down to zero when they don't receive any traffic for 1 hour"** ✅ | 🔴 No | 🔴 Yes, 1 h | eco-medium (1 vCPU, 2 GB) **$10.71/mo** ≈ ₹1,012; eco-large (2 vCPU, 4 GB) **$21.43/mo** ≈ ₹2,025 ✅ | 🔴 0.1 vCPU is a tenth of a core. **Cannot run a routing engine.** Eco instances are reasonably priced if the team ever has money. |
| G46 | 🔴 **PythonAnywhere** <br>https://www.pythonanywhere.com/pricing/ ✅ | Beginner (free): **512 MB disk**, **100 CPU-seconds/day**, 1 web app on `*.pythonanywhere.com`, **no always-on tasks** ✅. 🔴 **Outbound internet restricted to "Specific sites via HTTP(S) only"** — a whitelist ✅ | 🔴 No | — | Developer **$10/mo** ≈ ₹945 ✅ | 🔴 **Disqualified outright.** CityPulse's entire ingest layer calls Open-Meteo, GDACS, TomTom, OpenAQ. **A whitelisted-egress host cannot make those calls.** 100 CPU-seconds/day is also less than one GraphHopper graph load. |
| G47 | **Replit** <br>https://replit.com/pricing ✅ | ⚠️ **Free-plan specifics are not on the pricing page** ✅ — only the Core plan at **$20/mo ($18 annual)** with "up to 30 hours of chat on Free Mode" and "up to 60 projects" ✅ | ⚠️ | ⚠️ | $20/mo ≈ ₹1,890 | ⚠️ **Unquotable, and the product has pivoted to AI app-building.** Replit Deployments (always-on) have been paid-only for some time. Do not plan a backend here. |
| G48 | 🔑 **Laptop + Cloudflare Tunnel** <br>https://www.cloudflare.com/plans/ ✅ | **Cloudflare Zero Trust free tier: "$0 forever" for teams under 50 users** ✅. Cloudflare free plan: DNS, unmetered DDoS protection, CDN, Universal SSL, WAF, $0/mo ✅ | ✅ (whatever the laptop has) | ❌ (while the laptop is on) | Pro $20/mo annual; Zero Trust PAYG $7/user/mo ✅ | 🔑 **The honest demo answer, and it costs literally ₹0.** `cloudflared` exposes `localhost:8989` on a real HTTPS URL with a real certificate, from a laptop in a VIT lab. No card, no sleep, no cold start, full laptop RAM. ⚠️ **I could not verify tunnel bandwidth limits or whether a Cloudflare-hosted domain is required** — the connect-networks docs page does not state either ✅. **Team must test on their own network** (campus NAT/firewall is the real risk, not Cloudflare). |
| G49 | **ngrok** <br>https://ngrok.com/pricing ✅ | Free: **1 development domain**, **up to 3 online endpoints**, **1 GB data transfer/month**, **20,000 HTTP/S requests/month**, 4,000 req/min rate limit, **1 team member** ✅. 🔴 **Interstitial warning page on HTTP/S endpoints** ✅ | ✅ | ❌ | Hobbyist **$10/mo** ≈ ₹945 ✅ | 🔴 **The interstitial page will appear in the demo video and in the examiner's browser.** 20,000 req/month is also thin. **Cloudflare Tunnel is strictly better and free.** |
| G50 | **Tailscale Funnel** <br>https://tailscale.com/kb/1223/funnel ✅ | Docs state **"Tailscale Funnel is available for all plans"** ✅, including free Personal (unlimited user devices, up to 6 users ✅). *"Traffic sent over a Funnel is subject to non-configurable bandwidth limits"* — **the numbers are not published** ✅ | ✅ | ❌ | Standard $8/user/mo ≈ ₹756 ✅ | 🟡 ⚠️ **Contradiction flagged:** the **pricing page comparison table shows Funnel starting at the Standard paid plan**, while the **Funnel KB article says all plans** ✅. **Both are Tailscale's own pages.** Do not rely on Funnel until the team tests it on a free account. Cloudflare Tunnel has no such ambiguity. |

### 5.1 Compute verdict

**Try in this order, in week 1, not week 5:**

1. **Oracle Cloud Always Free A1** (2 OCPU / 12 GB) — attempt provisioning immediately; if the India
   regions return "out of host capacity", try again at off-peak hours for a few days, then move on.
2. **Hugging Face Space (Docker SDK)** — 2 vCPU / 16 GB, free, kept awake by a UptimeRobot ping.
3. **Azure for Students $100** — the funded fallback, no card needed.
4. **Laptop + Cloudflare Tunnel** — the demo-day insurance policy. **Have this working regardless**,
   because it is the only option with zero external failure modes on the day.

---

## 6. DATABASE + CACHE

| # | Service | Free-tier quota (exact) | PostGIS? | Paid entry | Verdict |
|---|---|---|---|---|---|
| G51 | 🔑 **Supabase** <br>https://supabase.com/pricing ✅ <br>https://supabase.com/docs/guides/database/extensions ✅ | **500 MB database per project** ✅, **1 GB file storage** ✅, **5 GB egress + 5 GB cached egress** ✅, **50,000 MAU** ✅, **500,000 edge function invocations** ✅, **max 2 active projects** ✅. 🔴 **"Free projects are paused after 1 week of inactivity"** ✅ | ✅ **Yes.** PostGIS is in the supported-extensions list and is enabled from the dashboard (Database → Extensions → `postgis`) ✅. ⚠️ **Supabase's docs do not state any plan restriction on extensions** ✅ — no page says "free plan excluded", but neither does one say "available on Free". **Team should enable it on a free project and screenshot the result before designing around it.** | **Pro $25/mo** ≈ ₹2,362 (8 GB disk, 250 GB egress, 100k MAU, daily backups) ✅ | 🔑 **Almost certainly the right database, with one serious caveat.** Managed Postgres + PostGIS + auth + storage on one free tier is exactly this project's shape. 🔴 **The 1-week inactivity pause is a demo-killer** (§9, Trap 3) — a project idle over a semester break wakes up paused. 500 MB also fills fast once you are storing hazard events with geometry. ⚠️ One PostGIS note from PostGIS itself: *"As of PostGIS 2.3 or newer, the PostGIS extension is no longer relocatable"* ✅ — **pick the schema on day one.** |
| G52 | **Neon** <br>https://neon.com/pricing ✅ | **0.5 GB storage/project**, **100 CU-hours/project/month**, 100 projects/org, 10 branches/project ✅. **Auto-suspends after 5 minutes** of inactivity ✅ | ⚠️ Not verified today | Launch: pay-as-you-go, **$0.106/CU-hour** ✅ | 🟡 **Database branching is genuinely useful for the evaluation** (branch per replay scenario). 🔴 **5-minute auto-suspend adds a cold start to the first query** — acceptable for a backend with a keep-alive, fatal if the demo's first action hits a cold DB. |
| G53 | **Aiven** <br>https://aiven.io/pricing ✅ | Free plans for **PostgreSQL, MySQL, OpenSearch, Kafka, Valkey** ✅. Free PostgreSQL: **1 dedicated VM, 1 CPU, 1 GB RAM, 1 GB storage** ✅. **Cannot select a specific cloud or region** ✅. No time expiry, but *"Aiven reserves the right to shut down services if we believe they... are unused for an extended period"* ✅ | ⚠️ Not verified | 30-day trial available ✅ | 🟡 **1 GB RAM on a dedicated VM is better than Supabase's shared free tier for query performance**, and 1 GB storage is double Supabase's 500 MB. 🔴 **"Cannot select a specific cloud or region"** means you may land far from Chennai — unacceptable latency risk for a live demo. |
| G54 | 🔴 **ElephantSQL** <br>https://www.elephantsql.com/blog/end-of-life-announcement.html ✅ | **DEAD.** Stopped new signups **after 1 May 2024**; full end of life **27 January 2025** ✅ | — | — | 🔴 **Do not use. Do not cite. Any tutorial recommending it is >2 years stale** — a useful signal for judging the freshness of any other "free tier" listicle the team reads. |
| G55 | **Railway Postgres** ✅ | Bundled in the $5 trial credit / $5-per-month Hobby usage (G44) | ⚠️ | $5/mo ≈ ₹473 | 🟡 Fine if they are already on Railway; no independent free tier. |
| G56 | 🔑 **Upstash Redis** <br>https://upstash.com/pricing/redis ✅ | **500,000 commands/month** (≈ 16,600/day) ✅, **256 MB** max data ✅, **10 MB** max request ✅, **10 GB bandwidth/month** ✅, 1 free DB (up to 10 on free tier) ✅ | n/a | Pay-as-you-go **$0.2 per 100K commands**; Fixed 250 MB **$10/mo** ≈ ₹945 ✅ | 🔑 **The right cache for the decay-scoring buffer** — serverless, HTTP API (works from Workers and from a phone-adjacent edge), no idle cost. 🔴 **500K commands/month is the binding constraint and it is easy to blow through**: a naive per-request `GET`+`SET`+`ZADD` pattern at 3,000 routes/day = 270K commands/month before you have done anything clever. **Batch with pipelines.** |
| G57 | **Redis Cloud "Always Free"** <br>https://redis.io/pricing/ ✅ | **30 MB**, shared deployment, single database, best-effort SLA, community support ✅ | n/a | Essentials from **$0.007/hr ≈ $5/mo** ≈ ₹473 ✅ | 🟡 30 MB is a toy, but it is genuinely permanent and it is real Redis (not an HTTP shim). Good for a small hot set of active hazards. Upstash is the better fit. |
| G58 | **Cloudflare D1** <br>https://developers.cloudflare.com/d1/platform/pricing/ ✅ | **5 million rows read/day**, **100,000 rows written/day**, **5 GB total storage** ✅ | ❌ **No PostGIS.** SQLite | Paid: 25B rows read/mo included, then $0.001/M; 50M writes/mo then $1.00/M; 5 GB then $0.75/GB-mo ✅ | 🟡 **5M row reads/day is astonishingly generous** — but **no spatial types.** Only useful for non-spatial metadata (users, settings, audit log). The hazard geometry has to live in PostGIS. |
| G59 | **Cloudflare KV** <br>https://developers.cloudflare.com/kv/platform/pricing/ ✅ | **100,000 reads/day**, 🔴 **1,000 writes/day**, 1,000 deletes/day, 1,000 list ops/day, **1 GB storage** ✅ | n/a | 10M reads/mo then $0.50/M; 1M writes/mo then $5.00/M ✅ | 🔴 **1,000 writes/day makes KV useless for a live hazard buffer.** Hazard signals arrive far faster than that. **Read-heavy config/cache only.** Note: *"Even failed lookups (null returns) incur charges"* ✅ |
| G60 | 🔑 **Cloudflare R2** <br>https://developers.cloudflare.com/r2/pricing/ ✅ | **10 GB-month storage**, **1M Class A ops/mo**, **10M Class B ops/mo**, 🔑 **egress free** ✅ | n/a | $0.015/GB-mo; $4.50/M Class A; $0.36/M Class B ✅ | 🔑 **Zero-egress object storage is the quiet hero of this stack.** Host the PMTiles basemap (G18), the pre-built GraphHopper graph for on-device download, and the replay corpus. **10M Class B ops/month covers ~5 million tile range-requests with room to spare.** |

---

## 7. MOBILE / APP SERVICES

| # | Service | Free-tier quota (exact) | Cost | Verdict |
|---|---|---|---|---|
| G61 | 🔑 **Firebase Cloud Messaging (FCM)** <br>https://firebase.google.com/pricing ✅ | **"No-cost"** on the Spark plan, **no usage limit listed** ✅. **"No payment method needed"** for Spark ✅ | ₹0 | 🔑 **FCM is free, unlimited, and the only push service the team needs.** This is the clearest zero-cost win in the report. |
| G62 | **Firebase Spark plan (rest)** ✅ | Firestore: **1 GiB storage, 50K reads/day, 20K writes/day, 20K deletes/day** ✅. Realtime DB: 1 GB, 10 GB downloads/mo, 100 simultaneous connections ✅. Hosting: **10 GB storage, 360 MB/day transfer** ✅. Auth: Identity Platform 50K MAU ✅. 🔴 **Cloud Functions: "Not applicable" on Spark** ✅. **App Distribution: "No-cost"** ✅ | ₹0 | 🟡 Use FCM, Auth and App Distribution. 🔴 **Hosting's 360 MB/day transfer cap is tiny** — do not serve map tiles from it. 🔴 **No Cloud Functions on Spark** means the backend must live elsewhere (§5). |
| G63 | **Firebase App Distribution** ✅ | **"No-cost"**, no usage limits listed ✅ | ₹0 | 🔑 **Ship the APK to testers for free, with no store account at all.** This is how the team demos on real phones in week 3 without paying Google anything. |
| G64 | **OneSignal** <br>https://onesignal.com/pricing ✅ | Free: **unlimited mobile push up to 1,000 MAU** ✅; web push **max 10,000 subscribers per send**, no monthly send cap ✅; email **10,000 sends/month** ✅. Locked on free: Intelligent Delivery, time-delayed sends, retargeting, frequency capping, confirmed receipt, data exports ✅ | Growth from **$19/mo** ≈ ₹1,795 ✅ | 🟡 Nicer dashboard than raw FCM and the 1,000-MAU free cap **exactly matches the 1,000-user pilot** — but it is an unnecessary dependency when FCM is free and unmetered. 🔴 **"Data Exports" being a paid feature matters** if the evaluation needs delivery statistics. |
| G65 | **ntfy (self-hosted)** <br>https://docs.ntfy.sh/ ✅ | Open-source; public `ntfy.sh` server exists; ⚠️ **rate limits and licence are not stated on the getting-started page** ✅ | ₹0 self-hosted | 🟡 Worth knowing as the no-Google-dependency option (relevant to the paper's "civic infrastructure" positioning), but FCM is free and already integrated with Flutter. |
| G66 | 🔴 **Google Play Console** <br>https://support.google.com/googleplay/android-developer/answer/6112435 ✅ | **US$25 one-time registration fee** ≈ **₹2,362** ✅. Card required (**prepaid cards not accepted**) ✅ | ₹2,362 one-time | 🔴 **Three hidden costs beyond the $25**, all verified: (a) **government ID + credit card in your legal name** for identity verification ✅; (b) personal accounts created after **13 Nov 2023** must **"meet specific testing requirements before they can make their app available"** ✅ — in practice a closed test with testers over a sustained period; (c) since early 2024, **device verification via the Play Console mobile app** ✅. **This is weeks of process, not a $25 payment.** |
| G67 | 🔴 **Apple Developer Program** <br>https://developer.apple.com/support/enrollment/ ✅ | **US$99/year** ≈ **₹9,355**, auto-renewing ✅. **No free distribution path** — *"You'll only need to enroll if you'd like to distribute apps"* ✅. 🔑 **"Accredited educational institutions worldwide can enroll... with a fee waiver"** ✅ | ₹9,355/yr, or ₹0 via VIT | 🔴 **Ship Android + web only.** $99/yr is the single largest avoidable cost in this project. 🔑 **If the team genuinely needs iOS, the route is VIT applying for the educational fee waiver — not three students paying $99.** That is an email to the department, not a purchase. |

**Mobile verdict:** **Android + web only. Firebase App Distribution for testers. FCM for push.
Skip the Play Store entirely for the academic deliverable** — a signed APK plus a hosted web build
demonstrates everything the rubric asks for, at ₹0. Pay the $25 only if the paper claims a public
release.

---

## 8. DEV / OPS FREEBIES

| # | Service | Free-tier quota (exact) | Paid entry | Verdict |
|---|---|---|---|---|
| G68 | 🔑 **GitHub Actions** <br>https://docs.github.com/en/billing/concepts/product-billing/github-actions ✅ | Free plan: **2,000 minutes/month**, 500 MB artifact storage, 10 GB cache ✅. 🔑 **"The use of standard GitHub-hosted runners is free: In public repositories"** with no minute limit ✅. Multipliers: Windows 1.67×, macOS 10.3× ✅ | Linux 2-core $0.006/min ✅ | 🔑 **Make the repo public and CI is unlimited and free.** An academic OSM/ODbL project has every reason to be public anyway (Strand C §5.2 requires publishing the graph-build script). **This also gives free compute for nightly graph rebuilds and the reproducible-evaluation runs** — a real, free compute resource most teams overlook. |
| G69 | **Sentry** <br>https://sentry.io/pricing/ ✅ | Developer (free): **5,000 errors/mo**, **5M spans/mo**, **50 replays**, **1 cron monitor**, **1 GB attachments**, **one user**, **30-day retention** ✅ | Team **$26/mo** ≈ ₹2,457 ✅ | 🟡 **"One user" on a 3-person team is the catch.** ✅ **But the GitHub Student Pack includes an upgraded Sentry offer (50K errors, 100K transactions, 1 GB attachments)** ✅ — take that instead. |
| G70 | 🔑 **PostHog** <br>https://posthog.com/pricing ✅ | **1M events/mo**, **5,000 session replays/mo**, **1M feature-flag requests/mo**, **100K exceptions/mo**, **1,500 survey responses/mo**, **1M data-warehouse rows/mo** ✅. **"No credit card required"** ✅ and 🔑 **"Usage stops at the free tier limits, so you can't be charged by surprise"** ✅ | Usage-based above the free tier | 🔑 **The single best free tier in this entire report**, and the only one that *guarantees in writing it cannot bill you by surprise.* 1M events/month covers a 1,000-user pilot comfortably. ⚠️ **Privacy caution for CityPulse specifically:** session replay + location data + DPDP Act (Strand C §5.4) = do **not** enable replay on screens showing a user's route. |
| G71 | **Grafana Cloud** <br>https://grafana.com/pricing/ ✅ | Free: **10K active metric series**, **50 GB logs/mo**, **50 GB traces/mo**, **50 GB profiles/mo**, all at **14-day retention** ✅; **3 active Grafana users** ✅; **500 k6 virtual-user hours/mo** ✅ | Pro from **$19/mo** ≈ ₹1,795 ✅ | 🔑 **3 users is exactly the team size.** 50 GB of logs/month free is far beyond what this project will generate. 🔑 **500 k6 VU-hours is a free load-testing budget** — use it to produce a real "can this survive 1,000 users?" figure for the paper instead of asserting one. |
| G72 | **UptimeRobot** <br>https://uptimerobot.com/pricing/ ✅ | Free: **50 monitors**, **5-minute check interval**, HTTP/port/ping/keyword/API/UDP/DNS/SSL monitors, **1 basic status page**, **3-month retention**, 5 basic integrations ✅ | Solo from **$12/mo** ≈ ₹1,134 ✅ | 🔑 **Dual-purpose: monitoring *and* the keep-alive that stops Hugging Face Spaces (G38) and Supabase (G51) from sleeping.** A 5-minute ping on the health endpoint is free and solves the two worst traps in this report at once. |
| G73 | **Cloudflare free plan** <br>https://www.cloudflare.com/plans/ ✅ | $0/mo: DNS, **unmetered DDoS protection**, CDN, **Universal SSL**, WAF, free managed ruleset ✅. 🔑 **Zero Trust free "for teams under 50 users" — "$0 forever"** ✅ | Pro $20/mo annual ($25 monthly); Zero Trust PAYG $7/user/mo ✅ | 🔑 **Free TLS, free CDN, free DDoS, free tunnel, free R2 egress, free Workers, free Pages.** Cloudflare is the backbone of the zero-rupee stack. |
| G74 | **Cloudflare Workers / Pages** <br>https://developers.cloudflare.com/workers/platform/limits/ ✅ <br>https://developers.cloudflare.com/pages/platform/limits/ ✅ | Workers free: **100,000 requests/day**, **10 ms CPU/request**, **128 MB memory**, **50 subrequests/request**, 100 Workers/account ✅. Pages free: **500 builds/month**, 1 concurrent build, 20,000 files/site, 25 MiB max file, 100 custom domains, unlimited preview deployments ✅ | Workers Paid **$5/mo** ≈ ₹473 (no daily cap, 5 min CPU, 10,000 subrequests) ✅ | 🔑 **Pages hosts the Flutter web build for free with unlimited bandwidth.** 🔴 **10 ms CPU per request on free Workers means Workers cannot do routing** — they can only proxy. That is fine: use a Worker as the public API gateway and hazard-cache in front of the GraphHopper box. |

---

## 9. 🔴 TRAPS — free tiers that will bite this team

Ranked by how badly and how likely.

### Trap 1 — 🔴 Gemini's free tier trains on your users' locations

**Verified, verbatim, from Google's own API terms** ✅:

> **Unpaid Services.** Google uses [your content] "to provide, improve, and develop Google products
> and services and machine learning technologies"... "human reviewers may read, annotate, and
> process your API input and output."

> **Paid Services.** "Google doesn't use your prompts... or responses to improve our products."

**CityPulse's explanation prompt contains, by design: the user's current position, their
destination, and named hazards near them.** On the free tier, that is being retained, used for
training, and may be read by a human. For an app the team is framing as **civic safety
infrastructure** operating under the **DPDP Act 2023** (Strand C §5.4), this is not a licensing
footnote — it is a Data Fiduciary problem and it is the kind of thing a reviewer will ask about.

**Mitigations, in order of preference:**
1. **Enable billing on the Gemini project.** Tier 1 is instant once a billing account is linked ✅.
   The terms flip to "not used to improve our products" the moment the project is paid.
2. Use **GitHub Models** instead for anything with real location data — it carries the only
   affirmative privacy statement in this report (*"Your data remains within GitHub and Azure and is
   not shared with model providers"* ✅).
3. **Coarsen before prompting.** Send an H3 cell and a hazard list, never a raw lat/lng. This is
   good design regardless of vendor and is a defensible novelty claim for the paper.

⚠️ **Groq, Cerebras, Mistral, OpenRouter free models and Together all have unverified or
unpublished data terms** (§1). Do not assume any of them is safer than Gemini just because they are
quieter about it. **"We could not find a statement" is not "they don't train on it."**

### Trap 2 — 🔴 Cold starts and sleep timers will ruin the live demo

Every one of these is verified from the vendor's own docs:

| Service | Sleep behaviour | Consequence on demo day |
|---|---|---|
| **Render free** | Spins down after **15 min**, **~60 s** to wake ✅ | The examiner clicks, watches a spinner for a minute, and forms an opinion |
| **Koyeb free** | Scales to zero after **1 h** ✅ | Same |
| **Hugging Face Spaces free** | Sleeps after **48 h**, not configurable ✅ | Survives a normal demo week; dies over a break |
| **Neon free** | Auto-suspends after **5 min** ✅ | First query of the demo is cold |
| **Supabase free** | 🔴 **Project paused after 1 week of inactivity** ✅ | A project idle since the last sprint is **paused, not slow** — it needs a manual restore |
| **Fly.io trial** | **2 h of runtime or 7 days** ✅ | Not a demo host at all |

**Mitigation:** a **UptimeRobot** 5-minute HTTP ping (free, 50 monitors ✅) on a `/health` endpoint
keeps HF Spaces, Render and Neon warm and keeps Supabase "active". **And ship the
laptop-plus-Cloudflare-Tunnel path as demo insurance regardless** — Strand C §4.4 already reached
the same conclusion about data; the same discipline applies to infrastructure.

### Trap 3 — 🔴 Free tiers that vanished or halved while nobody was looking

- **Oracle halved Always Free Ampere A1** from 4 OCPU/24 GB to **2 OCPU/12 GB** ✅ — with no
  announcement (July 2026; corroborated by InfoQ, Linuxiac, heise and Oracle's own Cloud Customer
  Connect thread). **It can happen again, mid-project.**
- **AWS killed the 12-month free tier.** It is now **$100–$200 of credit and the account
  auto-closes at 6 months** ✅. Any plan built on "t3.micro is free for a year" is 18 months stale.
- **ElephantSQL is dead** — EOL **27 January 2025** ✅.
- **Fly.io's free allowances are gone**; the trial is **2 hours of runtime** ✅.

**Mitigation:** **do not let any single free tier be load-bearing.** Containerise the backend so it
can move between Oracle, HF Spaces and a laptop in under an hour, and **record which free tier you
used and on what date in the paper's reproducibility section** — because by the time anyone reads
it, the number will have changed.

### Trap 4 — 🔴 Tile and geocoding licences that forbid exactly what CityPulse does

This is the same class of error Strand C found with Google Maps Platform, and the team is likely to
walk into it again with OSM's own infrastructure:

- **OSM standard tile server**: *"Download city/country for offline use"* and similar prefetching
  *"are therefore prohibited"* ✅. **CityPulse is an offline-first app that pre-caches spatial data.
  Using `tile.openstreetmap.org` in the app breaches the policy by design, not by accident.**
- **Public Nominatim**: bans **auto-complete search**, **systematic queries**, and services
  *"whose primary function involves geocoding"*; **1 req/s absolute maximum** ✅.
- **Mapbox Geocoding**: the free 100,000/month is **Temporary** geocoding. **Caching a geocode for
  offline use makes it Permanent geocoding — which has no free tier and costs $5.00/1,000** ✅.
- **GraphHopper Directions free plan**: *"for non-commercial use only"* ✅.
- **Stadia Maps free**: *"Commercial use not allowed"* ✅.
- **MapTiler free**: MapTiler logo mandatory on the map ✅.

**Mitigation: OpenFreeMap or self-hosted PMTiles on R2 for tiles; self-hosted Photon for geocoding;
self-hosted GraphHopper for routing.** All three are free, all three are licence-clean for an
offline-first app, and all three are *the same recommendation the architecture already wanted*.

### Trap 5 — 🔴 Services that require a credit card, or that quietly start charging

| Requires a card | Does **not** require a card |
|---|---|
| **Fly.io** — *"All organizations... require a credit card on file"* ✅ | **Azure for Students** — *"No credit card required"* ✅ |
| **Google Cloud free trial** — card + auth hold ✅ | **GraphHopper free plan** ✅ |
| **Google Play** — card in your legal name, **prepaid cards not accepted** ✅ | **OpenCage** ✅, **Stadia Maps** ✅, **PostHog** ✅ |
| **Apple Developer** — $99/yr recurring ✅ | **Firebase Spark** — *"No payment method needed"* ✅ |
| **Cloudflare Workers AI** — Kimi/GLM/DeepSeek models *"require a paid billing method"* ✅ | **Railway trial**, **Oracle Always Free** (⚠️ card *is* used for identity verification at signup — unverified whether it is charged) |

**Silent-charge risk:** **Render** states that exceeding free bandwidth *"triggers billing (or
suspension if no payment method exists)"* ✅ — i.e. with a card on file, overage bills silently.
**Cloudflare KV bills even for failed lookups that return null** ✅. **Neon and Railway are
usage-metered**, so a runaway loop costs money rather than erroring.

**The only vendor in this report that guarantees in writing you cannot be surprise-billed is
PostHog**: *"Usage stops at the free tier limits, so you can't be charged by surprise"* ✅.

**Mitigation: put no card on any account that does not strictly need one, and prefer hard-stop free
tiers (Stadia's "No additional usage", PostHog, Cloudflare Workers free's 100k/day cap) over
metered ones.**

### Trap 6 — 🔴 PythonAnywhere cannot reach the internet

Free Beginner accounts have outbound access to **"Specific sites via HTTP(S) only"** — a whitelist ✅.
**CityPulse's entire ingest layer is outbound HTTP calls to Open-Meteo, GDACS, TomTom and OpenAQ.**
A whitelisted-egress host cannot run this project. Also: **100 CPU-seconds/day** ✅, which is less
than one GraphHopper graph load.

### Trap 7 — 🟡 Documentation that contradicts itself

- **Tailscale**: the pricing page's comparison table shows **Funnel starting at the Standard paid
  plan**, while the Funnel KB article says *"available for all plans"* ✅. Both are Tailscale's own
  pages. **Test before depending on it.**
- **Cerebras**: the rate-limits page shows a **1M tokens/day free allowance** and a **$5 / 30-day
  trial** on the same page ✅. It is not clear which governs.
- **Google**: the Gemini rate-limits page **no longer publishes any free-tier number**, pushing
  users to a logged-in dashboard ✅. **A quota you cannot cite is a quota you cannot design around.**

---

## 10. 🔑 THE ZERO-RUPEE STACK

One specific, named combination. Every component verified above. **Total recurring cost: ₹0.
Total credit-card requirement: none.**

| Layer | Service | Free quota relied on | Why this one |
|---|---|---|---|
| **Source control + CI** | **GitHub, public repo** | **Unlimited Actions minutes on public repos** ✅ | Also satisfies the ODbL publish-the-build-script obligation (Strand C §5.2) |
| **Routing engine + API** | **GraphHopper (Apache 2.0) + FastAPI** in one Docker image, on **Oracle Cloud Always Free A1** | **2 OCPU / 12 GB RAM, 200 GB block storage, 10 TB/mo egress** ✅ | Only free option with enough RAM *and* no sleep *and* real egress |
| **Compute fallback #1** | **Hugging Face Space (Docker SDK)** | **2 vCPU / 16 GB RAM / 50 GB disk** ✅ | More RAM than Oracle; sleeps at 48 h ✅, kept awake by G72 |
| **Compute fallback #2 / demo insurance** | **Laptop + Cloudflare Tunnel** | **Zero Trust free, "$0 forever" under 50 users** ✅ | No sleep, no cold start, no capacity lottery, real HTTPS |
| **Map tiles** | **Protomaps PMTiles (Chennai extract) on Cloudflare R2**, with **OpenFreeMap** as the live fallback | R2 **10 GB storage, 10M Class B ops/mo, zero egress** ✅; OpenFreeMap **"no limits... no API keys"** ✅ | Licence-clean for an offline-first app; no tile server to run |
| **Web front end** | **Cloudflare Pages** (Flutter web build) | **500 builds/mo, unlimited preview deployments** ✅ | Free TLS + CDN + custom domain |
| **API edge / cache** | **Cloudflare Workers** | **100,000 req/day, 10 ms CPU** ✅ | Proxy + hazard cache in front of the routing box |
| **Spatial database** | **Supabase Free + PostGIS** | **500 MB DB, 5 GB egress, 50K MAU** ✅; PostGIS enabled from the dashboard ✅ | Managed Postgres + PostGIS + auth on one free tier |
| **Hot cache / decay buffer** | **Upstash Redis Free** | **500K commands/mo, 256 MB** ✅ | Serverless; no idle cost. **Pipeline your commands.** |
| **Object storage** | **Cloudflare R2** | **10 GB, egress free** ✅ | Ships the pre-built on-device routing graph (ODbL-offered) and the replay corpus |
| **Online LLM (primary)** | **Groq** `openai/gpt-oss-120b` | **30 RPM · 1,000 RPD · 200K TPD** ✅ | Fastest free tier; won't stall on stage |
| **Online LLM (fallback)** | **GitHub Models** | **10 req/min · 50 req/day** high-tier ✅ | Only verified "not shared with model providers" ✅ |
| **Geocoding** | **Self-hosted Photon (India extract)**, with **LocationIQ 5,000/day** ✅ as fallback | Photon: Apache 2.0 ✅ | Avoids the Nominatim policy entirely |
| **Routing baseline for evaluation** | **ORS 2,000 directions/day** ✅ + **TomTom 20,000/mo** + **GraphHopper hosted 500/day** ✅ | — | Three independent baselines, all free, for the counterfactual-routing evaluation |
| **Push** | **Firebase Cloud Messaging** | **No-cost, no stated limit, no payment method needed** ✅ | Free and unmetered |
| **App distribution** | **Firebase App Distribution** | **No-cost** ✅ | **No Play Store fee, no Apple fee** |
| **Product analytics** | **PostHog** | **1M events/mo, cannot be surprise-billed** ✅ | Best free tier in the report |
| **Errors** | **Sentry via GitHub Student Pack** | 50K errors, 100K transactions ✅ | Free Sentry is 1-user; the Pack offer is not |
| **Metrics / logs / load test** | **Grafana Cloud Free** | **10K series, 50 GB logs, 3 users, 500 k6 VU-hours** ✅ | 3 users = the team; k6 hours produce a real scale number for the paper |
| **Uptime + keep-alive** | **UptimeRobot Free** | **50 monitors, 5-min interval** ✅ | Doubles as the anti-sleep ping for HF Spaces and Supabase |
| **DNS / TLS / CDN / DDoS** | **Cloudflare Free** | $0/mo ✅ | — |
| **Domain** | **Namecheap `.me` or `.TECH`** via GitHub Student Pack ✅ | 1 year free ✅ | — |

### 10.1 What this stack honestly cannot do

Being blunt, because this is the section a reviewer will press on:

1. **It has no availability guarantee anywhere.** OpenFreeMap is donation-funded with no SLA ✅.
   Oracle's allowance halved without notice ✅. FOSSGIS routing is community-run. **Nothing here is
   contractually obliged to exist on demo day.**
2. **The LLM path caps at roughly 130 explanations/day** (Groq's 200K TPD ÷ ~1.5K tokens per
   explanation). That is a demo budget. At 1,000 users it is gone by 9 a.m.
3. **Supabase's 500 MB fills quickly.** At ~1 KB per hazard event with geometry, 500 MB ≈ 500,000
   events. A live monsoon ingest at 5,000 events/day fills it in ~3 months, and that is before user
   data. **Plan a retention/rollup policy from day one, not after it fills.**
4. **Upstash's 500K commands/month is ~16,600/day.** A naive three-Redis-ops-per-request design is
   over budget at 5,500 requests/day. **Pipelining is not an optimisation here, it is a requirement.**
5. **Oracle A1 capacity in Indian regions is a lottery.** ⚠️ I could not verify current availability
   for new India signups. **If it fails, the stack still works** (HF Spaces), but with a 48-hour
   sleep timer and non-persistent disk.
6. **Cloudflare Workers' 10 ms CPU limit means no computation at the edge** ✅ — the Worker is a
   proxy and a cache, nothing more.
7. **KV cannot buffer hazards** (1,000 writes/day ✅) and **D1 has no PostGIS** ✅.
8. **No free tier here permits commercial use across the board.** Stadia (free = non-commercial ✅),
   GraphHopper free (non-commercial ✅), Open-Meteo (non-commercial, Strand C ✅). **The paper's
   commercialisation section must name the paid migration path for each**, exactly as Strand C did
   for Open-Meteo → OpenWeather.

---

## 11. THE ₹500/MONTH UPGRADE PATH

₹500/month ≈ **$5.29**. That is a real constraint, so here is the arithmetic for the three
candidates, and the recommendation.

| Option | Cost | What it fixes | Verdict |
|---|---|---|---|
| **A. Cloudflare Workers Paid** | **$5.00/mo = ₹473** ✅ | Removes the 100k req/day cap; 5 min CPU instead of 10 ms; 10,000 subrequests ✅ | ❌ Fixes a limit they will not hit at demo scale |
| **B. Supabase stays free + Upstash pay-as-you-go** | **$0.20 per 100K commands** ✅ → ₹500 buys **2.65M commands/month** (5.3× the free tier) | Removes the Redis ceiling | 🟡 Useful only once they are actually over 500K/month |
| **C. Fly.io `shared-cpu-1x` 1 GB** | **$5.70/mo = ₹539** ✅ (slightly over) — or **256 MB at $1.94 = ₹183** ✅ | A guaranteed always-on box with no capacity lottery | 🟡 1 GB is too small for GraphHopper; 256 MB is only good as a keep-alive/watchdog |
| 🔑 **D. Gemini paid tier (Tier 1), budget ₹500/month of tokens** | **₹500 ≈ $5.29.** At Gemini 3.5 Flash-Lite (**$0.30/M in, $2.50/M out** ✅): a 1,200-in / 250-out explanation costs $0.00036 + $0.000625 = **$0.000985**. **$5.29 ÷ $0.000985 ≈ 5,370 explanations/month ≈ 179/day** | 🔑 **(a) Flips the data terms** — free tier *"content used to improve our products"* → paid *"Google doesn't use your prompts"* ✅. **(b)** Removes the free-tier rate-limit risk from the live demo. **(c)** Buys better model quality than any free tier here. | 🔑 **This is the ₹500.** |

**Recommendation: option D.** For ₹500/month the team gets **more daily explanations than the Groq
free tier allows (179/day vs ~130/day), on a better model, with the training clause switched off.**
It is the only ₹500 that fixes a *correctness and ethics* problem rather than a capacity one.

**Keep everything else free.** Do not spend ₹500 on hosting while Oracle Always Free and a
Cloudflare Tunnel both exist.

---

## 12. WHAT A REAL 1,000-USER PILOT WOULD COST — arithmetic shown

**Assumptions, stated so they can be challenged:**
- 1,000 registered users, 30-day month
- 3 hazard-aware route requests per user per day → **3,000 routes/day = 90,000 routes/month**
- 1 LLM explanation per route: **~1,200 input tokens** (hazard context + route summary + system
  prompt) and **~250 output tokens**
- ~60 map tiles loaded per routing session
- ~6 Redis operations per request (naive), ~2 with pipelining
- Hazard ingest: 5,000 events/day, ~1 KB each with geometry

### 12.1 LLM (the only unavoidable cost)

```
Input  : 90,000 × 1,200 = 108,000,000 tokens = 108 M
Output : 90,000 ×   250 =  22,500,000 tokens = 22.5 M

Gemini 3.5 Flash-Lite  ($0.30/M in, $2.50/M out)   ✅
  Input  : 108.0 × $0.30 = $32.40
  Output :  22.5 × $2.50 = $56.25
  TOTAL  = $88.65 / month  ≈ ₹8,377 / month

Gemini 3.8 Flash       ($0.75/M in, $3.75/M out)   ✅
  Input  : 108.0 × $0.75 = $81.00
  Output :  22.5 × $3.75 = $84.38
  TOTAL  = $165.38 / month ≈ ₹15,628 / month

Gemini 2.5 Pro         ($1.25/M in, $10.00/M out)  ✅
  TOTAL  = $135.00 + $225.00 = $360.00 / month ≈ ₹34,016 / month
```

**Note the shape: output tokens dominate.** Cutting the explanation from 250 to 120 tokens roughly
halves the bill. **"Terse explanations" is a cost decision as much as a UX one.**

### 12.2 Map tiles

```
90,000 sessions × 60 tiles = 5,400,000 tile requests / month

Self-hosted PMTiles on Cloudflare R2:
  Class B ops  : 5.4 M  (free tier = 10 M/month)      ✅  →  $0.00
  Storage      : ~1 GB  (free tier = 10 GB)           ✅  →  $0.00
  Egress       : free on R2                           ✅  →  $0.00
  TOTAL = $0.00 / month

For contrast — Mapbox Vector Tiles (200k free, then $0.25/1,000) ✅:
  (5,400,000 − 200,000) / 1,000 × $0.25 = $1,300.00 / month ≈ ₹1,22,837

MapTiler free tier = 100,000 API requests/month ✅ → exhausted on day 1.
Stadia free tier   = 200,000 credits/month ✅    → exhausted on day 2.
```

🔑 **Self-hosting the basemap is worth ~$1,300/month at this scale. It is the single largest cost
avoided in the whole architecture, and it costs nothing to do.**

### 12.3 Routing

```
90,000 routes/month, self-hosted GraphHopper on Oracle A1 (2 OCPU / 12 GB)  ✅
  = 3,000/day = ~2/minute average.  Peak maybe 20–30/minute.
  A city-sized GraphHopper graph serves this on 2 ARM cores comfortably.
  TOTAL = $0.00 / month

For contrast — hosted alternatives at 90,000 routes/month:
  ORS free            = 2,000/day  = 60,000/month  ✅  → 33% short, and non-commercial
  TomTom free         = 20,000/month             ✅  → 78% short
  GraphHopper free    = 500 credits/day          ✅  → 83% short; €69/mo Basic = 5,000/day ✅ (covers it)
  Mapbox Directions   = 100,000/month free       ✅  → covers it, BUT the Navigation SDK free
                                                       tier is 100 monthly active users ✅ → fails
```

### 12.4 Database, cache, egress, push

```
PostGIS (Supabase):
  Hazard events: 5,000/day × 30 × 1 KB = 150 MB/month of new data
  Free tier = 500 MB total  ✅  →  full in ~3 months with zero user data
  Supabase Pro = $25.00/month ≈ ₹2,362  (8 GB disk, 250 GB egress)  ✅
  → REQUIRED at this scale.

Redis (Upstash):
  Naive  : 90,000 × 6 = 540,000 commands/month  (free = 500,000 ✅) → just over
  With pipelining: 90,000 × 2 = 180,000/month   → comfortably free
  If over: $0.20 per 100K ✅ → 540K = $1.08/month ≈ ₹102
  Or: run Redis on the Oracle box → $0.00

Egress:
  Oracle Always Free: 10 TB/month outbound ✅ → $0.00
  R2 egress: free ✅                          → $0.00

Push (FCM): "No-cost", no stated limit ✅      → $0.00

Analytics (PostHog): 1,000 users × ~20 events/day × 30 = 600,000 events/month
  Free tier = 1M events/month ✅               → $0.00

Monitoring (Grafana Free, UptimeRobot Free)    → $0.00
```

### 12.5 Pilot totals

| Configuration | Monthly USD | Monthly INR |
|---|---|---|
| 🔑 **Recommended: Gemini Flash-Lite + Supabase Pro + everything else free** | **$88.65 + $25.00 = $113.65** | **≈ ₹10,739/month** |
| Same, but with terse (120-token) explanations | $32.40 + $27.00 + $25.00 = $59.40 | ≈ ₹5,613/month |
| Cheapest defensible: Groq/free LLMs + Supabase Pro | $25.00 | ≈ ₹2,362/month |
| If they had used Mapbox tiles instead of self-hosting | +$1,300.00 | +≈ ₹1,22,837/month |
| If they had used Gemini 2.5 Pro for explanations | $360.00 + $25.00 = $385.00 | ≈ ₹36,379/month |
| **One-time:** Google Play registration | $25.00 | ≈ ₹2,362 one-time |

**Headline for the paper: a 1,000-user CityPulse pilot costs roughly ₹10,700/month — about
₹10.70 per user per month — and over 90% of that is LLM output tokens.** Everything else in the
stack (routing, tiles, storage, push, monitoring, 10 TB of egress) genuinely runs at ₹0.

**The three levers that matter, in order:** (1) shorten the explanation, (2) cache explanations for
repeated hazard/route combinations, (3) route the cheap cases to the on-device model that the
architecture already has (Strand C / PROJECT_BRIEF step 4). **Lever 3 is the project's own core
novelty claim, and this cost model is the strongest possible argument for it** — the offline model
is not just a resilience feature, it is what makes the economics work.

---

## 13. WEEK-1 ACTION LIST (cost/infra only)

Ordered by lead time, longest first — the same logic Strand C used.

1. **Attempt an Oracle Cloud Always Free A1 provision in an India region today.** If it returns
   "out of host capacity", retry at off-peak hours for three days, then stop and use HF Spaces.
   **Do not discover this in week 5.**
2. **Claim the GitHub Student Developer Pack** (Azure $100, Heroku $13/mo × 24, Sentry upgrade,
   free domain). Requires student verification, which takes days.
3. **Submit the Anthropic AI for Science application** — reviewed the first Monday of each month ✅,
   so a late submission costs a full month.
4. **Make the repo public** — unlocks unlimited GitHub Actions ✅ and satisfies the ODbL
   publish-the-build-script obligation from Strand C §5.2.
5. **Create the Supabase project and enable PostGIS**; screenshot the extensions page as evidence it
   works on Free.
6. **Build the Chennai PMTiles extract and upload it to R2.** `pmtiles extract` with a Chennai
   bounding box, `--maxzoom 14` or 15.
7. **Set up UptimeRobot** with 5-minute pings on the backend health endpoint **and** a Supabase
   query endpoint — this is the anti-sleep insurance for the whole stack.
8. **Get `cloudflared` working from a team laptop** and confirm it survives the campus network.
   This is the demo-day fallback and it must be tested, not assumed.
9. **Register Groq + GitHub Models + OpenRouter keys** and put all three behind one provider
   interface in the code. Provider failover on demo day is worth more than any single quota.
10. **Decide the Gemini billing question explicitly and write it down.** Either enable billing, or
    commit in code that real location data never reaches Gemini. **Do not leave this implicit.**
11. **Screenshot every free-tier quota page you rely on, with the date.** Oracle's silent halving
    proves these numbers are not stable, and the paper needs a defensible "as of" claim.
12. **Do not create a Google Play developer account yet.** Firebase App Distribution ✅ covers the
    academic deliverable at ₹0.

---

## 14. THINGS I COULD NOT VERIFY — explicit flags

1. **Gemini free-tier per-model RPM/TPM/RPD.** Google removed them from the docs; they are only
   visible in a logged-in AI Studio dashboard ✅. **Every public number is secondary.**
2. **Groq's data-retention and training terms.** The Privacy Policy explicitly excludes GroqCloud
   API data ✅ and points to a Services Agreement + DPA I could not retrieve.
3. **Whether Cerebras' 1M tokens/day is permanent or part of a 30-day $5 trial** — both appear on
   the same docs page ✅.
4. **Mistral's free-tier rate limits** — not published; console-only ✅.
5. **Together AI's free tier** — the vendor explicitly declines to publish limits ✅.
6. **OpenRouter's `:free` model data policy** — the privacy doc references "separate settings for
   paid and free models" without stating them ✅.
7. **Whether Mapbox requires a credit card** for the free tier — not stated on the pricing page;
   the dedicated free-tier help page 404s ✅.
8. **HERE's freemium limits** — not published on their pricing page ✅ (Strand C reached the same
   conclusion independently).
9. **ORS per-endpoint quotas** beyond `directions` — the plans page renders client-side and returns
   no content to a fetcher ✅.
10. **FOSSGIS Valhalla/OSRM fair-use limits and base URLs** — not published anywhere I could fetch ✅.
    **Do not hardcode.**
11. **Tailscale Funnel on the free plan** — the pricing page and the Funnel KB article contradict
    each other ✅.
12. **Cloudflare Tunnel bandwidth limits and whether a Cloudflare-hosted domain is required** — not
    stated on the connect-networks docs page ✅.
13. **Oracle A1 capacity availability for new India signups in 2026** — cannot be verified without
    attempting a real provision. **This is the highest-impact unknown in the report.**
14. **Photon's India-only index size** — the repo documents the worldwide figures (95 GB disk,
    64 GB RAM) ✅ but not per-country extracts.
15. **Whether Oracle charges the card used for Always Free identity verification** — not stated.
16. **Hetzner Cloud's current CX/CAX prices** — the pricing table did not render to a fetcher ✅.
    Noted only because Hetzner has a **Singapore** region (nearest to Chennai of their locations ✅)
    and **no India region** ✅.
17. **Supabase PostGIS on the Free plan specifically** — PostGIS is listed as supported ✅ and no
    page states a plan restriction ✅, but no page affirmatively says "available on Free" either.
18. **Azure India VM prices** for sizing the $100 student credit.
19. **Hugging Face PRO subscription price** — the inference-pricing page states the $2/month credit
    but not the subscription cost ✅.
20. **Replit's current free-plan specifics** — absent from the pricing page ✅.

---

## Sources

All fetched 2026-09-12 unless noted.

**LLM APIs**
[Gemini API pricing](https://ai.google.dev/gemini-api/docs/pricing) ·
[Gemini API Additional Terms of Service](https://ai.google.dev/gemini-api/terms) ·
[Gemini API rate limits](https://ai.google.dev/gemini-api/docs/rate-limits) ·
[Gemini API available regions](https://ai.google.dev/gemini-api/docs/available-regions) ·
[Groq rate limits](https://console.groq.com/docs/rate-limits) ·
[Groq Privacy Policy](https://groq.com/privacy-policy/) ·
[Groq Terms of Use](https://groq.com/terms-of-use/) ·
[Cerebras rate limits](https://inference-docs.cerebras.ai/support/rate-limits) ·
[Cloudflare Workers AI pricing](https://developers.cloudflare.com/workers-ai/platform/pricing/) ·
[GitHub Models rate limits](https://docs.github.com/en/github-models/use-github-models/prototyping-with-ai-models) ·
[GitHub Models at scale (data privacy statement)](https://docs.github.com/en/github-models/github-models-at-scale/use-models-at-scale) ·
[OpenRouter API limits](https://openrouter.ai/docs/api-reference/limits) ·
[OpenRouter privacy & logging](https://openrouter.ai/docs/features/privacy-and-logging) ·
[Mistral pricing](https://mistral.ai/pricing) ·
[Mistral tier docs](https://docs.mistral.ai/deployment/laplateforme/tier/) ·
[Hugging Face Inference Providers pricing](https://huggingface.co/docs/inference-providers/pricing) ·
[Together AI rate limits](https://docs.together.ai/docs/rate-limits)

**Student / academic credits**
[Azure for Students](https://azure.microsoft.com/en-us/free/students) ·
[GitHub Student Developer Pack](https://education.github.com/pack) ·
[Google Cloud free features](https://docs.cloud.google.com/free/docs/free-cloud-features) ·
[AWS Free Tier](https://aws.amazon.com/free/) ·
[AWS Educate](https://aws.amazon.com/education/awseducate/) ·
[Anthropic AI for Science Program](https://support.claude.com/en/articles/11199177-anthropic-s-ai-for-science-program)

**Tiles, geocoding, routing**
[OpenFreeMap](https://openfreemap.org/) ·
[OSMF tile usage policy](https://operations.osmfoundation.org/policies/tiles/) ·
[OSMF Nominatim usage policy](https://operations.osmfoundation.org/policies/nominatim/) ·
[Protomaps basemap downloads](https://docs.protomaps.com/basemaps/downloads) ·
[Protomaps PMTiles docs](https://docs.protomaps.com/pmtiles/) ·
[VersaTiles](https://versatiles.org/) ·
[MapTiler Cloud pricing](https://www.maptiler.com/cloud/pricing/) ·
[Stadia Maps pricing](https://stadiamaps.com/pricing/) ·
[Thunderforest pricing](https://www.thunderforest.com/pricing/) ·
[CARTO pricing](https://carto.com/pricing) ·
[Mapbox pricing](https://www.mapbox.com/pricing) ·
[LocationIQ pricing](https://locationiq.com/pricing) ·
[Geoapify pricing](https://www.geoapify.com/pricing/) ·
[OpenCage pricing](https://opencagedata.com/pricing) ·
[Photon (komoot) repository](https://github.com/komoot/photon) ·
[openrouteservice FAQ (rate limits)](https://giscience.github.io/openrouteservice/frequently-asked-questions.html) ·
[openrouteservice restrictions](https://openrouteservice.org/restrictions/) ·
[GraphHopper Directions API pricing](https://www.graphhopper.com/pricing/) ·
[HERE pricing](https://www.here.com/get-started/pricing) ·
[OSM wiki — online routers](https://wiki.openstreetmap.org/wiki/Routing/online_routers) ·
[FOSSGIS Valhalla demo](https://valhalla.openstreetmap.de/)

**Compute / hosting**
[Oracle Cloud Always Free resources](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm) ·
[Oracle halves free A1 — InfoQ](https://www.infoq.com/news/2026/07/oracle-cloud-free-tier-limits/) ·
[Oracle Cloud Customer Connect — updated A1 allocation](https://community.oracle.com/customerconnect/discussion/970310/oci-always-free-updated-ampere-a1-compute-allocation) ·
[Hugging Face Spaces overview (free hardware)](https://huggingface.co/docs/hub/spaces-overview) ·
[Hugging Face Spaces GPUs (sleep time)](https://huggingface.co/docs/hub/spaces-gpus) ·
[Fly.io pricing](https://fly.io/docs/about/pricing/) ·
[Fly.io free trial](https://fly.io/docs/about/free-trial/) ·
[Render free tier docs](https://render.com/docs/free) ·
[Render pricing](https://render.com/pricing) ·
[Railway pricing](https://railway.com/pricing) ·
[Koyeb instances reference](https://www.koyeb.com/docs/reference/instances) ·
[PythonAnywhere pricing](https://www.pythonanywhere.com/pricing/) ·
[Replit pricing](https://replit.com/pricing) ·
[Cloudflare plans (incl. Zero Trust free)](https://www.cloudflare.com/plans/) ·
[ngrok pricing](https://ngrok.com/pricing) ·
[Tailscale pricing](https://tailscale.com/pricing) ·
[Tailscale Funnel KB](https://tailscale.com/kb/1223/funnel) ·
[Hetzner Cloud](https://www.hetzner.com/cloud/)

**Database / cache / storage**
[Supabase pricing](https://supabase.com/pricing) ·
[Supabase PostGIS extension](https://supabase.com/docs/guides/database/extensions/postgis) ·
[Supabase extensions list](https://supabase.com/docs/guides/database/extensions) ·
[Neon pricing](https://neon.com/pricing) ·
[Aiven pricing](https://aiven.io/pricing) ·
[ElephantSQL end-of-life announcement](https://www.elephantsql.com/blog/end-of-life-announcement.html) ·
[Upstash Redis pricing](https://upstash.com/pricing/redis) ·
[Redis Cloud pricing](https://redis.io/pricing/) ·
[Cloudflare D1 pricing](https://developers.cloudflare.com/d1/platform/pricing/) ·
[Cloudflare KV pricing](https://developers.cloudflare.com/kv/platform/pricing/) ·
[Cloudflare R2 pricing](https://developers.cloudflare.com/r2/pricing/) ·
[Cloudflare Workers limits](https://developers.cloudflare.com/workers/platform/limits/) ·
[Cloudflare Pages limits](https://developers.cloudflare.com/pages/platform/limits/)

**Mobile / app services**
[Firebase pricing (Spark plan)](https://firebase.google.com/pricing) ·
[OneSignal pricing](https://onesignal.com/pricing) ·
[ntfy docs](https://docs.ntfy.sh/) ·
[Google Play Console registration fee & verification](https://support.google.com/googleplay/android-developer/answer/6112435) ·
[Apple Developer Program enrollment (incl. education fee waiver)](https://developer.apple.com/support/enrollment/)

**Dev / ops**
[GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions) ·
[Sentry pricing](https://sentry.io/pricing/) ·
[PostHog pricing](https://posthog.com/pricing) ·
[Grafana Cloud pricing](https://grafana.com/pricing/) ·
[UptimeRobot pricing](https://uptimerobot.com/pricing/)

**FX**
[US Federal Reserve H.10 foreign exchange rates](https://www.federalreserve.gov/releases/h10/current/) — INR 94.4900 per USD, 2026-09-04
