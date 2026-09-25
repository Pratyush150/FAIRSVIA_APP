// End-to-end "does it behave like Uber?" verification.
//
// Asserts the things you can't eyeball on a screen:
//   1. The pickup ADDRESS + coords the rider booked are exactly what the
//      driver receives in the ride request.
//   2. On accept, the driver is sent the APPROACH route (their car -> pickup)
//      so their map can show where they're collecting the rider from.
//   3. The start OTP genuinely gates the trip: the rider sees it, the driver
//      does NOT, a WRONG code is rejected, and only the right code starts it.
//   4. The trip settles with a fare + payment.
//
// Run: node uber-flow-check.mjs
import { api, connect, login, once, onboardDriver, phone, wait } from './lib.mjs';

let passed = 0;
const failures = [];
function check(cond, msg) {
  if (cond) {
    passed++;
    console.log(`   ✓ ${msg}`);
  } else {
    failures.push(msg);
    console.log(`   ✗ ${msg}`);
  }
}

async function main() {
  // Real Miami locations (matches the Florida data the backend serves).
  const pickup = { lat: 25.7663, lng: -80.1936, addr: 'Brickell City Centre' };
  const dropoff = { lat: 25.7907, lng: -80.13, addr: 'Miami Beach' };

  console.log('\n── 1. Driver goes online near the pickup ──');
  const driver = await login(phone('80'));
  await onboardDriver(driver.token, 'economy');
  const dSock = await connect(driver.token);
  dSock.emit('driver:status', { status: 'online' });
  await wait(300);
  dSock.emit('driver:location', {
    lat: pickup.lat + 0.004, // ~450m away, like a real nearby driver
    lng: pickup.lng + 0.004,
    heading: 90,
    speed: 0,
  });
  await wait(500);
  console.log('   driver online + broadcasting location');

  console.log('\n── 2. Rider books the ride ──');
  const rider = await login(phone('81'));
  const rSock = await connect(rider.token);
  const offerP = once(dSock, 'trip:offer');
  const assignedP = once(dSock, 'trip:assigned');
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
      pickupAddr: pickup.addr,
      dropoffAddr: dropoff.addr,
      // PAYMENT_MODE=cash when the rider has no saved card (PAYMENT_METHOD_REQUIRED).
      paymentMode: process.env.PAYMENT_MODE === 'cash' ? 'cash' : 'card',
    },
  });
  console.log(`   trip ${trip.id} created (${trip.status})`);
  check(trip.status === 'requested', 'trip created in "requested" state');
  check(trip.pickup?.address === pickup.addr, `rider's pickup address stored ("${pickup.addr}")`);

  console.log('\n── 3. Driver receives the ride request ──');
  const offer = await offerP;
  console.log(`   offer: $${offer.fare} · pickup "${offer.pickup?.address}"`);
  check(offer.tripId === trip.id, 'offer is for this exact trip');
  check(offer.pickup?.address === pickup.addr, 'PICKUP ADDRESS matches what the rider entered');
  check(
    Math.abs(offer.pickup?.lat - pickup.lat) < 0.0001 &&
      Math.abs(offer.pickup?.lng - pickup.lng) < 0.0001,
    'pickup COORDINATES match exactly',
  );
  check(offer.dropoff?.address === dropoff.addr, 'dropoff address matches');
  check(typeof offer.fare === 'number' && offer.fare > 0, 'offer carries a fare');

  console.log('\n── 4. Driver accepts → gets the approach route ──');
  dSock.emit('trip:accept', { tripId: offer.tripId });
  const assigned = await assignedP;
  const accepted = await acceptedP;
  check(assigned.tripId === trip.id, 'driver received trip:assigned');
  check(
    typeof assigned.driverPolyline === 'string' && assigned.driverPolyline.length > 0,
    'driver receives APPROACH route (their car → pickup) for the map',
  );
  check(
    typeof assigned.polyline === 'string' && assigned.polyline.length > 0,
    'driver receives the trip route (pickup → dropoff)',
  );
  check(!!accepted.vehicle?.plate, `rider sees the assigned car (${accepted.vehicle?.make} ${accepted.vehicle?.model})`);

  console.log('\n── 5. Driver arrives ──');
  // "Arrived" is geofenced (ARRIVAL_RADIUS_M): be at the pickup first.
  dSock.emit('driver:location', { lat: pickup.lat, lng: pickup.lng, heading: 90, speed: 0 });
  await wait(400);
  const arrivedP = once(rSock, 'trip:arrived');
  await api(`/trips/${trip.id}/arrived`, { method: 'POST', token: driver.token });
  await arrivedP;
  console.log('   rider notified: driver arrived');

  console.log('\n── 6. OTP verifies BOTH sides ──');
  const riderView = await api(`/trips/${trip.id}`, { token: rider.token });
  const driverView = await api(`/trips/${trip.id}`, { token: driver.token });
  check(!!riderView.startOtp, 'rider CAN see the start code');
  check(driverView.startOtp === null, 'driver CANNOT see the start code (must ask the rider)');

  // A wrong code must be rejected — this is what makes the OTP meaningful.
  const wrong = String((Number(riderView.startOtp) + 1) % 10000).padStart(4, '0');
  let rejected = false;
  try {
    await api(`/trips/${trip.id}/start`, {
      method: 'POST',
      token: driver.token,
      body: { otp: wrong },
    });
  } catch {
    rejected = true;
  }
  check(rejected, `WRONG code "${wrong}" is REJECTED`);

  const startedP = once(rSock, 'trip:started');
  await api(`/trips/${trip.id}/start`, {
    method: 'POST',
    token: driver.token,
    body: { otp: riderView.startOtp },
  });
  await startedP;
  check(true, `correct code "${riderView.startOtp}" STARTS the trip`);

  console.log('\n── 7. Trip completes + settles ──');
  // Reach the drop-off before completing: Complete ends the trip wherever the
  // car is, and short of the drop-off it is charged as a short trip (metered,
  // minimum-fare floor) rather than the normal clamped fare.
  dSock.emit('driver:location', { lat: dropoff.lat, lng: dropoff.lng, heading: 90, speed: 0 });
  await wait(400);
  const completedP = once(rSock, 'trip:completed');
  const receipt = await api(`/trips/${trip.id}/complete`, {
    method: 'POST',
    token: driver.token,
  });
  await completedP;
  console.log(`   fare $${receipt.fareFinal} · driver payout $${receipt.driverPayout}`);
  check(receipt.fareFinal > 0, 'final fare charged');
  check(receipt.driverPayout > 0, 'driver payout computed');

  const final = await api(`/trips/${trip.id}`, { token: rider.token });
  check(final.status === 'completed', 'trip ends in "completed"');

  console.log('\n════════════════════════════════');
  console.log(`  PASSED: ${passed}   FAILED: ${failures.length}`);
  if (failures.length) {
    console.log('  Failures:');
    failures.forEach((f) => console.log(`   - ${f}`));
  }
  console.log('════════════════════════════════\n');

  dSock.close();
  rSock.close();
  process.exit(failures.length ? 1 : 0);
}

main().catch((e) => {
  console.error('\nFLOW ERROR:', e.message);
  process.exit(1);
});
