#!/bin/sh
# Obtain a real Let's Encrypt certificate for the production API hostname.
#
#   infra/tls/issue-cert.sh <domain> <contact-email> [--staging]
#
# Preconditions — Let's Encrypt checks these from the public internet:
#   - <domain> has an A record pointing at this server's public IP. On
#     Cloudflare it must be "DNS only" (grey cloud) for issuance.
#   - Ports 80 and 443 reach nginx (HTTP_PORT=80 HTTPS_PORT=443 in infra/.env).
#   - The prod stack is running with TLS_DOMAIN=<domain>.
# Use --staging first: it has generous rate limits and proves the path.
set -eu
DOMAIN="${1:?usage: issue-cert.sh <domain> <email> [--staging]}"
EMAIL="${2:?usage: issue-cert.sh <domain> <email> [--staging]}"
STAGING=""
[ "${3:-}" = "--staging" ] && STAGING="--staging"

COMPOSE="docker compose -p ubernav_prod -f $(dirname "$0")/../docker-compose.prod.yml"

$COMPOSE exec certbot certbot certonly $STAGING --non-interactive --agree-tos \
  --email "$EMAIL" --webroot -w /var/www/certbot -d "$DOMAIN" \
  --deploy-hook /scripts/deploy-hook.sh
$COMPOSE exec nginx nginx -c /etc/nginx/ridevela/nginx.conf -s reload
echo "done — verify: curl -sI https://$DOMAIN/api/v1/health"
