# One container: the web app, the router API, the report server and Caddy (the front door).
#
# Build from the repository root (01_code/citypulse-IDP):
#   docker build -f deploy/single/Dockerfile -t citypulse .
#   docker run --rm -p 8080:8080 -e ADMIN_TOKEN=change-me citypulse      # then open http://localhost:8080
#
# Why one container: most free hosts run a single web service, and the app is built to be served from ONE
# origin (/ web app, /api router, /ingest reports) so the browser makes no cross-origin calls and CORS stays off.
#
# STATUS: UNTESTED AS AN IMAGE. The authoring machine has no Docker. What was tested instead is every part on its
# own: the router executable, the report server and the web build run together behind a stand-in proxy (see
# docs/DEPLOY.md). Expect small fixes on the first builds (Render's first real builds, 4 Oct 2026, found two; see KNOWN_FLAWS F-35).
#
# Build arguments:
#   FLUTTER_VERSION  the Flutter release to install in the web stage. The app needs Dart >= 3.13.2 and was built and
#                    tested with Flutter 3.47.2. (The cirruslabs `stable` image shipped Dart 3.12.0 and failed pub get.)
#   DART_IMAGE       image with Dart (>= 3.13) for the router.
#   PACK_DATE        folder under data/packs/ named by `pack:` in config/cities.yaml (default Chennai pack).
ARG DART_IMAGE=dart:stable

# ---- 1. web app -------------------------------------------------------------------------------------------
# Flutter is installed from its Git tag so the version is exactly the one named, not whatever an image tag points to.
FROM debian:stable-slim AS web
ARG FLUTTER_VERSION=3.47.2
ARG PACK_DATE=2026-10-02
RUN apt-get update \
    && apt-get install -y --no-install-recommends git curl unzip xz-utils zip ca-certificates libglu1-mesa \
        python3 python3-yaml python-is-python3 \
    && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch ${FLUTTER_VERSION} https://github.com/flutter/flutter.git /opt/flutter
ENV PATH=/opt/flutter/bin:$PATH
# Some build sandboxes (Render's, for one) refuse to set file owners, and Flutter unpacks its archives with tar, which tries to
# keep the owner recorded in the archive ("Cannot change ownership ... Invalid argument"). GNU tar reads this variable.
ENV TAR_OPTIONS=--no-same-owner
# Downloads the Dart SDK and the web engine now, so the build step below only compiles.
RUN flutter --version && flutter precache --web
WORKDIR /src
COPY packages ./packages
COPY app ./app
COPY config ./config
COPY data/packs/${PACK_DATE} ./data/packs/${PACK_DATE}
COPY data/watchlist ./data/watchlist
WORKDIR /src/app
# sync_data_assets.sh copies the pack, configs and the reduced watchlist into app/assets (they are not in git).
RUN bash scripts/sync_data_assets.sh \
    && flutter pub get \
    && flutter build web --release --no-web-resources-cdn \
        --dart-define=ROUTER_API_URL=/api \
        --dart-define=INGEST_URL=/ingest

# ---- 2. router API ----------------------------------------------------------------------------------------
FROM ${DART_IMAGE} AS router
WORKDIR /src
COPY packages ./packages
COPY services/router_api ./services/router_api
WORKDIR /src/services/router_api
# dart compile does not create the output folder.
RUN mkdir -p /out && dart pub get && dart compile exe bin/server.dart -o /out/router_api

# ---- 3. runtime -------------------------------------------------------------------------------------------
# Same Debian line as the dart:stable build stage, so the compiled router finds the C library it was linked against
# (python:3.12-slim can sit on a different Debian release). Python comes from Debian, in a virtual environment.
FROM debian:stable-slim
ARG PACK_DATE=2026-10-02
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates bash python3 python3-venv \
    && rm -rf /var/lib/apt/lists/* \
    && python3 -m venv /opt/venv \
    && useradd --system --uid 10001 --create-home app
ENV PATH=/opt/venv/bin:$PATH
COPY --from=caddy:2 /usr/bin/caddy /usr/local/bin/caddy
# The official image gives the binary a file capability (to bind ports below 1024) and COPY keeps it. A non-root user in a
# sandbox without that capability then cannot start it ("Operation not permitted"). We listen on a high port, so rewrite the
# file as plain bytes, which drops the capability.
RUN cat /usr/local/bin/caddy > /tmp/caddy && rm /usr/local/bin/caddy \
    && install -m 0755 /tmp/caddy /usr/local/bin/caddy && rm /tmp/caddy

# Report server (FastAPI). Test-only packages are left out of the install.
COPY server/requirements.txt /tmp/requirements.txt
RUN grep -vE '^(pytest|respx|ruff|black)' /tmp/requirements.txt > /tmp/run.txt \
    && pip install --no-cache-dir -r /tmp/run.txt
COPY server/app /srv/server/app
# The report server reads config/hazard_classes.yaml relative to its own folder (/srv is its "repository root").
COPY config/hazard_classes.yaml /srv/config/hazard_classes.yaml

# Router API. Laid out like the repository so config/cities.yaml's relative paths (pack, places) resolve:
# /app is the "repository root" and CITIES_CONFIG points into it.
COPY --from=router /out/router_api /app/router_api
COPY config/cities.yaml config/hazard_classes.yaml /app/config/
COPY data/packs/${PACK_DATE} /app/data/packs/${PACK_DATE}
COPY data/places /app/data/places

# Web app and the front door.
COPY --from=web /src/app/build/web /srv/web
COPY deploy/single/Caddyfile /etc/caddy/Caddyfile
COPY deploy/single/start.sh /app/start.sh
# Belt and braces: strip any Windows line endings the checkout may have added.
RUN sed -i 's/\r$//' /app/start.sh /etc/caddy/Caddyfile && chmod +x /app/start.sh

USER app
ENV CITIES_CONFIG=/app/config/cities.yaml \
    HAZARD_CONFIG=/app/config/hazard_classes.yaml \
    OBSERVATIONS_URL=http://127.0.0.1:8000 \
    TRUST_FORWARDED_FOR=1 \
    CORS_ALLOWED_ORIGINS="" \
    EVENT_STATE=active \
    XDG_CONFIG_HOME=/tmp/caddy \
    XDG_DATA_HOME=/tmp/caddy \
    PORT=8080
# Secrets come from the host's environment settings, never from the image:
#   ADMIN_TOKEN (enables PUT /api/event-state), GROQ_API_KEY (optional, enables POST /api/rewrite).
EXPOSE 8080
CMD ["/app/start.sh"]
