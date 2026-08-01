// Situational tests for concurrency:
//  A) 2 riders request at once + 2 drivers  → each rider gets a DISTINCT driver
//     (no driver double-booked).
//  B) 2 riders + 1 driver → exactly one is matched, the other ends no_drivers.
import { api, connect, login, onboardDriver, wait } from './lib.mjs';

const P1 = { lat: 25.7617, lng: -80.1918 };
const P2 = { lat: 25.762, lng: -80.19 };
const D1 = { lat: 25.7625, lng: -80.1915 };
const D2 = { lat: 25.7628, lng: -80.1905 };

let pass = 0;
let fail = 0;
const ok = (c, m) => {
  if (c) {
    pass++;
    console.log('  ✓ ' + m);
  } else {
    fail++;
    console.log('  ✗ ' + m);
  }
};

async function driverOnline(phoneNum, loc) {
  const d = await login(phoneNum);
  await onboardDriver(d.token, 'economy');
  const sock = await connect(d.token);
  sock.emit('driver:status', { status: 'online' });
  await wait(200);
  sock.emit('driver:location', { ...loc, heading: 0, speed: 0 });
  const hb = setInterval(
    () => sock.emit('driver:location', { ...loc, heading: 0, speed: 0 }),
    4000,
  );
  // auto-accept the first offer it gets
  sock.on('trip:offer', (o) => sock.emit('trip:accept', { tripId: o.tripId }));
  return { d, sock, hb };
}

async function request(riderPhone, pickup) {
  const rider = await login(riderPhone);
  const trip = await api('/trips', {
    method: 'POST',
    token: rider.token,
    body: {
      pickupLat: pickup.lat,
      pickupLng: pickup.lng,
      pickupAddr: 'P',
      dropoffLat: 25.79,
      dropoffLng: -80.13,
      dropoffAddr: 'D',
      tier: 'economy',
      paymentMode: 'cash',
    },
  });
  return { rider, tripId: trip.id };
}

const finalTrip = (rider, id) => api(`/trips/${id}`, { token: rider.token });

(async () => {
  // ---- A) 2 riders + 2 drivers → distinct drivers ----
  console.log('── A) 2 riders + 2 drivers: distinct assignment ──');
  await new Promise((r) => setTimeout(r, 100));
  const d1 = await driverOnline('+19831000001', D1);
  const d2 = await driverOnline('+19832000002', D2);
  await wait(600);

  // fire both requests near-simultaneously
  const [r1, r2] = await Promise.all([
    request('+13055550001', P1),
    request('+13055550002', P2),
  ]);
  await wait(6000);
  const t1 = await finalTrip(r1.rider, r1.tripId);
  const t2 = await finalTrip(r2.rider, r2.tripId);
  console.log(
    `  trip1 ${t1.status} driver=${t1.driverId?.slice(0, 8)} | trip2 ${t2.status} driver=${t2.driverId?.slice(0, 8)}`,
  );
  ok(t1.status === 'accepted' && t2.status === 'accepted', 'both riders matched');
  ok(
    !!t1.driverId && !!t2.driverId && t1.driverId !== t2.driverId,
    'each rider got a DISTINCT driver (no double-booking)',
  );

  clearInterval(d1.hb);
  clearInterval(d2.hb);
  d1.sock.close();
  d2.sock.close();
  await wait(500);

  // ---- B) 2 riders + 1 driver → one matched, one no_drivers ----
  console.log('\n── B) 2 riders + 1 driver: one matched, one no_drivers ──');
  // clear the pool from scenario A leftovers
  const only = await driverOnline('+19833000003', D1);
  await wait(600);
  const [r3, r4] = await Promise.all([
    request('+13055550003', P1),
    request('+13055550004', P2),
  ]);
  await wait(8000);
  const t3 = await finalTrip(r3.rider, r3.tripId);
  const t4 = await finalTrip(r4.rider, r4.tripId);
  const statuses = [t3.status, t4.status].sort();
  console.log(`  statuses: ${statuses.join(', ')}`);
  ok(
    statuses.includes('accepted'),
    `exactly one matched (${t3.status}/${t4.status})`,
  );
  ok(
    statuses.filter((s) => s === 'accepted').length === 1,
    'only ONE matched (single driver not double-booked)',
  );

  clearInterval(only.hb);
  only.sock.close();

  console.log(`\n  PASS ${pass}  FAIL ${fail}`);
  process.exit(fail ? 1 : 0);
})().catch((e) => {
  console.error('ERR', e.message);
  process.exit(1);
});
