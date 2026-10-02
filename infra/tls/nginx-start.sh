#!/bin/sh
# nginx entrypoint: wait for a certificate (the certbot service writes a
# placeholder on first boot), then run nginx, reloading every 6h so renewed
# certificates are picked up without a restart.
set -eu
CONF=/etc/nginx/fairsvia/nginx.conf
i=0
until [ -s /etc/nginx/certs/fullchain.pem ] && [ -s /etc/nginx/certs/privkey.pem ]; do
  i=$((i + 1))
  [ "$i" -gt 60 ] && { echo "no TLS certificate after 60s — is the certbot service running?" >&2; exit 1; }
  sleep 1
done
(while true; do sleep 6h; nginx -c "$CONF" -s reload; done) &
exec nginx -c "$CONF" -g 'daemon off;'
