# Security policy

## Supported versions

CityPulse is a research prototype. Only the `main` branch is maintained. There are no released, supported
versions and nothing here should be deployed to the public without reading [`docs/DEPLOY.md`](01_code/citypulse-IDP/docs/DEPLOY.md).

## Reporting a vulnerability

Please **do not open a public issue** for a security problem. Use GitHub's private reporting:
**Security → Report a vulnerability** on this repository. Include what you found, how to reproduce it and
what you think the impact is. We aim to acknowledge a report within a few days; this is a student project,
so please be patient.

## Things worth knowing

- **API keys:** never commit one. `.env` is ignored; copy `.env.example`. The Groq key for the optional cloud
  rewriter is read by the server only (`POST /rewrite`); it must never be placed in the app, where it would
  ship in the APK or the web bundle.
- **Admin endpoint:** `PUT /event-state` is disabled unless `ADMIN_TOKEN` is set. Use a long random value.
- **Reverse proxy:** set `TRUST_FORWARDED_FOR=1` only behind a proxy that sets `X-Forwarded-For`.
- **Privacy:** request bodies carry coordinates and are never logged; the access log records method, path and
  status only. The project makes no passive location inference (DPDP Act 2023).
- **Reports are unauthenticated and in memory** in the current ingest server. Treat it as a demo until the
  database settings in `01_code/citypulse-IDP/server/README.md` are in place.
