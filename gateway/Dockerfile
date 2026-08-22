# DeerFlow Gateway for Railway.
#
# Upstream publishes the Gateway image but its docker-compose mounts three
# things into it at run time: config.yaml, extensions_config.json and the
# bundled skills/ directory. Railway has no bind mounts, so this one-layer
# image bakes them in and adds an entrypoint that binds $PORT and seeds the
# first admin account.
#
# Built from the repo root, so every COPY path is prefixed with gateway/.

ARG DEERFLOW_IMAGE=ghcr.io/bytedance/deer-flow-backend:latest
FROM ${DEERFLOW_IMAGE}

# Skills are content, not code: they ship in the git repo rather than the
# image, so they have to be fetched separately. Keep this on the tag the
# published image was built from (`latest` == v2.0.0) and bump both together.
ARG DEERFLOW_SKILLS_REF=v2.0.0

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl tini; \
    rm -rf /var/lib/apt/lists/*; \
    curl -fsSL "https://codeload.github.com/bytedance/deer-flow/tar.gz/refs/tags/${DEERFLOW_SKILLS_REF}" \
      | tar -xz -C /tmp; \
    mkdir -p /app/skills; \
    cp -a "/tmp/deer-flow-${DEERFLOW_SKILLS_REF#v}/skills/." /app/skills/; \
    rm -rf /tmp/deer-flow-*; \
    ls -A /app/skills

# Upstream's extensions file is an empty object unless the operator adds MCP
# extensions; ship the empty default so the Gateway never reads a missing path.
RUN printf '{}\n' > /app/backend/extensions_config.json

COPY gateway/config.yaml       /app/backend/config.yaml
COPY gateway/seed_admin.py     /usr/local/bin/deerflow-seed-admin.py
COPY gateway/entrypoint.sh     /usr/local/bin/deerflow-entrypoint.sh
RUN chmod 0755 /usr/local/bin/deerflow-entrypoint.sh

ENV DEER_FLOW_PROJECT_ROOT=/app \
    DEER_FLOW_HOME=/app/backend/.deer-flow \
    DEER_FLOW_CONFIG_PATH=/app/backend/config.yaml \
    DEER_FLOW_EXTENSIONS_CONFIG_PATH=/app/backend/extensions_config.json \
    DEER_FLOW_SKILLS_PATH=/app/skills \
    PYTHONUNBUFFERED=1

EXPOSE 8001

# tini -s so SIGTERM reaches uvicorn and the seeder subshell is reaped; a start
# command would run as a child of Railway's runtime, never as PID 1.
ENTRYPOINT ["/usr/bin/tini", "-s", "--"]
CMD ["/usr/local/bin/deerflow-entrypoint.sh"]
