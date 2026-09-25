// Destination ("go home") mode, live against the running backend (Pune):
//
//   1. A driver comes online at Shivajinagar and sets a destination ~8 km
//      north (POST /drivers/me/destination-mode).
//   2. Rider A books a trip whose drop-off is AWAY from that destination
//      (south). The driver — the closest car — must NOT be offered it.
//   3. Rider B books a trip whose drop-off is TOWARD the destination.
//      The driver must be offered it.
//   4. Cleanup: both trips cancelled, destination cleared, driver offline.
//
//   node destination-mode.mjs
import { api, connect, login, onboardDriver, phone, wait } from './lib.mjs';

function assert(cond, msg) {
  if (!cond) throw new Error('ASSERT FAILED: ' + msg);
}

const DRIVER_AT = { lat: 18.53, lng: 73.8475 }; // Shivajinagar
const HOME = { lat: 18.602, lng: 73.8475, label: 'Home' }; // ~8 km north
const PICKUP = { lat: 18.5305, lng: 73.848 };
const AWAY = { lat: 18.47, lng: 73.86 }; // south, further from home
const TOWARD = { lat: 18.585, lng: 73.85 }; // ~1.9 km from home (≪ 70 % of 8 km)

async function book(rider, dropoff) {
  return api('/trips', {
    method: 'POST',
    token: rider.token,
    body: {
      pickupLat: PICKUP.lat, pickupLng: PICKUP.lng,
      dropoffLat: dropoff.lat, dropoffLng: dropoff.lng,
      tier: 'economy', paymentMode: 'cash',
    },
  });
}

async function main() {
  const driver = await login(phone('93'));
  await onboardDriver(driver.token, 'economy');
  const dSock = await connect(driver.token);
  const offers = [];
  dSock.on('trip:offer', (o) => {
    offers.push(o);
    console.log(`  driver got offer for trip ${o.tripId}`);
  });
  dSock.emit('driver:status', { status: 'online' });
  await wait(300);
  dSock.emit('driver:location', { ...DRIVER_AT, heading: 0, speed: 0 });
  const keepAlive = setInterval(
    () => dSock.emit('driver:location', { ...DRIVER_AT, heading: 0, speed: 0 }),
    3000,
  );
  await wait(500);

  const set = await api('/drivers/me/destination-mode', { method: 'POST', token: driver.token, body: HOME });
  assert(set.active === true, 'destination mode on');
  console.log(`• destination set: ${set.destination.label} · ${set.usesToday} of ${set.usesPerDay} today, until ${set.expiresAt}`);

  const riderA = await login(phone('95'));
  const riderB = await login(phone('95'));
  const trips = [];
  try {
    const away = await book(riderA, AWAY);
    trips.push([riderA, away]);
    console.log(`• rider A booked AWAY trip ${away.id} (drop-off south)`);
    await wait(12000);
    assert(!offers.some((o) => o.tripId === away.id), 'away trip NOT offered to the destination-mode driver');
    console.log('  ✓ no offer for the away trip after 12 s');
    await api(`/trips/${away.id}/cancel`, { method: 'POST', token: riderA.token, body: { reason: 'sim' } }).catch(() => {});

    const toward = await book(riderB, TOWARD);
    trips.push([riderB, toward]);
    console.log(`• rider B booked TOWARD trip ${toward.id} (drop-off near home)`);
    const t0 = Date.now();
    while (Date.now() - t0 < 20000 && !offers.some((o) => o.tripId === toward.id)) await wait(250);
    assert(offers.some((o) => o.tripId === toward.id), 'toward trip offered to the destination-mode driver');
    console.log(`  ✓ offered the toward trip after ${Date.now() - t0} ms`);
    dSock.emit('trip:decline', { tripId: toward.id });
    console.log('PASS: only the trip heading toward the destination was offered');
  } finally {
    for (const [r, t] of trips) {
      await api(`/trips/${t.id}/cancel`, { method: 'POST', token: r.token, body: { reason: 'sim cleanup' } }).catch(() => {});
    }
    await api('/drivers/me/destination-mode', { method: 'DELETE', token: driver.token }).catch(() => {});
    clearInterval(keepAlive);
    dSock.emit('driver:status', { status: 'offline' });
    await wait(300);
    dSock.close();
  }
}

main().then(
  () => process.exit(0),
  (e) => {
    console.error(e.message);
    process.exit(1);
  },
);
