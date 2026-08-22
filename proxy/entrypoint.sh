#!/bin/sh
# Render the DeerFlow edge config and start nginx.
set -eu

: "${PORT:=2026}"

# A ${{svc.RAILWAY_PRIVATE_DOMAIN}} reference renders as an empty string until
# that service owns a deployment, which would bake "http://:8001" as the
# upstream. Fall back on the value's *shape*, not on the variable being unset.
case "${GATEWAY_UPSTREAM:-}" in
  ""|":"*) GATEWAY_UPSTREAM="gateway.railway.internal:8001" ;;
esac
case "${FRONTEND_UPSTREAM:-}" in
  ""|":"*) FRONTEND_UPSTREAM="frontend.railway.internal:3000" ;;
esac

# nginx needs an explicit resolver to re-resolve upstreams per request, and
# Railway's is IPv6 (fd12::10), which nginx only accepts bracketed.
NGINX_RESOLVER="$(
  awk '/^nameserver/ { print $2 }' /etc/resolv.conf \
  | while read -r ns; do
      case "$ns" in
        *:*) printf '[%s] ' "$ns" ;;
        *)   printf '%s ' "$ns" ;;
      esac
    done
)"
NGINX_RESOLVER="$(printf '%s' "$NGINX_RESOLVER" | sed 's/ *$//')"
[ -n "$NGINX_RESOLVER" ] || NGINX_RESOLVER="[fd12::10]"

# DeerFlow 2.0.0 exposes POST /api/v1/auth/register with no server-side switch,
# so an open public instance lets anyone self-register and spend the deployer's
# model credits. Closed unless the operator opts in.
if [ "${DEERFLOW_ALLOW_REGISTRATION:-false}" = "true" ]; then
  REGISTRATION_BLOCK="# self-registration enabled by DEERFLOW_ALLOW_REGISTRATION"
else
  REGISTRATION_BLOCK='location = /api/v1/auth/register { return 403 "Self-registration is disabled."; }'
fi

export PORT GATEWAY_UPSTREAM FRONTEND_UPSTREAM NGINX_RESOLVER REGISTRATION_BLOCK

# Name every variable explicitly: a bare envsubst would eat nginx's own
# $http_host, $remote_addr and friends.
envsubst '${PORT} ${GATEWAY_UPSTREAM} ${FRONTEND_UPSTREAM} ${NGINX_RESOLVER} ${REGISTRATION_BLOCK}' \
  < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

echo "[deerflow-proxy] listening on ${PORT}; gateway=${GATEWAY_UPSTREAM} frontend=${FRONTEND_UPSTREAM} resolver=${NGINX_RESOLVER}"
nginx -t -c /etc/nginx/nginx.conf

exec nginx -c /etc/nginx/nginx.conf -g 'daemon off;'
