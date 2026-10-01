#!/bin/zsh
# Realistic automated iOS ride: the simulated car visibly drives the approach
# leg and the trip leg; each step fires when the car actually gets there.
set -u
S=/private/tmp/claude-501/-Users-parthbhimani-ubernav/ab85084e-673f-4bf1-9727-49245d8302fa/scratchpad
R=0C719B75-F2EB-4F52-BEC5-285CE1CC8959   # iPhone 17 (rider)
D=17F881CA-34B0-4F74-83E9-7EB9A61AD130   # iPhone 16 Pro (driver)
RIDER_ID=7f962e3a-8f0e-411e-8e67-4e928353382a
DRIVER_ID=5a7e58af-625e-4c88-a299-8706f060e785
DEST="${DEST:-Miami Dade College Wolfson Campus}"
tap(){ idb ui tap --udid $1 $2 $3 --duration 0.05 >/dev/null 2>&1; }
typ(){ idb ui text --udid $1 "$2" >/dev/null 2>&1; }
log(){ echo "[$(date +%H:%M:%S) +$(( $(date +%s) - T0 ))s] $*"; }
sql(){ PGPASSWORD=fairsvia psql -h localhost -U fairsvia -d fairsvia -At -c "$1"; }
# metres from the driver's live Redis position to (lat,lng)
dist_to(){ python3 - "$1" "$2" <<'PY'
import sys, math, subprocess
lat2, lng2 = float(sys.argv[1]), float(sys.argv[2])
g = lambda f: subprocess.run(['redis-cli','hget','driver:5a7e58af-625e-4c88-a299-8706f060e785:loc',f],capture_output=True,text=True).stdout.strip()
try:
    lat1, lng1 = float(g('lat')), float(g('lng'))
except ValueError:
    print(99999); sys.exit()
r=6371000; p1,p2=math.radians(lat1),math.radians(lat2); dp=p2-p1; dl=math.radians(lng2-lng1)
h=math.sin(dp/2)**2+math.cos(p1)*math.cos(p2)*math.sin(dl/2)**2
print(int(2*r*math.asin(math.sqrt(h))))
PY
}
# wait until the car is within 30 m of (lat,lng), max $3 seconds
wait_near(){ local i=0; while [ $i -lt $3 ]; do d=$(dist_to $1 $2); [ "$d" -le 30 ] && { log "car within ${d} m"; return 0; }; sleep 2; i=$((i+2)); done; log "timeout, still ${d} m away"; }

xcrun simctl io $R recordVideo --codec h264 --force $S/real_rider.mp4 & VR=$!
xcrun simctl io $D recordVideo --codec h264 --force $S/real_driver.mp4 & VD=$!
sleep 2; T0=$(date +%s)

log "driver: go online";              tap $D 201 792; sleep 3
log "rider: search '$DEST'";          tap $R 201 791; sleep 2.5; typ $R "$DEST"; sleep 4
log "rider: pick first result";       tap $R 200 325; sleep 6
log "rider: confirm (Economy, card)"; tap $R 201 744; sleep 5
log "driver: accept offer";           tap $D 280 578; sleep 4
TRIP=$(sql "select id from trips where rider_id='$RIDER_ID' order by requested_at desc limit 1")
read PLAT PLNG DLAT DLNG <<< "$(sql "select pickup_lat, pickup_lng, dropoff_lat, dropoff_lng from trips where id='$TRIP'" | tr '|' ' ')"
log "trip $TRIP pickup=$PLAT,$PLNG dropoff=$DLAT,$DLNG"
log "driver: driving to pickup…";     wait_near $PLAT $PLNG 70
log "driver: arrived";                tap $D 201 792; sleep 4
OTP=$(sql "select start_otp from trips where id='$TRIP'")
log "driver: start code $OTP";        tap $D 105 714; sleep 0.6; for c in $(echo $OTP | sed 's/./& /g'); do typ $D "$c"; sleep 0.6; done; sleep 1; tap $D 201 792; sleep 4
log "driver: driving to dropoff…";    wait_near $DLAT $DLNG 75
log "driver: complete trip";          tap $D 201 792; sleep 6
log "rider: rate 5, tip \$2";         tap $R 296 549; sleep 0.8; tap $R 61 715; sleep 2
log "driver: rate rider";             tap $D 297 724; sleep 1
log "both: done";                     tap $R 201 792; sleep 1; tap $D 201 792; sleep 3
log "trip status: $(sql "select status||' fare='||coalesce(fare_final::text,'') from trips where id='$TRIP'")"
kill -INT $VR $VD; wait $VR $VD 2>/dev/null
log "recordings stopped"
