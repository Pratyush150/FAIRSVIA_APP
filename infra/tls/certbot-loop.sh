#!/bin/sh
# certbot service entrypoint.
#  1. First boot with no certificate: write a short-lived self-signed
#     placeholder so nginx can start and serve the ACME challenge that gets
#     the real one. Apps will (correctly) reject it until then.
#  2. Forever: `certbot renew` twice a day. A no-op until issue-cert.sh has
#     obtained a real certificate; afterwards it renews ~30 days before expiry
#     and the deploy hook hands the new files to nginx.
set -eu
DOMAIN="${TLS_DOMAIN:-localhost}"

if [ ! -s /certs/fullchain.pem ]; then
  openssl req -x509 -nodes -newkey rsa:2048 -days 30 \
    -subj "/CN=$DOMAIN" -addext "subjectAltName=DNS:$DOMAIN" \
    -keyout /certs/privkey.pem -out /certs/fullchain.pem 2>/dev/null
  touch /certs/.placeholder
  echo "wrote self-signed placeholder for $DOMAIN — run infra/tls/issue-cert.sh for a real certificate"
fi

while true; do
  certbot renew --quiet --webroot -w /var/www/certbot \
    --deploy-hook /scripts/deploy-hook.sh || echo "certbot renew failed" >&2
  sleep 12h
done
