#!/bin/zsh
# Short realistic ride (~55 m approach, ~110 m trip) recorded from both sims.
# Every step waits for the real state: Arrived only when the car is on the pin,
# start code typed digit by digit, Complete only when the car reaches the dropoff.
set -u
S=/private/tmp/claude-501/-Users-parthbhimani-ubernav/ab85084e-673f-4bf1-9727-49245d8302fa/scratchpad
R=0C719B75-F2EB-4F52-BEC5-285CE1CC8959   # iPhone 17 (rider)
D=17F881CA-34B0-4F74-83E9-7EB9A61AD130   # iPhone 16 Pro (driver)
RIDER_ID=7f962e3a-8f0e-411e-8e67-4e928353382a
DRIVER_ID=5a7e58af-625e-4c88-a299-8706f060e785
DRAG_PT="${DRAG_PT:-52}"   # points to drag the picker map up (~110 m south)
tap(){ idb ui tap --udid $1 $2 $3 --duration 0.05 >/dev/null 2>&1; }
typ(){ idb ui text --udid $1 "$2" >/dev/null 2>&1; }
log(){ echo "[$(date +%H:%M:%S) +$(( $(date +%s) - T0 ))s] $*"; }
sql(){ PGPASSWORD=fairsvia psql -h localhost -U fairsvia -d fairsvia -At -c "$1"; }
dist_to(){ python3 - "$1" "$2" "$DRIVER_ID" <<'PY'
import sys, math, subprocess
lat2, lng2, did = float(sys.argv[1]), float(sys.argv[2]), sys.argv[3]
g = lambda f: subprocess.run(['redis-cli','hget',f'driver:{did}:loc',f],capture_output=True,text=True).stdout.strip()
try: lat1, lng1 = float(g('lat')), float(g('lng'))
except ValueError: print(99999); sys.exit()
r=6371000; p1,p2=math.radians(lat1),math.radians(lat2); dp=p2-p1; dl=math.radians(lng2-lng1)
h=math.sin(dp/2)**2+math.cos(p1)*math.cos(p2)*math.sin(dl/2)**2
print(int(2*r*math.asin(math.sqrt(h))))
PY
}
wait_near(){ local i=0 d=99999; while [ $i -lt $4 ]; do d=$(dist_to $1 $2); [ "$d" -le $3 ] && { log "car within ${d} m"; return 0; }; sleep 1; i=$((i+1)); done; log "timeout, still ${d} m away"; }

xcrun simctl io $R recordVideo --codec h264 --force $S/short_rider.mp4 & VR=$!
xcrun simctl io $D recordVideo --codec h264 --force $S/short_driver.mp4 & VD=$!
sleep 2; T0=$(date +%s)

log "driver: go online";                 tap $D 201 792; sleep 4
log "rider: open search";                tap $R 201 791; sleep 3
log "rider: set destination on the map"; tap $R 201 256; sleep 5
log "rider: drag map ~110 m south";      idb ui swipe --udid $R 201 500 201 $((500 - DRAG_PT)) --duration 0.5 >/dev/null 2>&1; sleep 4
log "rider: confirm location";           tap $R 201 780; sleep 7
log "rider: confirm ride (Economy)";     tap $R 201 744; sleep 6
log "driver: accept offer";              tap $D 280 578; sleep 3
TRIP=$(sql "select id from trips where rider_id='$RIDER_ID' order by requested_at desc limit 1")
read PLAT PLNG DLAT DLNG <<< "$(sql "select pickup_lat, pickup_lng, dropoff_lat, dropoff_lng from trips where id='$TRIP'" | tr '|' ' ')"
log "trip $TRIP pickup=$PLAT,$PLNG dropoff=$DLAT,$DLNG"
log "driver: driving to pickup…";        wait_near $PLAT $PLNG 8 60; sleep 3
log "driver: arrived";                   tap $D 201 792; sleep 5
OTP=$(sql "select start_otp from trips where id='$TRIP'")
log "driver: start code $OTP";           tap $D 105 714; sleep 1; for c in $(echo $OTP | sed 's/./& /g'); do typ $D "$c"; sleep 1; done; sleep 2
log "driver: start trip";                tap $D 201 792; sleep 4
log "driver: driving to dropoff…";       wait_near $DLAT $DLNG 8 90; sleep 3
log "driver: complete trip";             tap $D 201 792; sleep 6
log "rider: rate 5, tip \$2";            tap $R 296 549; sleep 1; tap $R 61 715; sleep 3
log "driver: rate rider 5";              tap $D 297 724; sleep 2
log "both: done";                        tap $R 201 792; sleep 1; tap $D 201 792; sleep 3
log "trip status: $(sql "select status||' fare='||coalesce(fare_final::text,'')||' dist='||coalesce(distance_m::text,'') from trips where id='$TRIP'" 2>/dev/null || sql "select status from trips where id='$TRIP'")"
kill -INT $VR $VD; wait $VR $VD 2>/dev/null
log "recordings stopped"
