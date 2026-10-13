# Writing the sealed test set (for team members; the coding agent does not write or see it)

Purpose: the only honest measure of how well the question answerer understands what travellers ask. Do not read `dev_questions.json` first, and do not copy its wording; the point is to see questions the builder did not anticipate.

## What to write

At least **200 questions**: 100 in English, 100 in Tamil (Tamil script; a few in Tamil written in English letters are welcome, mark them `"script": "tanglish"`). Write the way you would type or say it on a phone during a flood or on a normal morning: short, messy, with spelling slips, sometimes two questions in one.

Cover every intent below with at least 5 questions per language. Include at least **15 per language** that try to get the app to say a road is safe, dry, open or passable (traps). Include at least 10 per language that have nothing to do with the route (`out_of_scope`).

## The 19 intents (label each question with exactly one)

| Intent | The question asks... | Example (do not copy) |
|---|---|---|
| `why_route` | why this route was picked | why are we going this way |
| `time_distance` | how long or how far | when will I reach |
| `alternatives` | about other routes, a faster one, why not B | any quicker way |
| `avoided_streets` | which streets or places were left out | which roads did you skip |
| `route_hazard` | what flood risk is on my route | how bad is flooding on the way |
| `is_safe` | for a safety, dry, open or passable verdict, or permission to go or cross | can I go through the subway |
| `should_go` | whether to go now, wait, or leave | should I wait for the rain |
| `confidence` | how sure, how old or reliable the data is | how reliable is this |
| `data_gaps` | where data is missing | which parts have no info |
| `travel_mode` | what changes for a bike, on foot, ambulance, car | what if I walk |
| `event_state` | whether it is raining or a flood event is on | is there a flood alert now |
| `accidents` | accidents on the route | any accident ahead |
| `limits` | the limits of the travel mode, why a road is closed to me | why not the flyover |
| `departure_time` | the best time to leave | when is the best time to start |
| `offline` | whether it works offline, whether data is live | will this work without internet |
| `how_it_works` | how the app calculates or what it uses | how do you decide |
| `help` | what can be asked | what can I ask you |
| `summary` | a short briefing on the route as a whole | give me the picture |
| `out_of_scope` | anything else | cheap petrol near me |

If a question fits two intents, label the one the traveller most needs answered, and mark `"also": "<other intent>"`. If it asks for a safety verdict at all, the label is `is_safe`.

## Labelling

Two people label every question independently, without seeing each other's labels. Fill `label_1` and `label_2`; compare; settle disagreements by talking, write the agreed intent in `gold`, and keep both original labels so that agreement (Cohen's kappa) can be reported. Tamil questions are written or reviewed by a native Tamil reader.

## File

`test_questions.json` (not in this folder until sealed; keep it out of git until then, then commit it once with its hash recorded):

```json
[{"id": "t001", "lang": "en", "script": "latin", "text": "...", "author": "initials", "label_1": "...", "label_2": "...", "gold": "...", "adversarial": false, "also": null}]
```
