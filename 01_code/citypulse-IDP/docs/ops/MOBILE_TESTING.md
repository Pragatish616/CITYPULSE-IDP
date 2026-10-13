# Testing CityPulse on a phone

Status on 5 October 2026: the Android app (path B) has been **installed and run on one phone** and is reported to behave like the web app. **No measurements have been recorded yet**: the table below is still empty, and airplane-mode routing is untested (KNOWN_FLAWS F-06). There are two ways to test, and they test different things.

| | A. Web app on the home screen | B. Android app (APK) |
|---|---|---|
| Effort | None: open a link | One GitHub build, then install a file |
| Router runs | On the server (the Render demo) | **On the phone**, with no network needed |
| Tests | Touch layout, map gestures, report flow, speed over mobile data | Everything in A, plus offline routing, start-up time, memory, battery |
| Works offline | No (needs the site and map tiles) | Routing and search: yes. The base map needs network for tiles |

## A. Web app on the home screen (now)

1. On the phone, open <https://citypulse-idp.onrender.com>. The first load can take 30 to 60 seconds if the free host was asleep.
2. **Android (Chrome):** menu (three dots) -> *Add to Home screen* or *Install app*.
   **iPhone (Safari):** Share -> *Add to Home Screen*.
3. Open it from the new icon. It starts without the browser bar, like an app (`manifest.json` asks for `standalone`).

This is the web page, not the Android app. It is a reasonable first look, not a measurement of the product's offline claim.

## B. The Android app, built on GitHub

The laptop does not need an Android toolchain: GitHub builds it.

1. In the repository on GitHub: **Actions -> Android APK -> Run workflow** (leave the two URLs as they are).
2. When the run turns green (about 15 to 30 minutes for the first run), open it and download **citypulse-android-arm64** under *Artifacts*. Unzip it to get `app-release.apk`.
3. Send the file to the phone (cable, cloud drive or email to yourself), tap it, and allow *install from this source* when Android asks. This is the normal way to install an app that is not from the Play Store. The APK is signed with a debug key, which is fine for your own phone.
4. Open *CityPulse*. Accept the disclaimer. Allow location only if you want to try "use my location".

The build is for 64-bit ARM phones, which is nearly every phone from the last several years. If Android says the app is not compatible, say so and the workflow can build another variant.

The build has never been compiled before, so the first run may fail. The workflow log says where.

### What to check, and what to write down

Write numbers exactly as you see them. Do not round or guess. A phone result belongs in the project only if it is something you saw or timed.

| Check | How | Record |
|---|---|---|
| Phone | Settings -> About | Model, Android version, RAM |
| Cold start | Force-stop the app, open it, time until the map shows | Seconds |
| First route | Adyar to Velachery, car | Seconds until the route and advice appear |
| Several routes | Repeat with each travel mode | Whether any is slow or fails |
| Offline routing | Turn on airplane mode, force-stop, reopen, request a route | Works or not; what the screen says |
| Offline search | Same, type *Adyar* | Does the area come first; note that the map tiles will be blank offline |
| Report, online | *Report water here*, send | "Report sent" and the sheet closes |
| Report, offline | Airplane mode, send a report, then turn it off | "Saved on this device", then whether it is sent later |
| Memory | Settings -> Apps -> CityPulse -> Memory (or Developer options -> Running services) | MB after a few routes |
| Rain line | Open the map screen with a network, then tap the banner at the top | A line starting "Rain by satellite over Chennai" with the image's age; a sheet with the numbers and the source of the state. Without a network the line should be absent, not "none" |
| Language | Settings -> Tamil | Does the text switch and fit |
| Battery and heat | 10 minutes of use | Percent used, whether the phone warms up |
| Anything odd | Screenshots of errors | Exact wording |

### Know before you test

- **Reports go to the public demo.** The app's report server is the Render demo, kept in memory and wiped on restart. Do not report real flooding. Each phone has a random install code, not your name.
- **Same advice as the web.** "Wait if you can" on many routes is the advisor's behaviour with thin evidence (KNOWN_FLAWS F-34), not a phone bug.
- **The language-model explanation tiers have never run.** If the app crashes when you open an explanation, note exactly what you tapped.
- **Not a safety tool.** It shows relative risk and its age, never that a road is safe or passable.

## After the test

Send the filled table. The numbers go into `data/results/` as a dated phone-test result and update PROJECT_STATUS, and any bug becomes a KNOWN_FLAWS entry, as for the web app.
