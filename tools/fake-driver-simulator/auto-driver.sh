#!/usr/bin/env bash
# Fully automatic driver side for filming the rider journey.
# Waits for the rider (on the phone) to book, then: accepts -> approaches ->
# arrives -> reads the start OTP server-side -> starts -> completes.
# The rider just books and watches, then rates/tips at the end.
set -u
cd "$(dirname "$0")"
LOG="${1:-/tmp/auto_driver.log}"
: > "$LOG"

echo "waiting for the rider to book..." >> "$LOG"
node demo-driver-stages.mjs accept >> "$LOG" 2>&1

TRIP=$(grep -oE 'ARRIVED tripId=[0-9a-f-]+' "$LOG" | tail -1 | cut -d= -f2)
if [ -z "$TRIP" ]; then
  echo "no trip accepted (offer never arrived?)" >> "$LOG"
  exit 1
fi
echo "arrived on trip $TRIP — pausing so the rider sees 'driver arrived'" >> "$LOG"
sleep 4

OTP=$(docker exec ubernav_postgres psql -U ubernav -d ubernav -tAc \
  "SELECT start_otp FROM trips WHERE id='$TRIP';" 2>/dev/null | tr -d '[:space:]')
echo "start code = $OTP" >> "$LOG"

node demo-driver-stages.mjs finish "$TRIP" "$OTP" >> "$LOG" 2>&1
echo "DONE" >> "$LOG"
