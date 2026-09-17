// End-to-end check of the issues found in field testing on 2026-09-16, driven
// over the real REST + Socket.IO surfaces against a running backend.
//
//   1. The driver's offer countdown is a sane length (was 90 s).
//   2. The ride sheet can itemise a fare, and the lines add up to the price.
//   3. Leaving the route pops an advisory on the rider, once, and redraws the
//      live route from where the driver actually is.
//   4. Coming back onto the route clears it, and a later deviation alerts again.
//   5. Standing still long enough pops a "driver stopped" advisory, once, and
//      moving again clears it.
//   6. A completed ride never settles at $0.
//   7. A rating can be changed after it has been given.
//
// The watchdog thresholds are slow by design (3 minutes of standing still), so
// run the backend with short ones for this script:
//
//   STOPPED_AFTER_S=4 OFF_ROUTE_PINGS=2 REROUTE_MIN_GAP_S=1 npm run start:prod
//   node tools/fake-driver-simulator/field-issues-check.mjs
import { api, connect, login, once, onboardDriver, phone, wait } from './lib.mjs';

let failures = 0;
function check(cond, msg) {
  console.log(`${cond ? '  ✓' : '  ✗ FAIL'} ${msg}`);
  if (!cond) failures++;
}
function section(title) {
  console.log(`\n${title}`);
}

/** Collect every occurrence of an event for later assertions. */
function collect(socket, event) {
  const seen = [];
  socket.on(event, (data) => seen.push(data ?? {}));
  return seen;
}

/** Google-encoded polyline → points (mirrors the apps' decoder). */
function decodePolyline(encoded) {
  const points = [];
  let index = 0;
  let lat = 0;
  let lng = 0;
  while (index < encoded.length) {
    let shift = 0;
    let result = 0;
    let b;
    do {
      b = encoded.charCodeAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20 && index < encoded.length);
    lat += result & 1 ? ~(result >> 1) : result >> 1;
    shift = 0;
    result = 0;
    do {
      b = encoded.charCodeAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20 && index < encoded.length);
    lng += result & 1 ? ~(result >> 1) : result >> 1;
    points.push({ lat: lat / 1e5, lng: lng / 1e5 });
  }
  return points;
}

async function main() {
  const pickup = { lat: 25.7743, lng: -80.1937 };
  const dropoff = { lat: 25.7806, lng: -80.242 };

  const driver = await login(phone('90'));
  await onboardDriver(driver.token, 'economy');
  const dSock = await connect(driver.token);
  dSock.emit('driver:status', { status: 'online' });
  await wait(300);
  dSock.emit('driver:location', { lat: pickup.lat + 0.001, lng: pickup.lng + 0.001, speed: 0 });
  await wait(400);

  const rider = await login(phone('91'));
  const rSock = await connect(rider.token);

  // Watch for everything the rider should (and shouldn't) be told.
  const offRoute = collect(rSock, 'trip:off_route');
  const backOnRoute = collect(rSock, 'trip:back_on_route');
  const stopped = collect(rSock, 'trip:driver_stopped');
  const moving = collect(rSock, 'trip:driver_moving');
  const routeUpdates = collect(rSock, 'trip:route_updated');

  section('2. Fare details — the itemised lines a rider can check');
  const estimate = await api('/trips/estimate', {
    method: 'POST',
    token: rider.token,
    body: {
      pickupLat: pickup.lat,
      pickupLng: pickup.lng,
      dropoffLat: dropoff.lat,
      dropoffLng: dropoff.lng,
    },
  });
  for (const tier of estimate.tiers) {
    const b = tier.breakdown;
    if (!b) {
      check(false, `${tier.label}: estimate carries a breakdown`);
      continue;
    }
    const sum =
      Math.round(
        (b.baseFare + b.distanceFare + b.timeFare + b.bookingFee +
          (b.minimumFareAdjustment ?? 0)) * 100,
      ) / 100;
    check(sum === tier.fare, `${tier.label}: lines sum to $${tier.fare} (got $${sum})`);
  }

  const matchingP = once(rSock, 'trip:matching');
  const offerP = once(dSock, 'trip:offer');
  const acceptedP = once(rSock, 'trip:accepted');
  const trip = await api('/trips', {
    method: 'POST',
    token: rider.token,
    body: {
      pickupLat: pickup.lat,
      pickupLng: pickup.lng,
      dropoffLat: dropoff.lat,
      dropoffLng: dropoff.lng,
      tier: 'economy',
      pickupAddr: 'Pickup',
      dropoffAddr: 'Dropoff',
      paymentMode: 'cash',
    },
  });
  await matchingP;
  const offer = await offerP;

  section('1. Driver offer window');
  check(
    offer.expiresInSec > 0 && offer.expiresInSec <= 30,
    `offer countdown is ${offer.expiresInSec}s (must be ≤ 30, was 90 in the field)`,
  );

  dSock.emit('trip:accept', { tripId: offer.tripId });
  await acceptedP;

  // Drive to the pickup, arrive, and start the ride.
  dSock.emit('driver:location', { lat: pickup.lat, lng: pickup.lng, speed: 0, accuracy: 5 });
  await wait(500);
  await api(`/trips/${trip.id}/arrived`, { method: 'POST', token: driver.token });
  const full = await api(`/trips/${trip.id}`, { token: rider.token });
  const startedP = once(rSock, 'trip:started');
  await api(`/trips/${trip.id}/start`, {
    method: 'POST',
    token: driver.token,
    body: { otp: full.startOtp },
  });
  await startedP;

  const route = decodePolyline(full.routePolyline);
  const onRoutePoint = route[Math.floor(route.length / 2)];

  section('3. Driver leaves the route');
  // Drive the planned route first — this must stay silent.
  for (const p of route.slice(0, Math.min(4, route.length))) {
    dSock.emit('driver:location', { lat: p.lat, lng: p.lng, speed: 12, accuracy: 5 });
    await wait(250);
  }
  check(offRoute.length === 0, 'driving the planned route raises nothing');

  // Now swing ~1 km off it.
  const detour = { lat: onRoutePoint.lat + 0.009, lng: onRoutePoint.lng + 0.009 };
  for (let i = 0; i < 4; i++) {
    dSock.emit('driver:location', { lat: detour.lat, lng: detour.lng, speed: 12, accuracy: 5 });
    await wait(300);
  }
  await wait(1200);
  check(offRoute.length === 1, `leaving the route alerts exactly once (got ${offRoute.length})`);
  check(
    routeUpdates.length >= 1 && !!routeUpdates[0]?.polyline,
    'the live route is redrawn from where the driver actually is',
  );

  section('4. Driver rejoins the route');
  dSock.emit('driver:location', { lat: onRoutePoint.lat, lng: onRoutePoint.lng, speed: 12, accuracy: 5 });
  await wait(900);
  check(backOnRoute.length >= 1, 'rejoining the route clears the advisory');

  section('5. Driver stops for a while');
  const parked = { lat: onRoutePoint.lat, lng: onRoutePoint.lng };
  const stoppedAfterS = Number(process.env.STOPPED_AFTER_S ?? 4);
  // Time the alert against the wall clock from the moment the car stops, not
  // against the figure the alert reports — the driver may already have been
  // stationary before this section started (the run-up parks them briefly),
  // so the reported duration legitimately counts from that earlier moment.
  let firedAt = null;
  const parkedAt = Date.now();
  const stoppedSeen = stopped.length;
  rSock.on('trip:driver_stopped', () => {
    firedAt ??= Date.now();
  });
  for (let i = 0; i < stoppedAfterS + 6; i++) {
    dSock.emit('driver:location', { lat: parked.lat, lng: parked.lng, speed: 0, accuracy: 5 });
    await wait(1000);
  }
  const raised = stopped.slice(stoppedSeen);
  check(stopped.length === 1, `standing still alerts exactly once (got ${stopped.length})`);
  if (raised.length) {
    const waited = Math.round((firedAt - parkedAt) / 1000);
    check(
      raised[0].stoppedSec >= stoppedAfterS,
      `the alert reports a full stop: ${raised[0].stoppedSec}s (threshold ${stoppedAfterS}s)`,
    );
    check(
      waited <= stoppedAfterS + 5,
      `it fired promptly once the threshold passed (+${waited}s)`,
    );
  }

  // Drive off again.
  dSock.emit('driver:location', { lat: parked.lat + 0.004, lng: parked.lng, speed: 12, accuracy: 5 });
  await wait(900);
  check(moving.length >= 1, 'setting off again clears the advisory');

  section('6. The fare on a completed ride');
  const completedP = once(rSock, 'trip:completed');
  // Drive the rest of the route so the odometer has a real trail.
  for (const p of route.slice(Math.floor(route.length / 2))) {
    dSock.emit('driver:location', { lat: p.lat, lng: p.lng, speed: 12, accuracy: 5 });
    await wait(120);
  }
  dSock.emit('driver:location', { lat: dropoff.lat, lng: dropoff.lng, speed: 0, accuracy: 5 });
  await wait(400);
  await api(`/trips/${trip.id}/complete`, { method: 'POST', token: driver.token });
  const completed = await completedP;
  check(completed.fareFinal > 0, `trip:completed carries a real fare ($${completed.fareFinal})`);

  const receipt = await api(`/payments/${trip.id}/receipt`, { token: rider.token });
  check(receipt.fare > 0, `the receipt carries a real fare ($${receipt.fare})`);
  if (receipt.breakdown) {
    const b = receipt.breakdown;
    const sum =
      Math.round(
        (b.baseFare + b.distanceFare + b.timeFare + b.bookingFee +
          (b.minimumFareAdjustment ?? 0) - (b.promoDiscount ?? 0)) * 100,
      ) / 100;
    check(sum === receipt.fare, `the receipt's lines sum to $${receipt.fare} (got $${sum})`);
  }

  section('7. Changing a rating');
  await api(`/trips/${trip.id}/rating`, {
    method: 'POST',
    token: rider.token,
    body: { stars: 5 },
  });
  let mine = await api(`/trips/${trip.id}/rating`, { token: rider.token });
  check(mine?.stars === 5, 'first rating recorded (5)');
  await api(`/trips/${trip.id}/rating`, {
    method: 'POST',
    token: rider.token,
    body: { stars: 3 },
  });
  mine = await api(`/trips/${trip.id}/rating`, { token: rider.token });
  check(mine?.stars === 3, 'the rating can be changed afterwards (5 → 3)');

  dSock.close();
  rSock.close();

  console.log(
    failures === 0
      ? '\nAll field-issue checks passed.'
      : `\n${failures} check(s) FAILED.`,
  );
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error('\nSimulation error:', e.message);
  process.exit(1);
});
