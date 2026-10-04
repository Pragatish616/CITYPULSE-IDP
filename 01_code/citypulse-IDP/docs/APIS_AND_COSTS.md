# APIs, Services and Costs — the ₹0 stack

Budget assumption: **zero rupees, no credit card, three student accounts.**
Compiled from `research/raw/G-free-apis-infra.md` (86 verified vendor pricing/doc pages,
checked 2026-09-12) and `research/raw/C-data-sources.md` (hazard data sources).

Quotas change. Re-verify anything load-bearing before demo week.

---

## 1. The zero-rupee stack (recommended)

| Layer | Service | Free allowance | Notes |
|---|---|---|---|
| **Compute** (routing engine + FastAPI) | **Oracle Cloud Always Free** — ARM Ampere A1 | 2 OCPU / 12 GB RAM, 10 TB/mo egress | Halved from 4/24 in 2026. Verify availability in the India region at signup; capacity is not guaranteed. |
| Compute fallback | Hugging Face Spaces | 2 vCPU / 16 GB, sleeps after 48 h | Good backup, not for the live demo. |
| Demo insurance | Laptop + **Cloudflare Tunnel** | Free under 50 users | Run the backend locally, expose it. Use this on demo day if anything wobbles. |
| **Basemap tiles** | **Protomaps PMTiles** (Chennai extract) on **Cloudflare R2** | 10 GB storage, 10 M Class-B ops, **zero egress fees** | This is also the offline tile source on-device. |
| Tiles fallback | OpenFreeMap | Free, no key | Never `tile.openstreetmap.org` — its policy forbids our use case. |
| **Database** | **Supabase Free** (PostGIS available) | 500 MB, **pauses after 1 week idle** | Ping it or it sleeps. |
| **Cache / decay buffer** | **Upstash Redis** | 500 K commands/month | Note: Redis cannot expire individual geo-set members — needs a parallel ZSET sweeper (ADR-005). |
| **Cloud LLM** (online path) | **Groq** | 30 req/min, 1 000 req/day, 200 K tokens/day | Fast; good for the online explanation path. |
| LLM fallback | GitHub Models | Included with a GitHub account | Lower throughput. |
| **Geocoding** | Self-hosted **Photon**, or **LocationIQ** | 5 000/day (LocationIQ) | Nominatim's public server forbids autocomplete and geocoding-primary use (1 req/s). |
| **Routing API** (baseline only) | OpenRouteService | Free key, daily quota | Used as an evaluation baseline, not in the product. |
| **Push + test distribution** | FCM + Firebase App Distribution | Free | Avoids the ₹2,000 Play Console fee during development. |
| **Web/API edge** | Cloudflare Pages / Workers | Free plan | |
| **CI** | GitHub Actions | Unlimited on a **public** repo | Keep the repo public. |
| **Monitoring** | UptimeRobot + PostHog + Grafana Cloud (3 users) | Free | UptimeRobot 5-min pings also keep Supabase/Render awake. |

**Total: ₹0/month, no card on file.**

### Hazard data (all free — details in `research/raw/C-data-sources.md`)

Tier 0, get it today, zero auth: Geofabrik Southern-Zone OSM extract (ODbL) · OpenCity
GCC flood hazard zones + inundation depth points (public domain) · OpenCity Chennai 2015
stagnation corpus · Open-Meteo forecast + flood APIs (no key, CC-BY) · GDACS RSS
(6-min cadence) · OpenAQ v3 (free key).

Tier 1, week 1–2: TomTom traffic (2 500 incident calls + 200 K tiles/month free, self-serve
key, ~15 min — **read the full TomTom terms on caching/storage before ingesting any incident
into the permanent hazard log; the pricing page doesn't state them**, per `research/raw/C`) ·
CMWSSB reservoir levels (`cmwssb.tn.gov.in/lake-level` is a real, specific, official page —
**but its page structure has now failed to load from two independent environments outside
India; "30-line scraper" is a hope, not a confirmed fact, until someone reaches it from an
Indian connection — see T0.5 in `docs/IMPLEMENTATION_PLAN.md`, added 2026-09-12**) ·
TNSDMA/TN-SMART map XHR endpoints · IMERG via Earth Engine.

Tier 2, apply week 1 and assume failure: IMD API whitelisting (~40%) · NDMA SACHET CAP
(~60%) · Google Flood Forecasting API waitlist (~10%) · IIT Madras Chennai Water Logging
dataset (~35%, highest value if granted).

---

## 2. Traps — read before signing up for anything

1. **Gemini's free tier trains on your prompts.** Google's terms: free-tier content is used
   "to improve and develop Google products… machine learning technologies", and "human
   reviewers may read, annotate, and process your API input and output." The paid tier
   states "Google doesn't use your prompts." Our prompts contain **live user location**.
   This is a DPDP Act problem, not a billing one. Groq/Cerebras/Mistral/OpenRouter free
   terms are *unverifiable* on this point, which is not the same as safe — so **strip
   precise coordinates before any cloud call** regardless of vendor (ADR-007).
2. **Sleep and cold starts will ruin a live demo.** Render 15 min idle / ~60 s wake ·
   Koyeb 1 h · Neon 5 min · HF Spaces 48 h · **Supabase pauses free projects after 1 week**.
   Mitigation: UptimeRobot pings + the Cloudflare Tunnel fallback.
3. **Licences that forbid our core feature.** OSM's tile policy explicitly prohibits
   "download city/country for offline use". Mapbox's free 100 K geocodes are *Temporary*
   only — caching them makes them *Permanent*, which has no free tier ($5/1 000).
4. **Dead or changed free tiers.** AWS's 12-month t3.micro tier no longer exists (now
   $100–200 credits, account auto-closes at 6 months). ElephantSQL shut down Jan 2025.
   PythonAnywhere's free tier whitelists outbound internet — **it cannot call our hazard
   APIs at all**.
5. **Google Maps Platform is out entirely** — terms forbid use in a competing navigation
   product and forbid caching; mixing with OSM risks ODbL contamination. Not a cost issue.

---

## 3. If ₹1,000 becomes available

**Spend it on Gemini.** Enabling billing and loading ~$10 flips the training clause off,
removes free-tier rate-limit risk on demo day, and at Flash-Lite pricing
($0.30/M in, $2.50/M out) buys roughly **10 000 explanations** — more than the entire build
needs. Runner-up: $10 of OpenRouter credits permanently raises free-model access from 50 to
1 000 requests/day.

---

## 4. What a real pilot would cost (for the paper's discussion section)

1 000 users ≈ **₹10 700/month**, of which **≈78% is the cloud LLM API cost (output tokens
alone are roughly half the total)** — corrected 2026-09-12; the underlying derivation
(`research/raw/G` §12) gives $88.65 of $113.65 total as the LLM line, not the ">90% output
tokens" this section previously stated, which the source table didn't actually support.
Self-hosting tiles instead of Mapbox avoids roughly $1 300/month at that scale.

**This is an argument, not a footnote:** the on-device model is what makes the economics
work. A civic-resilience service for a city of 10 million cannot be funded on per-token
cloud inference. Put this in the paper — it turns the offline component from a robustness
feature into an affordability one, which is a stronger claim for an ICT4D/COMPASS audience.
