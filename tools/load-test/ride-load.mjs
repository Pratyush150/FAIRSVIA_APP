// Realistic capacity test: a fleet of drivers online (streaming GPS + auto-
// accepting offers) while many riders request and complete full rides
// concurrently. This exercises the whole hot path — auth, WebSockets, Redis
// GEO, the BullMQ dispatch queue, the trip state machine, and payments.
//
// Reports match-latency + end-to-end percentiles, match success rate, and
// completed-ride throughput, and exits non-zero on SLO breach.
//
//   DRIVERS=100 CONC=40 RIDES=400 node ride-load.mjs
import {
  api, login, connect, onboardDriver, phone, printStats, stats, wait,
} from './lib.mjs';

const DRIVERS = Number(process.env.DRIVERS || 60);
const CONC = Number(process.env.CONC || 25);
const RIDES = Number(process.env.RIDES || 150);
const MATCH_TIMEOUT = Number(process.env.MATCH_TIMEOUT_MS || 20000);
const MATCH_SUCCESS_SLO = Number(process.env.MATCH_SUCCESS_SLO || 0.95);
const MATCH_P95_SLO = Number(process.env.MATCH_P95_SLO_MS || 4000);

const CENTER = { lat: 25.7743, lng: -80.1937 };
const jitter = () => (Math.random() - 0.5) * 0.01; // ~0.5km
const drivers = new Map(); // userId -> { token, socket }

function awaitMatch(socket, timeoutMs) {
  return new Promise((resolve) => {
    const t = setTimeout(() => { cleanup(); resolve({ type: 'timeout' }); }, timeoutMs);
    const onA = (d) => { cleanup(); resolve({ type: 'accepted', data: d }); };
    const onN = () => { cleanup(); resolve({ type: 'no_drivers' }); };
    function cleanup() {
      clearTimeout(t);
      socket.off('trip:accepted', onA);
      socket.off('trip:no_drivers', onN);
    }
    socket.on('trip:accepted', onA);
    socket.on('trip:no_drivers', onN);
  });
}

function goOnline(d) {
  d.socket.emit('driver:status', { status: 'online' });
  d.socket.emit('driver:location', {
    lat: CENTER.lat + jitter(),
    lng: CENTER.lng + jitter(),
  });
}

async function setupDrivers() {
  process.stdout.write(`Bringing ${DRIVERS} drivers online… `);
  let ready = 0;
  await Promise.all(
    Array.from({ length: DRIVERS }, async () => {
      const d = await login(phone());
      await onboardDriver(d.token, 'economy');
      const socket = await connect(d.token);
      socket.on('trip:offer', (o) => socket.emit('trip:accept', { tripId: o.tripId }));
      const entry = { token: d.token, socket };
      drivers.set(d.user.id, entry);
      goOnline(entry);
      ready += 1;
    }),
  );
  console.log(`${ready} online.`);
  // Keep the fleet in the geo index + re-pool completed drivers.
  return setInterval(() => {
    for (const d of drivers.values()) {
      d.socket.emit('driver:location', {
        lat: CENTER.lat + jitter(),
        lng: CENTER.lng + jitter(),
      });
    }
  }, 1000);
}

async function main() {
  console.log(
    `\n== Ride load == ${DRIVERS} drivers, ${RIDES} rides, ${CONC} concurrent\n` +
      `   (SLO: match success ≥${(MATCH_SUCCESS_SLO * 100).toFixed(0)}%, ` +
      `match p95 <${MATCH_P95_SLO}ms)\n`,
  );

  const locTimer = await setupDrivers();

  process.stdout.write(`Connecting ${CONC} riders… `);
  const riders = await Promise.all(
    Array.from({ length: CONC }, async () => {
      const r = await login(phone());
      const socket = await connect(r.token);
      return { token: r.token, socket };
    }),
  );
  console.log('done.');
  await wait(1500); // let presence settle

  const matchMs = [];
  const e2eMs = [];
  let matched = 0;
  let completed = 0;
  let noDrivers = 0;
  let timedOut = 0;
  let errors = 0;
  let stuckRiders = 0;
  const errSamples = new Map(); // "status body" -> count
  let cursor = 0;

  // A rider may only hold one live trip (the backend refuses a second with
  // 409). Any path that leaves this ride in flight therefore has to cancel it,
  // or that rider spends the rest of the run instantly 409-ing and burns the
  // whole ride queue. Returns false when the trip could not be released —
  // `in_progress` is past the rider-cancellable window, so that rider retires.
  const releaseRider = async (rider, tripId) => {
    if (!tripId) return true;
    try {
      await api(`/trips/${tripId}/cancel`, {
        method: 'POST',
        token: rider.token,
        body: { reason: 'load-test cleanup' },
      });
      return true;
    } catch {
      return false;
    }
  };

  // Resolves to 'ok' (rider is free for another ride) or 'stuck' (rider still
  // holds a live trip and must be retired from the pool).
  const runOneRide = async (rider) => {
    const t0 = Date.now();
    const matchP = awaitMatch(rider.socket, MATCH_TIMEOUT);
    const pickup = { lat: CENTER.lat + jitter(), lng: CENTER.lng + jitter() };
    let trip;
    try {
      trip = await api('/trips', {
        method: 'POST',
        token: rider.token,
        body: {
          pickupLat: pickup.lat,
          pickupLng: pickup.lng,
          dropoffLat: 25.7806, dropoffLng: -80.2420,
          tier: 'economy', pickupAddr: 'Load', dropoffAddr: 'Test',
        },
      });
    } catch {
      errors += 1;
      // The create itself failed, so there is nothing of ours in flight.
      return 'ok';
    }

    const res = await matchP;
    if (res.type === 'timeout') {
      timedOut += 1;
      return (await releaseRider(rider, trip.id)) ? 'ok' : 'stuck';
    }
    if (res.type === 'no_drivers') {
      noDrivers += 1;
      return (await releaseRider(rider, trip.id)) ? 'ok' : 'stuck';
    }

    matched += 1;
    matchMs.push(Date.now() - t0);
    const d = drivers.get(res.data.driver.id);
    if (!d) {
      // Matched to a driver we don't own (shouldn't happen) — we can't drive
      // this ride to completion, so hand the trip back rather than orphan it.
      return (await releaseRider(rider, trip.id)) ? 'ok' : 'stuck';
    }

    try {
      // Drive the matched driver to the pickup before they mark arrived. The
      // backend enforces a 150 m arrival geofence (assertNearPickup), so a
      // driver sitting wherever they spawned would be legitimately refused —
      // a real driver drives to the rider first. The GET below gives the fix
      // time to land in Redis, plus a small margin under load.
      d.socket.emit('driver:location', { lat: pickup.lat, lng: pickup.lng });
      const view = await api(`/trips/${trip.id}`, { token: rider.token });
      await wait(100);
      try {
        await api(`/trips/${trip.id}/arrived`, { method: 'POST', token: d.token });
      } catch (e) {
        // The driver's pickup fix can lose a write race against the location
        // this driver emitted when it was returned to the pool (the gateway
        // does not serialize async handlers), leaving the stored position at
        // the old spot. Re-send the fix and tap again — what a real driver
        // app does when the geofence refuses the first tap.
        if (e.status !== 400) throw e;
        d.socket.emit('driver:location', { lat: pickup.lat, lng: pickup.lng });
        await wait(250);
        await api(`/trips/${trip.id}/arrived`, { method: 'POST', token: d.token });
      }
      await api(`/trips/${trip.id}/start`, {
        method: 'POST', token: d.token, body: { otp: view.startOtp },
      });
      await api(`/trips/${trip.id}/complete`, { method: 'POST', token: d.token });
      completed += 1;
      e2eMs.push(Date.now() - t0);
      goOnline(d); // return the driver to the pool
      return 'ok';
    } catch (e) {
      errors += 1;
      // Keep a tally of *why* rides fail — a bare count can't tell a backend
      // fault from the harness driving the flow wrong.
      const key = `${e.status || 'net'} ${String(e.bodyText || e.message).slice(0, 120)}`;
      errSamples.set(key, (errSamples.get(key) || 0) + 1);
      goOnline(d);
      return (await releaseRider(rider, trip.id)) ? 'ok' : 'stuck';
    }
  };

  const worker = async (rider) => {
    for (;;) {
      const i = cursor++;
      if (i >= RIDES) return;
      const outcome = await runOneRide(rider);
      if (outcome === 'stuck') {
        // This rider can no longer start a ride; retire it instead of letting
        // it spin through the remaining queue on instant 409s.
        stuckRiders += 1;
        return;
      }
      if ((matched + noDrivers + timedOut) % 25 === 0) {
        process.stdout.write(
          `\r  progress: ${completed} completed / ${matched} matched / ` +
            `${noDrivers + timedOut} unmatched   `,
        );
      }
    }
  };

  const started = Date.now();
  await Promise.all(riders.map((r) => worker(r)));
  const elapsed = (Date.now() - started) / 1000;

  clearInterval(locTimer);

  const attempted = RIDES;
  const successRate = matched / attempted;
  const throughput = completed / elapsed;

  console.log(`\n\nResults (${elapsed.toFixed(1)}s):`);
  console.log(`  rides attempted   ${attempted}`);
  console.log(`  matched           ${matched}  (${(successRate * 100).toFixed(1)}%)`);
  console.log(`  completed         ${completed}`);
  console.log(`  no-drivers        ${noDrivers}`);
  console.log(`  timed-out         ${timedOut}`);
  console.log(`  errors            ${errors}`);
  console.log(`  riders retired    ${stuckRiders}`);
  if (errSamples.size > 0) {
    console.log('  failure breakdown:');
    for (const [k, v] of [...errSamples].sort((a, b) => b[1] - a[1]).slice(0, 5)) {
      console.log(`    ${String(v).padStart(4)} x  ${k}`);
    }
  }
  console.log(`  throughput        ${throughput.toFixed(1)} completed rides/s`);
  printStats('match latency', matchMs);
  printStats('end-to-end', e2eMs);

  const mp95 = stats(matchMs).p95;
  const pass = successRate >= MATCH_SUCCESS_SLO && mp95 <= MATCH_P95_SLO;
  console.log(
    `\n${pass ? 'PASS ✓' : 'FAIL ✗'}  match success=${(successRate * 100).toFixed(1)}% ` +
      `(SLO ${(MATCH_SUCCESS_SLO * 100).toFixed(0)}%)  match p95=${mp95}ms (SLO ${MATCH_P95_SLO})\n`,
  );

  for (const d of drivers.values()) d.socket.close();
  for (const r of riders) r.socket.close();
  await wait(300);
  process.exit(pass ? 0 : 1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
