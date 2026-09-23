#!/bin/sh
# certbot --deploy-hook: runs after a successful issue or renewal. Copies the
# live files (dereferencing certbot's symlinks, which don't survive the volume
# boundary) to where nginx reads them. nginx reloads on its own schedule.
set -eu
cp -L "$RENEWED_LINEAGE/fullchain.pem" /certs/fullchain.pem.new
cp -L "$RENEWED_LINEAGE/privkey.pem" /certs/privkey.pem.new
mv /certs/privkey.pem.new /certs/privkey.pem
mv /certs/fullchain.pem.new /certs/fullchain.pem
rm -f /certs/.placeholder
echo "installed certificate from $RENEWED_LINEAGE"
