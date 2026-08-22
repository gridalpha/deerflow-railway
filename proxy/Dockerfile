# DeerFlow edge proxy: one public domain split between the Next.js frontend
# and the FastAPI Gateway, which Railway's host-only edge cannot do itself.
#
# Built from the repo root, so every COPY path is prefixed with proxy/.

FROM nginx:1.29-alpine

RUN apk add --no-cache gettext tini

COPY proxy/nginx.conf.template /etc/nginx/nginx.conf.template
COPY proxy/entrypoint.sh       /usr/local/bin/deerflow-proxy-entrypoint.sh
RUN chmod 0755 /usr/local/bin/deerflow-proxy-entrypoint.sh

ENV PORT=2026

EXPOSE 2026

ENTRYPOINT ["/sbin/tini", "-s", "--"]
CMD ["/usr/local/bin/deerflow-proxy-entrypoint.sh"]
