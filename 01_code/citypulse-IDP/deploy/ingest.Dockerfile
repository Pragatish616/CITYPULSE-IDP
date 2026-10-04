# Ingest server (FastAPI). Build from the repository root:
#   docker build -f deploy/ingest.Dockerfile -t citypulse-ingest .
# UNTESTED: written 2026-10-03 on a machine without Docker.
FROM python:3.12-slim
WORKDIR /srv
COPY server/requirements.txt /tmp/requirements.txt
RUN grep -vE '^(pytest|respx|ruff|black)' /tmp/requirements.txt > /tmp/run.txt \
    && pip install --no-cache-dir -r /tmp/run.txt && useradd --system --uid 10001 app
COPY server/app ./app
USER app
ENV CORS_ALLOWED_ORIGINS=""
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers"]
