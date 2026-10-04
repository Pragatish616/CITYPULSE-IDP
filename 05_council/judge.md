# Judge: CityPulse AI

## VERDICT: FIX FIRST, and this is the last FIX FIRST
The Skeptic and Investor win on the facts. Nobody pays, Google already does free flood reports, and the commuter default is nearly blind to hazards (7/100 routes changed, +0.026 s). The crowd evidence also makes Brier worse than the prior. The Believer is right about one thing: the moat is labels, not maths. But the team still has no labels. The 12 Sep council gave the same verdict for the same reason, and the fix it asked for (traversal-silence) never happened. If this second FIX FIRST also stalls, the startup is KILL.

**Split:** The **research paper is BUILD** now. Its bar is honest evaluation, not revenue. Report the negative and weak calibration results, the re-scored routes, and the "λ caps penalty at (1+λs)" proposition. Drop the ALT novelty claim, which is already in Delling & Wagner 2007, and correct the "caution grows as evidence thins" claim. The **startup is FIX FIRST**, and it turns into KILL on the date below.

## BIGGEST RISK
The team has no live, timestamped, street-level passability signal it can get, so the product is a static 2015 hazard map with uncertainty decoration.

## 10-MINUTE TEST (no code)
Open the CFM-DSS public WFS GetCapabilities in a browser and pull one GetFeature from any subway-barrier, flood-meter or sensor layer.
- **Pass:** the layer has a per-location reading with a timestamp from today.
- **Fail:** only static polygons or old snapshots. In that case, the same day, email GCC ICCC and GCTP one question: "Can we poll barrier and sensor state this monsoon?"

## EXACT CHANGE THAT FLIPS IT TO BUILD
By 15 Oct, cut the scope from 471k edges to GCC's 22 subways plus its 290 named waterlogging points. Wire one live, timestamped feed into the belief engine, from CFM-DSS or a written yes from GCC/GCTP. Log every reading as a passability label. That fixes the single-timestamp, no-depth, positives-only corpus. Commercial flip: the Investor's bar of ₹1,00,000 committed in writing by one non-grant buyer before 15 Dec. No feed by 15 Oct means the startup is KILL and the team ships the paper only.

---
SHARED NOTE
Idea: CityPulse AI, offline hazard-aware Chennai routing on decaying per-segment flood probabilities, plus a passability feed for insurers and fleets.
Verdict: FIX FIRST (2nd time; startup is KILL if no live feed by 15 Oct). Research paper: BUILD now as an honest evaluation with the negative results.
Risk: The team has no live, timestamped street-level passability signal, so it is a static 2015 hazard map that Google already beats for free.
Next: Check the CFM-DSS WFS for live barrier and sensor timestamps today; email GCC ICCC and GCTP; rescope to 22 subways + 290 points; chase ₹1 lakh LOI by 15 Dec.
