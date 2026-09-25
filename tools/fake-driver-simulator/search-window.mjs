// The ride search window, live against the running backend (Pune):
//
//   1. A rider books Comfort with NO comfort driver online.
//   2. The trip must stay searching (matching) — not fail at once.
//   3. 20 s later a comfort driver comes online beside the pickup.
//   4. That driver must be offered the waiting ride (well inside the window),
//      and accepts; the rider then cancels, so nothing is left running.
//
//   node search-window.mjs            # default 20 s delay before the driver
//   node search-window.mjs 45         # driver comes online after 45 s
import { api, connect, login, onboardDriver, phone, wait } from './lib.mjs';

const DELAY_S = Number(process.argv[2] || 20);

function assert(cond, msg) {
  if (!cond) throw new Error('ASSERT FAILED: ' + msg);
}

async function main() {
  const pickup = { lat: 18.53, lng: 73.8475 }; // Shivajinagar
  const dropoff = { lat: 18.559, lng: 73.8076 }; // Aundh

  const rider = await login(phone('95'));
  const rSock = await connect(rider.token);
  let matching = null;
  let noDrivers = false;
  rSock.on('trip:matching', (d) => (matching = d));
  rSock.on('trip:no_drivers', () => (noDrivers = true));

  const est = await api('/trips/estimate', {
    method: 'POST',
    token: rider.token,
    body: { pickupLat: pickup.lat, pickupLng: pickup.lng, dropoffLat: dropoff.lat, dropoffLng: dropoff.lng },
  });
  const comfort = est.tiers.find((t) => t.tier === 'comfort');
  assert(comfort, 'comfort is offered');
  console.log(`• quote: Comfort ₹${comfort.fare}, ${comfort.etaSeconds == null ? 'no car nearby' : `a car ~${Math.round(comfort.etaSeconds / 60)} min away`}`);

  const trip = await api('/trips', {
    method: 'POST',
    token: rider.token,
    body: {
      pickupLat: pickup.lat, pickupLng: pickup.lng,
      dropoffLat: dropoff.lat, dropoffLng: dropoff.lng,
      tier: 'comfort',
      paymentMode: 'cash',
    },
  });
  const booked = Date.now();
  console.log(`• booked Comfort trip ${trip.id}`);

  let driverSock;
  try {
    await wait(DELAY_S * 1000);
    const mid = await api(`/trips/${trip.id}`, { token: rider.token });
    console.log(`• after ${DELAY_S} s with no comfort driver: status=${mid.status}, no_drivers event=${noDrivers}`);
    assert(mid.status === 'matching', 'still searching inside the window');
    assert(!noDrivers, 'rider was not told no_drivers');
    if (matching) {
      console.log(`  trip:matching said: window ${matching.searchWindowSec} s, ends ${matching.searchEndsAt}`);
    }

    // A comfort driver comes online beside the pickup.
    const driver = await login(phone('92'));
    const profile = await onboardDriver(driver.token, 'comfort');
    assert(profile.vehicleTier === 'comfort', 'driver registered as comfort');
    driverSock = await connect(driver.token);
    const offer = new Promise((resolve) => driverSock.once('trip:offer', resolve));
    driverSock.emit('driver:status', { status: 'online' });
    await wait(300);
    const online = Date.now();
    driverSock.emit('driver:location', { lat: pickup.lat + 0.001, lng: pickup.lng + 0.001, heading: 90, speed: 0 });
    console.log(`• comfort driver online at +${Math.round((online - booked) / 1000)} s (${profile.vehicleMake} ${profile.vehicleModel})`);

    const got = await Promise.race([offer, wait(20000).then(() => null)]);
    assert(got, 'the comfort driver was offered the waiting ride');
    assert(got.tripId === trip.id, 'offer is for the waiting trip');
    console.log(`• OFFER received ${Date.now() - online} ms after the driver's first GPS fix (trip ${got.tripId}, tier ${got.tier}, ₹${got.fare})`);

    driverSock.emit('trip:accept', { tripId: trip.id });
    await wait(1500);
    const after = await api(`/trips/${trip.id}`, { token: rider.token });
    console.log(`• driver accepted → status=${after.status}`);
    assert(after.status === 'accepted', 'trip accepted by the comfort driver');
    console.log('PASS: search kept going and the late comfort driver got the ride');
  } finally {
    await api(`/trips/${trip.id}/cancel`, {
      method: 'POST',
      token: rider.token,
      body: { reason: 'search-window simulation cleanup' },
    }).catch((e) => console.log(`  (cleanup cancel: ${e.message})`));
    if (driverSock) {
      driverSock.emit('driver:status', { status: 'offline' });
      await wait(300);
      driverSock.close();
    }
    rSock.close();
  }
}

main().then(
  () => process.exit(0),
  (e) => {
    console.error(e.message);
    process.exit(1);
  },
);
