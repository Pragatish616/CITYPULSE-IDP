# Router service. Build from the repository root (01_code/citypulse-IDP):
#   docker build -f deploy/router_api.Dockerfile -t citypulse-router .
# UNTESTED: written 2026-10-03 on a machine without Docker. Fixed 2026-10-04: the server needs
# config/cities.yaml and the places file, which the first version did not copy (the container would not have started).
FROM dart:stable AS build
WORKDIR /src
COPY packages ./packages
COPY services/router_api ./services/router_api
WORKDIR /src/services/router_api
RUN dart pub get && dart compile exe bin/server.dart -o /out/router_api

FROM debian:stable-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/* && useradd --system --uid 10001 app
ARG PACK_DATE=2026-10-02
COPY --from=build /out/router_api /app/router_api
# Laid out like the repository so the relative paths in config/cities.yaml (pack, places) resolve:
# /app is the repository root, and the server finds the rest from CITIES_CONFIG.
COPY config/cities.yaml config/hazard_classes.yaml /app/config/
COPY data/packs/${PACK_DATE} /app/data/packs/${PACK_DATE}
COPY data/places /app/data/places
ENV CITIES_CONFIG=/app/config/cities.yaml HAZARD_CONFIG=/app/config/hazard_classes.yaml PORT=8080
# Secrets come from the environment at run time, never from the image:
#   ADMIN_TOKEN, GROQ_API_KEY (optional), OBSERVATIONS_URL, ALLOWED_ORIGIN, TRUST_FORWARDED_FOR
USER app
EXPOSE 8080
CMD ["/app/router_api"]
