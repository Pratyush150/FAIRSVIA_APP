// Scenario orchestrator. Brings a driver fleet online (with ramp-up), then
// drives rider demand through one of three arrival models:
//   - open:   Poisson arrivals at a target rate for a duration (realistic demand)
//   - closed: a fixed pool of riders doing back-to-back rides with think-time
//   - batch:  synchronized waves of simultaneous requests (thundering herd)
// All actors report into one shared Metrics instance.

import { Driver } from './driver.mjs';
import { Rider } from './rider.mjs';
import { wait } from './client.mjs';
import { setRegion, setTierWeights, assignTiers } from './geo.mjs';

export class Orchestrator {
  constructor(scenario, metrics) {
    this.s = scenario;
    this.m = metrics;
    this.drivers = [];
    this.inflight = 0;
  }

  async run() {
    setRegion(this.s.region);
    if (this.s.tiers) setTierWeights(this.s.tiers);
    await this.rampDrivers();
    // Small settle so all drivers are in the GEO index before demand starts.
    await wait(1500);
    const a = this.s.arrivals;
    if (a.model === 'open') await this.runOpen(a);
    else if (a.model === 'closed') await this.runClosed(a);
    else if (a.model === 'batch') await this.runBatch(a);
    else throw new Error(`unknown arrival model: ${a.model}`);
    // Let any in-flight rides finish before we tear down.
    await this.drain();
    await this.teardown();
  }

  async rampDrivers() {
    const n = this.s.drivers;
    const stepMs = n > 1 ? (this.s.driverRampMs || 0) / n : 0;
    // Guarantee per-tier supply coverage instead of leaving it to chance.
    const tiers = assignTiers(n);
    this.log(`fleet tier mix: ${summarizeTiers(tiers)}`);
    const tasks = [];
    for (let i = 0; i < n; i++) {
      tasks.push(
        (async () => {
          await wait(i * stepMs);
          const d = new Driver(this.m, { ...this.s.driverBehavior, tier: tiers[i] });
          try {
            await d.setup();
            this.drivers.push(d);
          } catch (e) {
            this.m.error('orchestrator', 'driver_setup', e);
          }
        })(),
      );
    }
    await Promise.all(tasks);
    this.log(`fleet online: ${this.drivers.length}/${n} drivers`);
  }

  async runOpen({ ratePerSec, durationS, maxInflight = 400 }) {
    const endAt = Date.now() + durationS * 1000;
    const meanGapMs = 1000 / ratePerSec;
    let launched = 0;
    while (Date.now() < endAt) {
      if (this.inflight < maxInflight) {
        this.launchRider();
        launched++;
      }
      // Exponential inter-arrival (Poisson process).
      const gap = -Math.log(1 - Math.random()) * meanGapMs;
      await wait(Math.max(1, gap));
    }
    this.log(`open arrivals done: launched ${launched} riders over ${durationS}s`);
  }

  async runClosed({ pool, rides, durationS, thinkMs = 1500 }) {
    const endAt = durationS ? Date.now() + durationS * 1000 : Infinity;
    let remaining = rides || Infinity;
    const worker = async () => {
      for (;;) {
        if (Date.now() >= endAt || remaining <= 0) return;
        remaining -= 1;
        await this.oneRide();
        await wait(thinkMs + Math.random() * thinkMs);
      }
    };
    await Promise.all(Array.from({ length: pool }, () => worker()));
    this.log(`closed load done: pool=${pool}`);
  }

  async runBatch({ waveSize, waves, gapMs }) {
    for (let w = 0; w < waves; w++) {
      this.log(`wave ${w + 1}/${waves}: firing ${waveSize} simultaneous requests`);
      // launchRider() tracks each ride in `this.inflight`, so the subsequent
      // drain() actually waits for the herd to finish instead of tearing down
      // sockets mid-trip (which would truncate match/completion metrics).
      for (let i = 0; i < waveSize; i++) this.launchRider();
      if (w < waves - 1) await wait(gapMs);
    }
  }

  /** Fire-and-forget a rider (open/batch models). */
  launchRider() {
    this.inflight++;
    this.oneRide().finally(() => { this.inflight--; });
  }

  /** One rider lifecycle: setup → ride → teardown, fully guarded. */
  async oneRide() {
    const r = new Rider(this.m, this.s.riderBehavior);
    try {
      await r.setup();
      await r.ride();
    } catch (e) {
      this.m.error('rider', 'lifecycle', e);
    } finally {
      r.teardown();
    }
  }

  async drain(timeoutMs = 120000) {
    const endAt = Date.now() + timeoutMs;
    while (this.inflight > 0 && Date.now() < endAt) await wait(500);
    if (this.inflight > 0) this.log(`drain timeout with ${this.inflight} rides still in flight`);
  }

  async teardown() {
    await Promise.all(this.drivers.map((d) => d.teardown()));
  }

  log(msg) {
    console.log(`  [orchestrator] ${msg}`);
  }
}

function summarizeTiers(tiers) {
  const counts = {};
  for (const t of tiers) counts[t] = (counts[t] || 0) + 1;
  return Object.entries(counts).map(([t, c]) => `${t}×${c}`).join(' ');
}
