# Router service. Build from the repository root (01_code/citypulse-IDP):
#   docker build -f deploy/router_api.Dockerfile -t citypulse-router .
# UNTESTED: written 2026-10-03 on a machine without Docker.
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
COPY data/packs/${PACK_DATE} /app/pack
COPY config/hazard_classes.yaml /app/hazard_classes.yaml
ENV PACK_DIR=/app/pack HAZARD_CONFIG=/app/hazard_classes.yaml PORT=8080
# Secrets come from the environment at run time, never from the image:
#   ADMIN_TOKEN, GROQ_API_KEY (optional), OBSERVATIONS_URL, ALLOWED_ORIGIN, TRUST_FORWARDED_FOR
USER app
EXPOSE 8080
CMD ["/app/router_api"]
