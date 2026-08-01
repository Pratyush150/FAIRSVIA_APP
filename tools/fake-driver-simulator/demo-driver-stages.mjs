// Drives the DRIVER side of a ride at REALISTIC pace so the whole rider journey
// can be filmed on a real phone end-to-end — the car actually drives to the
// pickup, waits, then drives the trip, like Uber.
//
// Two stages, because the driver legitimately cannot see the rider's start OTP
// (the backend hides it) — the OTP is supplied out-of-band for the demo.
//
//   node demo-driver-stages.mjs accept
//       -> logs in a fixed demo driver, goes online ~1.5km from the pickup,
//          accepts the next offer, DRIVES to the pickup (visible movement),
//          marks Arrived, prints the tripId.
//
//   node demo-driver-stages.mjs finish <tripId> <otp>
//       -> starts the trip with the OTP, DRIVES to the dropoff, completes.
import { api, connect, login, once, onboardDriver, wait } from './lib.mjs';

const DEMO_DRIVER_PHONE = '+19800000077';

// Start well away from the pickup so the rider watches the car approach.
const START = { lat: 25.7885, lng: -80.1865 }; // ~1.6 km NE of downtown pickup

// Pacing (ms) — tuned so each phase is clearly visible on camera.
const APPROACH_MS = Number(process.env.APPROACH_MS ?? 26000);
const WAIT_AT_PICKUP_MS = Number(process.env.WAIT_AT_PICKUP_MS ?? 9000);
const TRIP_MS = Number(process.env.TRIP_MS ?? 26000);
const STEP_MS = 1300; // location ping interval

/** Emit location updates interpolating from -> to over durationMs. */
async function drive(sock, from, to, durationMs, label) {
  const steps = Math.max(4, Math.round(durationMs / STEP_MS));
  const heading =
    (Math.atan2(to.lng - from.lng, to.lat - from.lat) * 180) / Math.PI;
  for (let i = 1; i <= steps; i++) {
    const t = i / steps;
    sock.emit('driver:location', {
      lat: from.lat + (to.lat - from.lat) * t,
      lng: from.lng + (to.lng - from.lng) * t,
      heading: (heading + 360) % 360,
      speed: 11,
    });
    await wait(STEP_MS);
  }
  console.log(`${label} complete`);
}

async function accept() {
  const driver = await login(DEMO_DRIVER_PHONE);
  await onboardDriver(driver.token, 'economy');
  const sock = await connect(driver.token);
  sock.emit('driver:status', { status: 'online' });
  await wait(300);
  sock.emit('driver:location', { ...START, heading: 200, speed: 0 });
  console.log('driver online — waiting for a ride request…');

  // Real driver apps stream GPS continuously; keep pinging while we wait so the
  // driver's presence stays fresh (dispatch evicts drivers that go silent past
  // PRESENCE_STALE_MS). Without this a slow-to-book rider finds "no drivers".
  const heartbeat = setInterval(
    () => sock.emit('driver:location', { ...START, heading: 200, speed: 0 }),
    5000,
  );
  let offer;
  try {
    offer = await once(sock, 'trip:offer', 180000);
  } finally {
    clearInterval(heartbeat);
  }
  console.log(`offer received: ${offer.tripId} ($${offer.fare})`);
  // A beat before accepting, like a real driver reading the request.
  await wait(2500);
  sock.emit('trip:accept', { tripId: offer.tripId });
  console.log('accepted — driving to the pickup');
  await wait(1500);

  const pickup = { lat: offer.pickup.lat, lng: offer.pickup.lng };
  await drive(sock, START, pickup, APPROACH_MS, 'approach');

  await api(`/trips/${offer.tripId}/arrived`, {
    method: 'POST',
    token: driver.token,
  });
  console.log(`ARRIVED tripId=${offer.tripId}`);
  // Idle at the pickup so the rider sees "driver arrived" + the start code.
  await wait(WAIT_AT_PICKUP_MS);
  sock.close();
}

async function finish(tripId, otp) {
  const driver = await login(DEMO_DRIVER_PHONE);
  const sock = await connect(driver.token);
  await wait(400);

  // GET /trips/:id returns pickup/dropoff with flat lat/lng (not nested .point,
  // which is the Flutter model's shape — a mismatch that used to crash here).
  const trip = await api(`/trips/${tripId}`, { token: driver.token });
  const pickup = { lat: trip.pickup.lat, lng: trip.pickup.lng };
  const dropoff = { lat: trip.dropoff.lat, lng: trip.dropoff.lng };

  await api(`/trips/${tripId}/start`, {
    method: 'POST',
    token: driver.token,
    body: { otp },
  });
  console.log('trip started — driving to the dropoff');
  await drive(sock, pickup, dropoff, TRIP_MS, 'trip');

  const receipt = await api(`/trips/${tripId}/complete`, {
    method: 'POST',
    token: driver.token,
  });
  console.log(`COMPLETED fare=$${receipt.fareFinal} payout=$${receipt.driverPayout}`);
  sock.close();
}

const [stage, a, b] = process.argv.slice(2);
(stage === 'finish' ? finish(a, b) : accept()).catch((e) => {
  console.error('ERROR:', e.message);
  process.exit(1);
});
