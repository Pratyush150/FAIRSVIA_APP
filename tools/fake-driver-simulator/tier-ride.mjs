// A real ride on one ride type in Pune, end to end over REST + Socket.IO:
// rider quote → book → offer to a driver OF THAT TYPE ONLY → accept → arrive
// → OTP start → complete, with the fare checked in rupees.
//
// A decoy economy driver is put online right beside the pickup: it must NOT
// be offered an auto or bike ride. Run against the INR (Pune) backend:
//
//   node tier-ride.mjs auto
//   node tier-ride.mjs bike
import {
  api,
  connect,
  login,
  once,
  onboardDriver,
  phone,
  wait,
} from './lib.mjs';

const TIER = process.argv[2] || 'auto';

function assert(cond, msg) {
  if (!cond) throw new Error('ASSERT FAILED: ' + msg);
}

/** Resolve true if [event] arrives within [ms], else false (no throw). */
function arrives(socket, event, ms) {
  return new Promise((resolve) => {
    const t = setTimeout(() => resolve(false), ms);
    socket.once(event, () => {
      clearTimeout(t);
      resolve(true);
    });
  });
}

async function goOnline(token, at) {
  const sock = await connect(token);
  sock.emit('driver:status', { status: 'online' });
  await wait(300);
  sock.emit('driver:location', { lat: at.lat, lng: at.lng, heading: 90, speed: 0 });
  await wait(400);
  return sock;
}

async function main() {
  // Shivajinagar → Aundh, Pune.
  const pickup = { lat: 18.53, lng: 73.8475 };
  const dropoff = { lat: 18.559, lng: 73.8076 };

  // --- The driver of this type, and a decoy economy car beside it ---
  const driver = await login(phone('92'));
  const profile = await onboardDriver(driver.token, TIER);
  assert(profile.vehicleTier === TIER, `driver registered as ${TIER}`);
  const dSock = await goOnline(driver.token, { lat: pickup.lat + 0.001, lng: pickup.lng + 0.001 });
  console.log(`• ${TIER} driver online (${profile.vehicleMake} ${profile.vehicleModel}, ${profile.plateNumber})`);

  const decoy = await login(phone('94'));
  await onboardDriver(decoy.token, 'economy');
  const decoySock = await goOnline(decoy.token, { lat: pickup.lat + 0.0005, lng: pickup.lng + 0.0005 });
  console.log('• decoy economy driver online, even closer to the pickup');

  // --- Rider: quote ---
  const rider = await login(phone('95'));
  const rSock = await connect(rider.token);
  const est = await api('/trips/estimate', {
    method: 'POST',
    token: rider.token,
    body: { pickupLat: pickup.lat, pickupLng: pickup.lng, dropoffLat: dropoff.lat, dropoffLng: dropoff.lng },
  });
  console.log(`• estimate: ${(est.distanceM / 1000).toFixed(2)} km, ${Math.round(est.durationS / 60)} min, ${est.currency}, surge ${est.surge}`);
  for (const t of est.tiers) {
    console.log(`    ${t.tier.padEnd(8)} ${t.label.padEnd(8)} ${t.capacity} seat(s)  ₹${t.fare}  ${t.etaSeconds == null ? '(none nearby)' : `pickup ~${Math.round(t.etaSeconds / 60)} min`}`);
  }
  assert(est.currency === 'INR', 'quoted in rupees');
  const quote = est.tiers.find((t) => t.tier === TIER);
  assert(quote, `${TIER} is offered`);
  assert(Number.isInteger(quote.fare), 'whole-rupee fare');
  assert(quote.etaSeconds != null, `a ${TIER} is nearby`);
  // The government meter for this distance (surge 1): auto ₹20/km, min ₹30;
  // bike ₹10.27/km, min ₹15.
  const km = est.distanceM / 1000;
  const meter = TIER === 'auto' ? Math.max(30, Math.round(km * 20)) : Math.max(15, Math.round(km * 10.27));
  if (est.surge === 1) {
    assert(Math.abs(quote.fare - meter) <= 1, `quote ₹${quote.fare} matches the meter ₹${meter}`);
    console.log(`• quote ₹${quote.fare} = meter for ${km.toFixed(2)} km (₹${meter}) ✓`);
  }

  // --- Book ---
  const offerP = once(dSock, 'trip:offer', 20000);
  const decoyOfferP = arrives(decoySock, 'trip:offer', 8000);
  const acceptedP = once(rSock, 'trip:accepted', 25000);
  const trip = await api('/trips', {
    method: 'POST',
    token: rider.token,
    body: {
      pickupLat: pickup.lat,
      pickupLng: pickup.lng,
      dropoffLat: dropoff.lat,
      dropoffLng: dropoff.lng,
      tier: TIER,
      pickupAddr: 'Shivajinagar, Pune',
      dropoffAddr: 'Aundh, Pune',
      paymentMode: 'cash',
    },
  });
  assert(trip.tier === TIER, `trip tier ${TIER}`);
  console.log(`• trip ${trip.id} requested (${trip.tier}, ₹${trip.fareEstimate}, cash)`);

  const offer = await offerP;
  assert(offer.tripId === trip.id, 'offer is for this trip');
  assert(offer.tier === TIER, `offer tier ${TIER}`);
  console.log(`• ${TIER} driver ← trip:offer  ₹${offer.fare}`);
  dSock.emit('trip:accept', { tripId: offer.tripId });
  const accepted = await acceptedP;
  console.log(`• rider ← trip:accepted  ${accepted.vehicle.make} ${accepted.vehicle.model} ${accepted.vehicle.plate}`);
  assert(!(await decoyOfferP), 'economy decoy was NOT offered the ride');
  console.log('• decoy economy driver got no offer ✓');

  // --- Pickup, start, complete ---
  dSock.emit('driver:location', { lat: pickup.lat, lng: pickup.lng, heading: 90, speed: 8 });
  await wait(300);
  const arrivedP = once(rSock, 'trip:arrived');
  await api(`/trips/${trip.id}/arrived`, { method: 'POST', token: driver.token });
  await arrivedP;
  const riderView = await api(`/trips/${trip.id}`, { token: rider.token });
  const startedP = once(rSock, 'trip:started');
  await api(`/trips/${trip.id}/start`, { method: 'POST', token: driver.token, body: { otp: riderView.startOtp } });
  await startedP;
  console.log('• arrived → started (OTP)');
  const completedP = once(rSock, 'trip:completed');
  const receipt = await api(`/trips/${trip.id}/complete`, { method: 'POST', token: driver.token });
  await completedP;
  const final = await api(`/trips/${trip.id}`, { token: rider.token });
  assert(final.status === 'completed', 'completed');
  assert(final.currency === 'INR', 'trip in rupees');
  assert(Number.isInteger(receipt.fareFinal), 'whole-rupee final fare');
  console.log(`• completed  fare ₹${receipt.fareFinal} (${final.currency})  platform ₹${receipt.platformFee}  driver ₹${receipt.driverPayout}`);

  console.log(`\n✅ ${TIER.toUpperCase()} RIDE OK — quote ₹${quote.fare} → offer (${TIER} driver only) → accept → arrive → start → complete ₹${receipt.fareFinal}`);

  for (const s of [dSock, decoySock]) s.emit('driver:status', { status: 'offline' });
  await wait(300);
  dSock.close();
  decoySock.close();
  rSock.close();
  process.exit(0);
}

main().catch((e) => {
  console.error('❌ FAILED:', e.message);
  process.exit(1);
});
