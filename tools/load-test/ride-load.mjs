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

const CENTER = { lat: 12.9611, lng: 77.6387 };
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
  let cursor = 0;

  const runOneRide = async (rider) => {
    const t0 = Date.now();
    const matchP = awaitMatch(rider.socket, MATCH_TIMEOUT);
    let trip;
    try {
      trip = await api('/trips', {
        method: 'POST',
        token: rider.token,
        body: {
          pickupLat: CENTER.lat + jitter(),
          pickupLng: CENTER.lng + jitter(),
          dropoffLat: 12.9674, dropoffLng: 77.5904,
          tier: 'economy', pickupAddr: 'Load', dropoffAddr: 'Test',
        },
      });
    } catch {
      errors += 1;
      return;
    }

    const res = await matchP;
    if (res.type === 'timeout') { timedOut += 1; return; }
    if (res.type === 'no_drivers') { noDrivers += 1; return; }

    matched += 1;
    matchMs.push(Date.now() - t0);
    const d = drivers.get(res.data.driver.id);
    if (!d) return; // matched to an unknown driver (shouldn't happen)

    try {
      const view = await api(`/trips/${trip.id}`, { token: rider.token });
      await api(`/trips/${trip.id}/arrived`, { method: 'POST', token: d.token });
      await api(`/trips/${trip.id}/start`, {
        method: 'POST', token: d.token, body: { otp: view.startOtp },
      });
      await api(`/trips/${trip.id}/complete`, { method: 'POST', token: d.token });
      completed += 1;
      e2eMs.push(Date.now() - t0);
      goOnline(d); // return the driver to the pool
    } catch {
      errors += 1;
      goOnline(d);
    }
  };

  const worker = async (rider) => {
    for (;;) {
      const i = cursor++;
      if (i >= RIDES) return;
      await runOneRide(rider);
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
