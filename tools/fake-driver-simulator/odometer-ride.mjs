// Validates the driven-distance odometer + final-fare recompute (settleFare).
// Unlike full-ride.mjs (sparse pings → fare falls back to the estimate), this
// streams many GPS pings along the route DURING in_progress, so the backend
// accumulates real driven meters and recomputes the final fare from them.
// Run: node odometer-ride.mjs
import { api, connect, login, once, onboardDriver, phone, wait } from './lib.mjs';

function assert(cond, msg) {
  if (!cond) throw new Error('ASSERT FAILED: ' + msg);
}

// Great-circle meters — must match the backend's haversineMeters.
function haversine(a, b) {
  const R = 6371000;
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const lat1 = toRad(a.lat);
  const lat2 = toRad(b.lat);
  const x =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(x));
}

async function main() {
  const pickup = { lat: 12.9611, lng: 77.6387 };
  const dropoff = { lat: 12.9674, lng: 77.5904 };

  const driver = await login(phone('90'));
  await onboardDriver(driver.token, 'economy');
  const dSock = await connect(driver.token);
  dSock.emit('driver:status', { status: 'online' });
  await wait(300);
  dSock.emit('driver:location', { lat: pickup.lat, lng: pickup.lng, heading: 90, speed: 0 });
  await wait(300);

  const rider = await login(phone('91'));
  const rSock = await connect(rider.token);

  const offerP = once(dSock, 'trip:offer');
  const trip = await api('/trips', {
    method: 'POST',
    token: rider.token,
    body: {
      pickupLat: pickup.lat, pickupLng: pickup.lng,
      dropoffLat: dropoff.lat, dropoffLng: dropoff.lng,
      tier: 'economy', pickupAddr: 'Indiranagar', dropoffAddr: 'MG Road',
    },
  });
  const estimateFare = trip.fareEstimate;
  const offer = await offerP;
  dSock.emit('trip:accept', { tripId: offer.tripId });
  await once(rSock, 'trip:accepted');

  await api(`/trips/${trip.id}/arrived`, { method: 'POST', token: driver.token });
  const riderView = await api(`/trips/${trip.id}`, { token: rider.token });
  await api(`/trips/${trip.id}/start`, {
    method: 'POST', token: driver.token, body: { otp: riderView.startOtp },
  });
  console.log('• trip in_progress — streaming GPS along the route');

  // Interpolate N points pickup→dropoff, emit each as a driver:location ping.
  const N = 40;
  let driven = 0;
  let prev = pickup;
  for (let i = 1; i <= N; i++) {
    const t = i / N;
    const cur = {
      lat: pickup.lat + (dropoff.lat - pickup.lat) * t,
      lng: pickup.lng + (dropoff.lng - pickup.lng) * t,
    };
    driven += haversine(prev, cur);
    prev = cur;
    dSock.emit('driver:location', { lat: cur.lat, lng: cur.lng, heading: 270, speed: 30 });
    await wait(25); // let the server process each ping
  }
  await wait(400); // drain
  console.log(`• streamed ${N} pings, client-side driven ≈ ${Math.round(driven)} m`);

  const receipt = await api(`/trips/${trip.id}/complete`, {
    method: 'POST', token: driver.token,
  });
  const final = await api(`/trips/${trip.id}`, { token: rider.token });

  console.log(`• estimate fare      ₹${estimateFare}`);
  console.log(`• final (metered)    ₹${receipt.fareFinal}`);
  console.log(`• receipt distanceM  ${receipt.distanceM} m  (driven ≈ ${Math.round(driven)} m)`);

  // The odometer must have engaged: recorded distance close to what we drove.
  assert(receipt.distanceM > 1000, 'odometer accumulated a real distance');
  const err = Math.abs(receipt.distanceM - driven) / driven;
  assert(err < 0.1, `recorded distance within 10% of driven (err=${(err * 100).toFixed(1)}%)`);
  assert(receipt.fareFinal > 0, 'final fare positive');
  assert(final.fareFinal === receipt.fareFinal, 'trip row persisted the metered fare');

  console.log(
    `\n✅ ODOMETER OK — final fare recomputed from ${receipt.distanceM} m driven ` +
      `(within ${(err * 100).toFixed(1)}% of the ${Math.round(driven)} m streamed)`,
  );

  dSock.close();
  rSock.close();
  process.exit(0);
}

main().catch((e) => {
  console.error('❌ FAILED:', e.message);
  process.exit(1);
});
