#!/bin/sh
# DeerFlow Gateway entrypoint.
set -eu

: "${PORT:=8001}"
: "${GATEWAY_WORKERS:=1}"
export PORT

# The Gateway owns run state in process, so upstream ships production at one
# worker. The Redis stream bridge that would allow more raises
# NotImplementedError in this release -- do not raise this without checking.
if [ "$GATEWAY_WORKERS" != "1" ]; then
  echo "[deerflow] WARNING: GATEWAY_WORKERS=$GATEWAY_WORKERS; run state is worker-local in this release."
fi

mkdir -p "${DEER_FLOW_HOME:-/app/backend/.deer-flow}"

# Seed the first admin so the deployment is never reachable with an open
# /setup page. Runs behind the exec: it waits for the server it is seeding,
# and POSTs to the app's own API rather than writing the users table itself.
# /api/v1/auth/initialize answers 409 once an admin exists, so this is
# idempotent across redeploys.
if [ -n "${DEERFLOW_ADMIN_EMAIL:-}" ] && [ -n "${DEERFLOW_ADMIN_PASSWORD:-}" ]; then
  python3 /usr/local/bin/deerflow-seed-admin.py &
else
  echo "[deerflow] DEERFLOW_ADMIN_EMAIL/DEERFLOW_ADMIN_PASSWORD unset - complete /setup in the browser immediately."
fi

cd /app/backend
echo "[deerflow] starting Gateway on 0.0.0.0:${PORT} (workers=${GATEWAY_WORKERS})"
exec uv run --no-sync uvicorn app.gateway.app:app \
  --host 0.0.0.0 --port "$PORT" --workers "$GATEWAY_WORKERS"
