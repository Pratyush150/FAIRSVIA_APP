// A driver that accepts, reaches the pickup, starts the trip — and then
// CRAWLS toward the dropoff for as long as you ask, without completing.
//
// Why this exists: demo-live-ride.mjs finishes a whole ride in about 90
// seconds, which is far too short to drive a manual UI sequence on a device
// (pan the map, screenshot, tap Recenter, screenshot). Every attempt raced the
// trip's completion and landed the tap on the post-ride sheet instead.
//
// This keeps the rider app parked in `onTrip` with a live, moving car, so map
// and camera behaviour can be exercised by hand at a human pace.
//
//   node slow-ride.mjs [minutes]     (default 6)
//
// Ctrl-C when done; the trip is left in_progress and can be cleaned up with
//   docker exec ubernav_postgres psql -U ubernav -d ubernav \
//     -c "UPDATE trips SET status='cancelled' WHERE status='in_progress'"
import { execSync } from 'node:child_process';
import { api, connect, login, onboardDriver, phone, wait } from './lib.mjs';

const MINUTES = Number(process.argv[2] || 6);
// Hold the arriving screens long enough to work them by hand:
//   APPROACH_S=60 WAIT_AT_PICKUP_S=120 node slow-ride.mjs 6
const APPROACH_S = Number(process.env.APPROACH_S || 5.6);
const WAIT_AT_PICKUP_S = Number(process.env.WAIT_AT_PICKUP_S || 1.2);
// Where the driver waits. Defaults to Miami; for the Pune pilot:
//   START_LAT=18.5300 START_LNG=73.8475 node slow-ride.mjs
const START = {
  lat: Number(process.env.START_LAT ?? 25.766),
  lng: Number(process.env.START_LNG ?? -80.1955),
};

function readStartOtp(tripId) {
  return execSync(
    `docker exec ubernav_postgres psql -U ubernav -d ubernav -tAc ` +
      `"SELECT start_otp FROM trips WHERE id='${tripId}'"`,
  )
    .toString()
    .trim();
}

function bearing(a, b) {
  const dLng = ((b.lng - a.lng) * Math.PI) / 180;
  const y = Math.sin(dLng) * Math.cos((b.lat * Math.PI) / 180);
  const x =
    Math.cos((a.lat * Math.PI) / 180) * Math.sin((b.lat * Math.PI) / 180) -
    Math.sin((a.lat * Math.PI) / 180) *
      Math.cos((b.lat * Math.PI) / 180) *
      Math.cos(dLng);
  return ((Math.atan2(y, x) * 180) / Math.PI + 360) % 360;
}

/** Stream location from `from` → `to` in `steps` hops, `gap` ms apart. */
async function drive(sock, from, to, { steps = 12, gap = 800, label } = {}) {
  const hdg = Math.round(bearing(from, to));
  for (let i = 1; i <= steps; i++) {
    const t = i / steps;
    sock.emit('driver:location', {
      lat: from.lat + (to.lat - from.lat) * t,
      lng: from.lng + (to.lng - from.lng) * t,
      heading: hdg,
      speed: 9,
    });
    if (label && i % 4 === 0) {
      console.log(`  · ${label} ${Math.round(t * 100)}%`);
    }
    await wait(gap);
  }
}

const driverPhone = phone('90');
const driver = await login(driverPhone);
await onboardDriver(driver.token, 'economy');
const sock = await connect(driver.token);

sock.emit('driver:status', { status: 'online' });
await wait(400);
sock.emit('driver:location', { ...START, heading: 0, speed: 0 });
console.log(`🟢 ONLINE at ${START.lat},${START.lng}`);
console.log('   Book a ride from the phone now.\n');

const ping = setInterval(
  () => sock.emit('driver:location', { ...START, heading: 0, speed: 0 }),
  4000,
);

sock.on('trip:rider_coming', (e) => console.log(`🚶 RIDER IS ON THE WAY OUT (trip ${e.tripId})`));
sock.on('trip:stops_updated', (e) => console.log(`📍 RIDER ADDED A STOP — now ${e.stops.length} stop(s), fare ${e.fareEstimate}: ${e.stops.map((x) => x.addr).join(' → ')}`));

sock.on('trip:offer', async (offer) => {
  clearInterval(ping);
  console.log(`🚕 OFFER ${offer.tripId} — $${offer.fare}. Accepting…`);
  sock.emit('trip:accept', { tripId: offer.tripId });

  // The wait for an offer may have outlived the original token.
  const token = (await login(driverPhone)).token;
  const pickup = { lat: offer.pickup.lat, lng: offer.pickup.lng };
  const dropoff = { lat: offer.dropoff.lat, lng: offer.dropoff.lng };

  await wait(600);
  console.log('→ driving to pickup');
  const approachSteps = Math.max(8, Math.round(APPROACH_S / 0.7));
  await drive(sock, START, pickup, { steps: approachSteps, gap: 700, label: 'to pickup' });

  await api(`/trips/${offer.tripId}/arrived`, { method: 'POST', token });
  console.log(`📍 ARRIVED — waiting ${WAIT_AT_PICKUP_S}s at the pickup`);
  await wait(WAIT_AT_PICKUP_S * 1000);

  const otp = readStartOtp(offer.tripId);
  await api(`/trips/${offer.tripId}/start`, {
    method: 'POST',
    token,
    body: { otp },
  });
  console.log('▶️  TRIP STARTED');
  console.log(`\n🐌 Now crawling for ${MINUTES} min — drive the UI by hand.`);
  console.log('   The trip will NOT complete on its own.\n');

  // Cover only a fraction of the leg, spread over the whole window, so the car
  // is always genuinely moving (the camera only pans when it nears an edge)
  // but never arrives.
  const gap = 2000;
  const steps = Math.round((MINUTES * 60 * 1000) / gap);
  const near = {
    lat: pickup.lat + (dropoff.lat - pickup.lat) * 0.35,
    lng: pickup.lng + (dropoff.lng - pickup.lng) * 0.35,
  };
  await drive(sock, pickup, near, { steps, gap, label: 'crawling' });

  console.log('\n⏱  Window over. Trip left in_progress — Ctrl-C to exit.');
});
