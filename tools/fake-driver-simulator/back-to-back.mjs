// Back-to-back rides: a driver who just completed trip A must be offerable at
// once — while they are still on the "Trip complete / rate your rider" screen —
// without tapping Done, going online again, or sending another GPS ping.
//
// Owner bug: "the driver just completed the ride but while he is doing rating
// etc. he doesn't get ride requests for that duration."
//
// Strict version: after POST /trips/:id/complete the driver sends NOTHING
// (no driver:status, no driver:location). Rider B then books right next to
// the drop-off and the driver must receive trip:offer within a few seconds.
// Run: node back-to-back.mjs   (backend must be running)
import { api, connect, login, once, onboardDriver, phone, wait } from './lib.mjs';

function assert(cond, msg) {
  if (!cond) throw new Error('ASSERT FAILED: ' + msg);
}

async function main() {
  // A remote spot so no other simulated driver is nearer than ours.
  const base = { lat: 6.2 + Math.random() * 0.5, lng: 3.1 + Math.random() * 0.5 };
  const pickupA = base;
  const dropoffA = { lat: base.lat + 0.01, lng: base.lng + 0.01 };

  const driver = await login(phone('92'));
  await onboardDriver(driver.token, 'economy');
  const dSock = await connect(driver.token);
  dSock.emit('driver:status', { status: 'online' });
  await wait(300);
  dSock.emit('driver:location', { lat: pickupA.lat, lng: pickupA.lng, heading: 0, speed: 0 });
  await wait(400);
  console.log(`• driver online at (${pickupA.lat.toFixed(4)}, ${pickupA.lng.toFixed(4)})`);

  // --- Trip A, the full lifecycle ---
  // Both riders log in up front so the only thing between completing A and
  // booking B is the booking itself.
  const riderA = await login(phone('93'));
  const riderB = await login(phone('94'));
  const offerAP = once(dSock, 'trip:offer');
  const tripA = await api('/trips', {
    method: 'POST',
    token: riderA.token,
    body: {
      pickupLat: pickupA.lat, pickupLng: pickupA.lng,
      dropoffLat: dropoffA.lat, dropoffLng: dropoffA.lng,
      tier: 'economy', paymentMode: 'cash',
    },
  });
  const offerA = await offerAP;
  assert(offerA.tripId === tripA.id, 'offer A is for trip A');
  await api(`/trips/${tripA.id}/accept`, { method: 'POST', token: driver.token });
  await wait(300);
  await api(`/trips/${tripA.id}/arrived`, { method: 'POST', token: driver.token });
  const { startOtp } = await api(`/trips/${tripA.id}`, { token: riderA.token });
  await api(`/trips/${tripA.id}/start`, { method: 'POST', token: driver.token, body: { otp: startOtp } });
  // Drive to the drop-off: the last GPS fix the server has is AT the drop-off.
  dSock.emit('driver:location', { lat: dropoffA.lat, lng: dropoffA.lng, heading: 45, speed: 8 });
  await wait(400);
  console.log(`• trip A ${tripA.id.slice(0, 8)} accepted → arrived → started → at drop-off`);

  const tComplete = Date.now();
  await api(`/trips/${tripA.id}/complete`, { method: 'POST', token: driver.token });
  console.log('• trip A completed — driver now sits on the rate-rider screen and sends NOTHING');

  // --- Rider B books right next to the drop-off, immediately ---
  const offerBP = once(dSock, 'trip:offer', 20000);
  const tripB = await api('/trips', {
    method: 'POST',
    token: riderB.token,
    body: {
      pickupLat: dropoffA.lat + 0.001, pickupLng: dropoffA.lng + 0.001,
      dropoffLat: dropoffA.lat + 0.02, dropoffLng: dropoffA.lng + 0.02,
      tier: 'economy', paymentMode: 'cash',
    },
  });
  let offerB;
  try {
    offerB = await offerBP;
  } catch (e) {
    await api(`/trips/${tripB.id}/cancel`, { method: 'POST', token: riderB.token, body: { reason: 'sim' } }).catch(() => {});
    throw new Error(`driver was NOT offered trip B after completing A: ${e.message}`);
  }
  const dt = ((Date.now() - tComplete) / 1000).toFixed(2);
  assert(offerB.tripId === tripB.id, 'offer B is for trip B');
  console.log(`• driver ← trip:offer for trip B ${tripB.id.slice(0, 8)} ${dt}s after completing A (no extra action)`);
  assert(Number(dt) < 10, `offer B arrived within 10 s (took ${dt}s)`);

  // Accepting B from the completion screen starts the new trip; rating A is
  // still possible afterwards ("rate later").
  await api(`/trips/${tripB.id}/accept`, { method: 'POST', token: driver.token });
  await wait(300);
  const b = await api(`/trips/${tripB.id}`, { token: driver.token });
  assert(b.status === 'accepted', `trip B accepted (${b.status})`);
  const rated = await api(`/trips/${tripA.id}/rating`, { method: 'POST', token: driver.token, body: { stars: 5 } });
  assert(rated.toUser === riderA.user.id, 'rider A rated later, while on trip B');
  console.log('• accepted trip B; rated rider A afterwards (5★) — rating is not a gate');

  await api(`/trips/${tripB.id}/driver-cancel`, { method: 'POST', token: driver.token, body: { reason: 'sim cleanup' } }).catch(() => {});
  dSock.emit('driver:status', { status: 'offline' });
  dSock.close();
  console.log('\nPASS back-to-back: driver offerable immediately after completion');
  process.exit(0);
}

main().catch((e) => {
  console.error('\nFAIL', e.message);
  process.exit(1);
});
