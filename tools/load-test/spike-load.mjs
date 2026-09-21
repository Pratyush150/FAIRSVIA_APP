// Burst / thundering-herd capacity test. Unlike ride-load (which paces rides
// through a fixed pool of concurrent workers, i.e. steady-state throughput),
// this fires a whole WAVE of ride requests SIMULTANEOUSLY — every rider in the
// batch calls POST /trips at once. That is the demand profile of a real spike:
// a concert lets out, a storm starts, surge kicks in. It stresses a different
// axis than throughput — the dispatch queue depth, per-driver offer locking,
// and Redis GEO contention when hundreds of matches are contended at the same
// instant.
//
// Runs one or more waves and reports, per wave, how many riders matched, the
// match-latency spread under contention, and unmatched/error counts. Exits
// non-zero on SLO breach.
//
//   DRIVERS=250 WAVE=200 WAVES=3 node spike-load.mjs
import {
  api, login, connect, onboardDriver, phone, printStats, stats, wait,
} from './lib.mjs';

const DRIVERS = Number(process.env.DRIVERS || 200);
const WAVE = Number(process.env.WAVE || 150); // riders firing at once per wave
const WAVES = Number(process.env.WAVES || 3);
const GAP_MS = Number(process.env.GAP_MS || 2000); // pause between waves
const MATCH_TIMEOUT = Number(process.env.MATCH_TIMEOUT_MS || 25000);
// A synchronized herd is more contended than steady-state, so the p95 bar is a
// touch wider — but with dead-socket drivers correctly evicted from the pool the
// system matches a full wave in ~1s, so we hold a tight success bar.
const MATCH_SUCCESS_SLO = Number(process.env.MATCH_SUCCESS_SLO || 0.97);
const MATCH_P95_SLO = Number(process.env.MATCH_P95_SLO_MS || 4000);

const CENTER = { lat: 25.7743, lng: -80.1937 };
const jitter = () => (Math.random() - 0.5) * 0.02; // ~1km spread
const drivers = new Map();

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
  await Promise.all(
    Array.from({ length: DRIVERS }, async () => {
      const d = await login(phone());
      await onboardDriver(d.token, 'economy');
      const socket = await connect(d.token);
      // Auto-accept the first offer they see; drivers rejoin the pool between
      // waves via the location heartbeat.
      socket.on('trip:offer', (o) => socket.emit('trip:accept', { tripId: o.tripId }));
      const entry = { token: d.token, socket };
      drivers.set(d.user.id, entry);
      goOnline(entry);
    }),
  );
  console.log(`${DRIVERS} online.`);
  return setInterval(() => {
    for (const d of drivers.values()) {
      d.socket.emit('driver:location', {
        lat: CENTER.lat + jitter(),
        lng: CENTER.lng + jitter(),
      });
    }
  }, 1000);
}

async function connectRiders(n) {
  process.stdout.write(`Connecting ${n} riders… `);
  const riders = await Promise.all(
    Array.from({ length: n }, async () => {
      const r = await login(phone());
      const socket = await connect(r.token);
      return { token: r.token, socket };
    }),
  );
  console.log('done.');
  return riders;
}

// Fire all WAVE ride requests at the same instant and wait for each to resolve.
async function runWave(riders, waveNo) {
  const matchMs = [];
  let matched = 0;
  let noDrivers = 0;
  let timedOut = 0;
  let errors = 0;
  let stuck = 0;

  // Riders are reused across waves, and the backend allows one live trip per
  // rider. A ride left in flight therefore makes that rider 409 on every
  // later wave, which looks exactly like wave-over-wave dispatch decay. Cancel
  // on every path that doesn't reach `complete`.
  const releaseRider = async (rider, tripId) => {
    if (!tripId) return;
    try {
      await api(`/trips/${tripId}/cancel`, {
        method: 'POST',
        token: rider.token,
        body: { reason: 'load-test cleanup' },
      });
    } catch {
      stuck += 1;
    }
  };

  const fireOne = async (rider) => {
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
          tier: 'economy', pickupAddr: 'Spike', dropoffAddr: 'Test',
        },
      });
    } catch {
      errors += 1;
      return;
    }
    const res = await matchP;
    if (res.type === 'timeout') {
      timedOut += 1;
      await releaseRider(rider, trip.id);
      return;
    }
    if (res.type === 'no_drivers') {
      noDrivers += 1;
      await releaseRider(rider, trip.id);
      return;
    }
    matched += 1;
    matchMs.push(Date.now() - t0);
    // Complete the ride so its driver returns to the pool for the next wave.
    const d = drivers.get(res.data.driver.id);
    if (!d) {
      await releaseRider(rider, trip.id);
      return;
    }
    let done = false;
    try {
      // Drive the driver to the pickup first — the backend enforces a 150 m
      // arrival geofence, so a driver parked where they spawned is refused.
      d.socket.emit('driver:location', { lat: pickup.lat, lng: pickup.lng });
      const view = await api(`/trips/${trip.id}`, { token: rider.token });
      await wait(100);
      try {
        await api(`/trips/${trip.id}/arrived`, { method: 'POST', token: d.token });
      } catch (e) {
        // Pickup fix can lose a write race against the pool-return location;
        // re-send and tap again, as a real driver app would.
        if (e.status !== 400) throw e;
        d.socket.emit('driver:location', { lat: pickup.lat, lng: pickup.lng });
        await wait(250);
        await api(`/trips/${trip.id}/arrived`, { method: 'POST', token: d.token });
      }
      await api(`/trips/${trip.id}/start`, {
        method: 'POST', token: d.token, body: { otp: view.startOtp },
      });
      await api(`/trips/${trip.id}/complete`, { method: 'POST', token: d.token });
      done = true;
    } catch {
      // matched already counted; completion errors are reported separately
      errors += 1;
    } finally {
      goOnline(d);
    }
    if (!done) await releaseRider(rider, trip.id);
  };

  const started = Date.now();
  // The crux: no worker pool, no pacing — every rider fires at once.
  await Promise.all(riders.map((r) => fireOne(r)));
  const elapsed = (Date.now() - started) / 1000;

  const attempted = riders.length;
  const successRate = matched / attempted;
  console.log(
    `\n  wave ${waveNo}: ${matched}/${attempted} matched ` +
      `(${(successRate * 100).toFixed(1)}%)  ` +
      `noDrivers=${noDrivers} timedOut=${timedOut} errors=${errors} ` +
      `stuck=${stuck}  ` +
      `in ${elapsed.toFixed(1)}s`,
  );
  printStats(`  wave ${waveNo} match`, matchMs);
  return { matchMs, matched, attempted, noDrivers, timedOut, errors };
}

async function main() {
  console.log(
    `\n== Spike load == ${DRIVERS} drivers, ${WAVES} wave(s) of ${WAVE} ` +
      `simultaneous requests\n` +
      `   (SLO: match success ≥${(MATCH_SUCCESS_SLO * 100).toFixed(0)}%, ` +
      `match p95 <${MATCH_P95_SLO}ms)\n`,
  );

  const locTimer = await setupDrivers();
  const riders = await connectRiders(WAVE);
  await wait(1500); // let presence settle

  const allMatch = [];
  let totalMatched = 0;
  let totalAttempted = 0;
  let totalUnmatched = 0;
  let totalErrors = 0;

  for (let w = 1; w <= WAVES; w += 1) {
    const r = await runWave(riders, w);
    allMatch.push(...r.matchMs);
    totalMatched += r.matched;
    totalAttempted += r.attempted;
    totalUnmatched += r.noDrivers + r.timedOut;
    totalErrors += r.errors;
    if (w < WAVES) {
      await wait(GAP_MS); // let the fleet re-pool before the next surge
    }
  }

  clearInterval(locTimer);

  const successRate = totalMatched / totalAttempted;
  const mp95 = stats(allMatch).p95;
  console.log(`\nTotals across ${WAVES} wave(s):`);
  console.log(`  requests fired    ${totalAttempted}`);
  console.log(`  matched           ${totalMatched}  (${(successRate * 100).toFixed(1)}%)`);
  console.log(`  unmatched         ${totalUnmatched}`);
  console.log(`  errors            ${totalErrors}`);
  printStats('match latency', allMatch);

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
