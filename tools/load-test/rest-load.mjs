// REST hot-path load test. N virtual users hammer /trips/estimate (the most
// frequently called compute+IO endpoint — every "where to?" triggers one) for
// a fixed duration. Reports throughput + latency percentiles + error rate and
// exits non-zero if it breaches the SLOs, so it can gate a release.
//
//   CONC=100 DURATION_S=30 node rest-load.mjs
import { api, login, phone, printStats, stats, runPool, wait } from './lib.mjs';

const CONC = Number(process.env.CONC || 75);
const DURATION_S = Number(process.env.DURATION_S || 20);
const P95_SLO_MS = Number(process.env.P95_SLO_MS || 600);
const ERR_SLO = Number(process.env.ERR_SLO || 0.01);

const pickup = { lat: 12.9611, lng: 77.6387 };
const dropoff = { lat: 12.9674, lng: 77.5904 };

async function main() {
  console.log(
    `\n== REST load == ${CONC} VUs × ${DURATION_S}s  ` +
      `(SLO: p95<${P95_SLO_MS}ms, errors<${(ERR_SLO * 100).toFixed(1)}%)\n`,
  );

  process.stdout.write(`Logging in ${CONC} users… `);
  const tokens = new Array(CONC);
  await runPool({
    conc: Math.min(CONC, 25),
    total: CONC,
    task: async (i) => {
      tokens[i] = (await login(phone())).token;
    },
  });
  console.log('done.');

  const latencies = [];
  let ok = 0;
  let err = 0;
  const errByCode = {};
  const deadline = Date.now() + DURATION_S * 1000;

  const vu = async (wid) => {
    const token = tokens[wid];
    while (Date.now() < deadline) {
      const t = Date.now();
      try {
        await api('/trips/estimate', {
          method: 'POST',
          token,
          body: {
            pickupLat: pickup.lat,
            pickupLng: pickup.lng,
            dropoffLat: dropoff.lat,
            dropoffLng: dropoff.lng,
          },
        });
        latencies.push(Date.now() - t);
        ok += 1;
      } catch (e) {
        err += 1;
        const code = e.status || 'net';
        errByCode[code] = (errByCode[code] || 0) + 1;
      }
    }
  };

  const started = Date.now();
  await Promise.all(Array.from({ length: CONC }, (_, w) => vu(w)));
  const elapsed = (Date.now() - started) / 1000;

  const total = ok + err;
  const rps = total / elapsed;
  const errorRate = total ? err / total : 0;

  console.log(`\nResults (${elapsed.toFixed(1)}s):`);
  console.log(`  requests        ${total}   (${ok} ok, ${err} errors)`);
  console.log(`  throughput      ${rps.toFixed(0)} req/s`);
  console.log(`  error rate      ${(errorRate * 100).toFixed(2)}%` +
    (err ? `  ${JSON.stringify(errByCode)}` : ''));
  printStats('estimate', latencies);

  const s = stats(latencies);
  const pass = s.p95 <= P95_SLO_MS && errorRate <= ERR_SLO;
  console.log(
    `\n${pass ? 'PASS ✓' : 'FAIL ✗'}  p95=${s.p95}ms (SLO ${P95_SLO_MS}) ` +
      `errors=${(errorRate * 100).toFixed(2)}% (SLO ${(ERR_SLO * 100).toFixed(1)}%)\n`,
  );
  await wait(200);
  process.exit(pass ? 0 : 1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
