// Driver tools from docs/plans/driver-app-benchmark.md, driven end-to-end
// against the running backend over Socket.IO + REST:
//   1. Rider no-show: driver arrives, a no-show cancel is refused before the
//      wait (server clock), then — with the trip's arrival backdated past the
//      wait — accepted; the rider is charged the cancellation fee and both
//      apps get trip:cancelled {noShow:true, fee}.
//   2. Busy areas: ride requests in one ~1 km cell show up on
//      GET /drivers/me/demand as a shaded cell; nothing reveals a lone pickup.
//   3. Earnings dashboard: 7 daily buckets, online time from the session.
// Requires the backend running (and the ubernav_postgres / ubernav_redis
// containers for the backdate + cache flush). Run: node driver-tools-check.mjs
import { execSync } from 'node:child_process';
import { BASE, api, connect, login, once, onboardDriver, phone, wait } from './lib.mjs';

function assert(cond, msg) {
  if (!cond) throw new Error('ASSERT FAILED: ' + msg);
}

// A Pune street corner (the pilot market); the demand grid is 0.01°.
const pickup = { lat: 18.5602, lng: 73.7769 }; // mid-cell, so the +-0.002 offsets stay in it
const dropoff = { lat: 18.5204, lng: 73.8567 };

const psql = (sql) =>
  execSync(`docker exec ubernav_postgres psql -U ubernav -d ubernav -tAc "${sql}"`).toString().trim();

async function main() {
  const driver = await login(phone('93'));
  await onboardDriver(driver.token, 'economy');
  const dSock = await connect(driver.token);
  dSock.emit('driver:status', { status: 'online' });
  await wait(300);
  dSock.emit('driver:location', { lat: pickup.lat + 0.001, lng: pickup.lng, heading: 0, speed: 0 });
  await wait(400);

  // --- 1. Rider no-show ---
  const rider = await login(phone('94'));
  const rSock = await connect(rider.token);
  // Only accept OUR rider's trip; anything else offered (a stray request in
  // the area) is declined.
  let trip;
  const earlyOffers = [];
  let handle;
  const offerP = new Promise((resolve) => {
    handle = (o) => {
      if (!trip) return earlyOffers.push(o); // arrived before POST /trips returned
      if (o.tripId === trip.id) resolve(o);
      else dSock.emit('trip:decline', { tripId: o.tripId });
    };
    dSock.on('trip:offer', (o) => handle(o));
  });
  const acceptedP = once(rSock, 'trip:accepted');
  trip = await api('/trips', {
    method: 'POST',
    token: rider.token,
    body: {
      pickupLat: pickup.lat, pickupLng: pickup.lng,
      dropoffLat: dropoff.lat, dropoffLng: dropoff.lng,
      tier: 'economy', paymentMode: 'cash',
    },
  });
  earlyOffers.splice(0).forEach((o) => handle(o));
  const offer = await offerP;
  console.log(`1. offer ${offer.tripId.slice(0, 8)}: fare ${offer.fare}, rider ${offer.rider?.name ?? '-'} ${offer.rider?.rating ?? ''}`);
  dSock.emit('trip:accept', { tripId: offer.tripId });
  await acceptedP;
  dSock.emit('driver:location', { lat: pickup.lat, lng: pickup.lng, heading: 0, speed: 0 });
  await wait(300);
  await api(`/trips/${trip.id}/arrived`, { method: 'POST', token: driver.token });
  const view = await api(`/trips/${trip.id}`, { token: driver.token });
  assert(view.arrivedAt, 'trip carries arrivedAt for the timer');
  assert(view.noShowWaitSec > 0, 'trip carries noShowWaitSec');
  console.log(`   arrived; wait ${view.noShowWaitSec}s, fee ${view.cancellationFee}`);

  const early = await fetch(`${BASE}/trips/${trip.id}/driver-cancel`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${driver.token}` },
    body: JSON.stringify({ reason: "Rider didn't show up", noShow: true }),
  });
  const earlyBody = await early.json();
  assert(early.status === 400 && earlyBody.code === 'NO_SHOW_TOO_EARLY', 'early no-show refused');
  console.log(`   no-show at once -> 400 ${earlyBody.code}, ${earlyBody.secondsLeft}s left`);

  // Stand in for the real wait: move the server's arrival stamp back.
  psql(`UPDATE trips SET arrived_at = now() - interval '${view.noShowWaitSec + 5} seconds' WHERE id = '${trip.id}'`);
  const riderToldP = once(rSock, 'trip:cancelled');
  const res = await api(`/trips/${trip.id}/driver-cancel`, {
    method: 'POST', token: driver.token,
    body: { reason: "Rider didn't show up", noShow: true },
  });
  const told = await riderToldP;
  assert(res.status === 'cancelled' && res.fee > 0, 'no-show cancelled with a fee');
  assert(told.noShow === true && told.fee === res.fee, 'rider told it was a no-show with the fee');
  const pay = psql(`SELECT kind || ' ' || amount || ' ' || driver_payout FROM payments WHERE trip_id = '${trip.id}'`);
  console.log(`   after the wait -> cancelled, fee ${res.fee}; payment row: ${pay}; rider got trip:cancelled ${JSON.stringify(told)}`);

  // --- 2. Busy areas ---
  // Two more riders request from the same cell and cancel (unmet demand is
  // still demand); one lone request elsewhere must not show.
  for (const tag of ['95', '96']) {
    const r = await login(phone(tag));
    const t = await api('/trips', {
      method: 'POST', token: r.token,
      body: {
        pickupLat: pickup.lat + 0.002, pickupLng: pickup.lng - 0.001,
        dropoffLat: dropoff.lat, dropoffLng: dropoff.lng,
        tier: 'economy', paymentMode: 'cash',
      },
    });
    // A cancel can race dispatch's requested→matching step (409); retry.
    let cancelled = false;
    for (let i = 0; i < 10 && !cancelled; i++) {
      const c = await api(`/trips/${t.id}/cancel`, { method: 'POST', token: r.token, body: {}, expectError: true });
      cancelled = c?.status === 'cancelled';
      if (!cancelled) await wait(500);
    }
    assert(cancelled, `demand request ${t.id.slice(0, 8)} cancelled`);
  }
  execSync(`docker exec ubernav_redis sh -c "redis-cli --scan --pattern 'demand:map:*' | xargs -r redis-cli del"`);
  const demand = await api(`/drivers/me/demand?lat=${pickup.lat}&lng=${pickup.lng}`, { token: driver.token });
  const cell = demand.cells.find(
    (c) => Math.abs(c.lat - Math.round(pickup.lat / 0.01) * 0.01) < 1e-6 &&
      Math.abs(c.lng - Math.round(pickup.lng / 0.01) * 0.01) < 1e-6,
  );
  assert(cell && cell.count >= 3, 'the pickup cell is shaded with the 3 requests');
  assert(demand.cells.every((c) => c.count >= 2), 'no lone request is shown');
  console.log(`2. busy areas (last ${demand.windowMinutes} min): ${demand.cells.length} cell(s); pickup cell count ${cell.count}, intensity ${cell.intensity}`);

  // --- 3. Earnings dashboard ---
  await wait(1500);
  const week = await api('/drivers/me/earnings?range=week', { token: driver.token });
  const today = await api('/drivers/me/earnings?range=today', { token: driver.token });
  assert(week.days.length === 7, '7 daily buckets');
  assert(today.onlineSeconds >= 1, 'online time counted from the open session');
  console.log(
    `3. earnings: today ${today.total} (${today.trips} trips, online ${today.onlineSeconds}s, ` +
      `fees ${today.cancellationFees}); week buckets ${week.days.map((d) => d.total).join('/')}`,
  );
  console.log('   (a cash no-show fee is booked pending until collected, so it is not yet in the total — by design)');

  dSock.emit('driver:status', { status: 'offline' });
  await wait(300);
  for (const s of [dSock, rSock]) s.close();
  console.log('\nDRIVER TOOLS CHECK PASSED');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
