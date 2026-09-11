#!/bin/zsh
# Fully automated iOS rider+driver ride, recorded from both simulators.
set -u
S=/private/tmp/claude-501/-Users-parthbhimani-ubernav/ab85084e-673f-4bf1-9727-49245d8302fa/scratchpad
R=0C719B75-F2EB-4F52-BEC5-285CE1CC8959   # iPhone 17 (rider)
D=17F881CA-34B0-4F74-83E9-7EB9A61AD130   # iPhone 16 Pro (driver)
RIDER_ID=7f962e3a-8f0e-411e-8e67-4e928353382a
tap(){ idb ui tap --udid $1 $2 $3 --duration 0.05 >/dev/null 2>&1; }
typ(){ idb ui text --udid $1 "$2" >/dev/null 2>&1; }
log(){ echo "[$(date +%H:%M:%S)] $*"; }

xcrun simctl io $R recordVideo --codec h264 --force $S/video_rider.mp4 & VR=$!
xcrun simctl io $D recordVideo --codec h264 --force $S/video_driver.mp4 & VD=$!
sleep 2; T0=$(date +%s)

log "driver: go online";            tap $D 201 792; sleep 3
log "rider: open search";           tap $R 201 791; sleep 2
log "rider: type destination";      typ $R "airport"; sleep 3
log "rider: pick 'airport Park'";   tap $R 200 520; sleep 6
log "rider: scroll sheet";          idb ui swipe --udid $R 201 650 201 250 --duration 0.4 >/dev/null 2>&1; sleep 1.5
log "rider: choose Cash";           tap $R 306 576; sleep 1
log "rider: confirm ride";          tap $R 201 744; sleep 6
log "driver: accept offer";         tap $D 280 578; sleep 6
log "rider: open chat";             tap $R 108 791; sleep 2; tap $R 170 804; sleep 0.8
typ $R "Hi! I am by the cafe entrance"; sleep 0.5; tap $R 370 804; sleep 3
log "driver: open chat, reply";     tap $D 358 703; sleep 2; tap $D 170 804; sleep 0.8
typ $D "On my way, 2 min"; sleep 0.5; tap $D 370 804; sleep 3
log "both: back to trip";           tap $D 27 91; sleep 1; tap $R 27 91; sleep 1.5
log "driver: arrived";              tap $D 201 792; sleep 4
OTP=$(PGPASSWORD=ubernav psql -h localhost -U ubernav -d ubernav -At -c "select start_otp from trips where rider_id='$RIDER_ID' order by requested_at desc limit 1")
log "driver: start code $OTP";      tap $D 105 714; sleep 0.6; for c in $(echo $OTP | sed 's/./& /g'); do typ $D "$c"; sleep 0.7; done; sleep 1
tap $D 201 792; sleep 5
log "driver: complete trip";        tap $D 201 792; sleep 6
log "rider: rate 5, tip \$2";       tap $R 296 549; sleep 0.8; tap $R 61 715; sleep 2
log "driver: rate rider";           tap $D 297 724; sleep 1
log "both: done";                   tap $R 201 792; sleep 1; tap $D 201 792; sleep 3
log "elapsed $(( $(date +%s) - T0 ))s"
kill -INT $VR $VD; wait $VR $VD 2>/dev/null
log "recordings stopped"
