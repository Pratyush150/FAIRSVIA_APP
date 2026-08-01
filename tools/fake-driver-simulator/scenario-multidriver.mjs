// Situational test: 2 drivers, 1 rider.
//  - the NEAREST driver must be offered the trip first
//  - if they decline, dispatch must fail over to the next-nearest driver
//  - that driver accepting moves the trip to `accepted`
import { api, connect, login, onboardDriver, wait } from './lib.mjs';

const PICKUP = { lat: 25.7617, lng: -80.1918 }; // downtown Miami
const NEAR = { lat: 25.765, lng: -80.1918 }; // ~0.4 km from pickup
const FAR = { lat: 25.785, lng: -80.1918 }; // ~2.6 km from pickup

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

async function goOnline(phoneNum, loc, label) {
  const d = await login(phoneNum);
  await onboardDriver(d.token, 'economy');
  const sock = await connect(d.token);
  sock.emit('driver:status', { status: 'online' });
  await wait(200);
  sock.emit('driver:location', { ...loc, heading: 0, speed: 0 });
  // Heartbeat so ghost-eviction (F9) doesn't drop us mid-test.
  const hb = setInterval(
    () => sock.emit('driver:location', { ...loc, heading: 0, speed: 0 }),
    4000,
  );
  return { d, sock, hb, label };
}

(async () => {
  console.log('── 2 drivers, 1 rider: nearest-first + decline→failover ──');
  const near = await goOnline('+19810000001', NEAR, 'NEAR');
  const far = await goOnline('+19820000002', FAR, 'FAR');
  await wait(600);

  const offers = [];
  near.sock.on('trip:offer', (o) =>
    offers.push({ who: 'NEAR', tripId: o.tripId, t: Date.now() }),
  );
  far.sock.on('trip:offer', (o) =>
    offers.push({ who: 'FAR', tripId: o.tripId, t: Date.now() }),
  );

  const rider = await login('+13055551234');
  const trip = await api('/trips', {
    method: 'POST',
    token: rider.token,
    body: {
      pickupLat: PICKUP.lat,
      pickupLng: PICKUP.lng,
      pickupAddr: 'Pickup',
      dropoffLat: 25.79,
      dropoffLng: -80.13,
      dropoffAddr: 'Dropoff',
      tier: 'economy',
      paymentMode: 'cash',
    },
  });
  console.log(`  trip ${trip.id} (${trip.status})`);

  await wait(3000);
  ok(offers.length >= 1, `an offer arrived (${offers.length})`);
  ok(offers[0]?.who === 'NEAR', `NEAREST offered first (got ${offers[0]?.who})`);

  near.sock.emit('trip:decline', { tripId: trip.id });
  console.log('  NEAR declined — expecting failover to FAR');

  await wait(5000);
  const farOffer = offers.find((o) => o.who === 'FAR');
  ok(!!farOffer, 'FAR offered after NEAR declined (failover works)');

  if (farOffer) {
    far.sock.emit('trip:accept', { tripId: trip.id });
    await wait(2500);
    const t = await api(`/trips/${trip.id}`, { token: rider.token });
    ok(t.status === 'accepted', `FAR accepted → accepted (got ${t.status})`);
  }

  console.log(`\n  PASS ${pass}  FAIL ${fail}`);
  clearInterval(near.hb);
  clearInterval(far.hb);
  near.sock.close();
  far.sock.close();
  process.exit(fail ? 1 : 0);
})().catch((e) => {
  console.error('ERR', e.message);
  process.exit(1);
});
