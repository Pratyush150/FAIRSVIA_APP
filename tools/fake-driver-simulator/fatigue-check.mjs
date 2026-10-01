// Fatigue limit (docs/plans/driver-app-benchmark.md item 9), driven end to
// end against the running backend over Socket.IO + REST. The Uber rule: 12 h
// online (adding up across sessions, reset only by one 6 h offline break).
//   1. Two drivers online by the same pickup; the NEARER one is over the
//      limit. A rider books: only the rested driver is offered the trip.
//   2. Within one sweep (30 s) the tired driver is forced offline
//      (driver:status_changed reason 'fatigue' + driver:fatigue_locked).
//   3. Going online is refused: 409 DRIVER_REST_REQUIRED with the time left.
//   4. A third driver at 11h40m gets driver:fatigue_warning.
// Hours of online time are seeded into Redis (fairsvia_redis) — nobody waits
// 12 h. Run: node fatigue-check.mjs
import { execSync } from 'node:child_process';
import { BASE, api, connect, login, once, onboardDriver, phone, wait } from './lib.mjs';

function assert(cond, msg) {
  if (!cond) throw new Error('ASSERT FAILED: ' + msg);
  console.log('   ok:', msg);
}
const H = 3600;
const redis = (...args) =>
  execSync(`docker exec fairsvia_redis redis-cli ${args.join(' ')}`).toString().trim();

// A quiet corner (east Pune) so other simulators' drivers are not in range.
const pickup = { lat: 18.6331, lng: 73.9012 };
const dropoff = { lat: 18.5204, lng: 73.8567 };

async function onlineDriver(prefix, offsetLat) {
  const d = await login(phone(prefix));
  await onboardDriver(d.token, 'economy');
  const sock = await connect(d.token);
  sock.emit('driver:status', { status: 'online' });
  await wait(300);
  sock.emit('driver:location', { lat: pickup.lat + offsetLat, lng: pickup.lng, heading: 0, speed: 0 });
  await wait(300);
  return { ...d, id: d.user.id, sock };
}

async function main() {
  const tired = await onlineDriver('81', 0.0005); // ~55 m from the pickup
  const fresh = await onlineDriver('82', 0.003); // ~330 m
  // The tired driver has been online 12 h (this session included).
  redis('HSET', `driver:${tired.id}:fatigue`, 'acc', 12 * H);
  const f = await api('/drivers/me/fatigue', { token: tired.token });
  console.log(`1. tired driver: online ${Math.round(f.onlineSeconds / 60)} min of ${f.limitSeconds / H} h, overLimit=${f.overLimit}`);
  assert(f.overLimit, 'GET /drivers/me/fatigue reports over the limit');

  const offered = { tired: [], fresh: [] };
  tired.sock.on('trip:offer', (o) => offered.tired.push(o.tripId));
  fresh.sock.on('trip:offer', (o) => offered.fresh.push(o.tripId));
  const rider = await login(phone('83'));
  const rSock = await connect(rider.token);
  const acceptedP = once(rSock, 'trip:accepted', 30000);
  const trip = await api('/trips', {
    method: 'POST',
    token: rider.token,
    body: {
      pickupLat: pickup.lat, pickupLng: pickup.lng,
      dropoffLat: dropoff.lat, dropoffLng: dropoff.lng,
      tier: 'economy', paymentMode: 'cash',
    },
  });
  // Accept only our trip, from the fresh driver.
  for (let i = 0; i < 60 && !offered.fresh.includes(trip.id); i++) await wait(250);
  assert(offered.fresh.includes(trip.id), 'the rested driver (farther away) is offered the trip');
  assert(!offered.tired.includes(trip.id), 'the tired driver (nearer) is NOT offered it');
  fresh.sock.emit('trip:accept', { tripId: trip.id });
  await acceptedP;
  console.log(`   trip ${trip.id.slice(0, 8)} accepted by the rested driver`);
  // Clean up the ride so the fresh driver is free again.
  await api(`/trips/${trip.id}/cancel`, { method: 'POST', token: rider.token, body: {}, expectError: true });

  console.log('2. waiting for the fatigue sweep (<= 35 s)…');
  const statusP = new Promise((resolve) => {
    tired.sock.on('driver:status_changed', (d) => d.reason === 'fatigue' && resolve(d));
  });
  const lockedP = once(tired.sock, 'driver:fatigue_locked', 40000);
  const locked = await lockedP;
  const status = await Promise.race([statusP, wait(2000).then(() => null)]);
  assert(status?.status === 'offline', "driver:status_changed {offline, reason:'fatigue'}");
  assert(locked.resting && locked.restSecondsLeft > 5 * H, `driver:fatigue_locked: resting, ${Math.round(locked.restSecondsLeft / 60)} min of rest left`);
  assert(redis('GET', `driver:${tired.id}:status`) === 'offline', 'server presence is offline');

  const res = await fetch(`${BASE}/drivers/status`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${tired.token}` },
    body: JSON.stringify({ status: 'online' }),
  });
  const body = await res.json();
  console.log(`3. going online -> ${res.status} ${body.code}: "${body.message}"`);
  assert(res.status === 409 && body.code === 'DRIVER_REST_REQUIRED', '409 DRIVER_REST_REQUIRED');
  assert(body.restSecondsLeft > 5 * H && typeof body.restUntil === 'string', `restSecondsLeft ${body.restSecondsLeft}, restUntil ${body.restUntil}`);

  // 4. Warning 30 min before the limit.
  const near = await onlineDriver('84', 0.01);
  redis('HSET', `driver:${near.id}:fatigue`, 'acc', 11 * H + 40 * 60);
  console.log('4. waiting for the warning (<= 35 s)…');
  const warning = await once(near.sock, 'driver:fatigue_warning', 40000);
  assert(warning.remainingSeconds <= 20 * 60 && !warning.overLimit, `driver:fatigue_warning with ${Math.round(warning.remainingSeconds / 60)} min left`);

  for (const d of [fresh, near]) {
    d.sock.emit('driver:status', { status: 'offline' });
  }
  await wait(300);
  for (const s of [tired.sock, fresh.sock, near.sock, rSock]) s.close();
  console.log('\nFATIGUE CHECK PASSED');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
