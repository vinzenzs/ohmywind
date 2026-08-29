# syntax=docker/dockerfile:1.7
#
# Generic OCI image of the OhMyWind MCP server: the same Starlette wrapper the
# Hugging Face Space runs, built from the monorepo instead of vendored copies.
# This is the "different wrapper" the cloud-agnostic rule in CLAUDE.md talks
# about — nothing here is Kubernetes-specific, it only has to be runnable by
# any container runtime (Helm chart in deploy/helm/, docker run, Fly, ...).
#
# Build from the repository root:
#   docker build -f deploy/docker/Dockerfile -t ohmywind-mcp .
#
# The tidal atlas dataset is NOT baked in (it is private and the HF token
# would have to be threaded through the build). Mount it at /data/atlas
# instead; without it the server degrades to Open-Meteo SMOC currents only.

ARG PYTHON_VERSION=3.12

# ---------------------------------------------------------------- builder
FROM python:${PYTHON_VERSION}-slim AS builder

COPY --from=ghcr.io/astral-sh/uv:0.8 /uv /bin/uv

ENV UV_LINK_MODE=copy \
    UV_COMPILE_BYTECODE=1 \
    UV_PYTHON_DOWNLOADS=never

WORKDIR /src
COPY packages/data-adapters ./data-adapters
COPY packages/mcp-core ./mcp-core

# One flat venv, then copied wholesale into the runtime stage. The third-party
# set mirrors packages/hf-space/pyproject.toml minus huggingface_hub, which
# only the Space's build-time atlas fetch needs.
#
# --no-sources: mcp-core's [tool.uv.sources] declares openwind-data as an
# *editable* path dependency for local development. Honouring it here writes
# a .pth pointing at /src, which does not exist in the runtime stage, and the
# server dies at import time. Both packages are given explicitly instead.
RUN uv venv /opt/venv \
 && uv pip install --python /opt/venv/bin/python --no-sources \
      ./data-adapters ./mcp-core \
      "starlette>=0.37" "uvicorn[standard]>=0.30" "httpx>=0.27"

# ---------------------------------------------------------------- runtime
FROM python:${PYTHON_VERSION}-slim

ARG VERSION=dev
ARG VCS_REF=unknown
LABEL org.opencontainers.image.title="ohmywind-mcp" \
      org.opencontainers.image.description="OhMyWind MCP server + REST API (sailing passage planner)" \
      org.opencontainers.image.source="https://github.com/qdonnars/ohmywind" \
      org.opencontainers.image.url="https://ohmywind.fr" \
      org.opencontainers.image.licenses="AGPL-3.0-or-later" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}"

ENV PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH" \
    # Same directory for both registries: the dataset layout puts the SHOM
    # artefacts at the root next to the per-atlas MARC subdirectories.
    ATLAS_DATA_DIR=/data/atlas \
    MARC_ATLAS_DIR=/data/atlas \
    SHOM_C2D_DIR=/data/atlas \
    # Outside HF nothing legitimately frames the landing page.
    OPENWIND_FRAME_ANCESTORS="'none'"

# curl is only here for the HEALTHCHECK / a shell in a pod; a distroless
# variant is a later optimisation once the image is in real use.
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl \
 && rm -rf /var/lib/apt/lists/* \
 && groupadd --system --gid 10001 app \
 && useradd --system --uid 10001 --gid app --home-dir /app --no-create-home app \
 && mkdir -p /app /data/atlas \
 && chown -R app:app /app /data

COPY --from=builder /opt/venv /opt/venv
# security.py is imported by app.py at boot: a missing COPY is a crash, not a
# degraded mode. static/ carries the landing page's demo assets.
COPY --chown=app:app packages/hf-space/app.py packages/hf-space/security.py /app/
COPY --chown=app:app packages/hf-space/static /app/static

WORKDIR /app
USER app
EXPOSE 7860

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl -fsS http://127.0.0.1:7860/healthz || exit 1

CMD ["python", "/app/app.py"]
