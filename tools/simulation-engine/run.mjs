#!/usr/bin/env node
// CLI entry. Usage:
//   node run.mjs <scenario> [--json out.json]
//   npm run steady            (scenario presets: smoke steady spike chaos soak)
// Env overrides: BASE_URL, WS_URL, OSRM_BASE_URL, TIME_SCALE, DRIVERS, RATE,
//   DURATION, WAVE, WAVES, POOL, RIDES, MAX_INFLIGHT, GAP_MS.

import { writeFileSync } from 'node:fs';
import { getScenario, SCENARIOS } from './src/scenarios.mjs';
import { Orchestrator } from './src/orchestrator.mjs';
import { Metrics } from './src/metrics.mjs';
import { buildReport, printReport } from './src/report.mjs';
import { BASE, WS, OSRM, TIME_SCALE } from './src/config.mjs';

async function main() {
  const args = process.argv.slice(2);
  const name = args[0] && !args[0].startsWith('--') ? args[0] : 'smoke';
  const jsonIdx = args.indexOf('--json');
  const jsonOut = jsonIdx >= 0 ? args[jsonIdx + 1] : null;

  let scenario;
  try {
    scenario = getScenario(name);
  } catch (e) {
    console.error(e.message);
    console.error(`\nScenarios:\n${Object.values(SCENARIOS).map((s) => `  ${s.name.padEnd(8)} ${s.description}`).join('\n')}`);
    process.exit(2);
  }

  console.log(`\n  UberNav Simulation Engine`);
  console.log(`  scenario=${scenario.name}  drivers=${scenario.drivers}  target=${BASE}`);
  console.log(`  osrm=${OSRM || '(off, straight-line)'}  ws=${WS}  timeScale=${TIME_SCALE}x`);

  const metrics = new Metrics();
  const orch = new Orchestrator(scenario, metrics);

  const onSig = async () => { console.log('\n  interrupted — building partial report…'); await finish(); };
  process.once('SIGINT', onSig);

  async function finish() {
    const report = await buildReport(scenario, metrics);
    printReport(report);
    if (jsonOut) {
      writeFileSync(jsonOut, JSON.stringify(report, null, 2));
      console.log(`  wrote ${jsonOut}`);
    }
    process.exit(report.passed ? 0 : 1);
  }

  try {
    await orch.run();
  } catch (e) {
    metrics.error('engine', 'run', e);
    console.error(`  engine error: ${e.message}`);
  }
  await finish();
}

main();
