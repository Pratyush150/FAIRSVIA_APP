// Standalone demo drivers: bring a small fleet online near Brickell and keep
// them there, auto-accepting whatever a REAL rider (phone) books, then driving
// the OSRM route to pickup + dropoff so the ride completes on the live map.
// One driver per tier so any tier the rider picks matches. Runs until killed.

import { execSync } from 'node:child_process';
import { Driver } from './src/driver.mjs';
import { Metrics } from './src/metrics.mjs';
import { setRegion } from './src/geo.mjs';
import { wait, login } from './src/client.mjs';

setRegion(['Brickell']); // spawn drivers in the Brickell core

// A REAL rider (phone) holds the start code on their screen — the in-process
// registry the sim uses can't see it. For the demo, read it straight from the
// backend DB so the simulated driver can start the trip and complete the ride.
function otpFromDb(tripId) {
  try {
    const out = execSync(
      'docker exec fairsvia_postgres psql -U fairsvia -d fairsvia -tAc ' +
        `"select start_otp from trips where id='${tripId}'"`,
      { encoding: 'utf8', timeout: 5000 },
    ).trim();
    return out || null;
  } catch {
    return null;
  }
}

const metrics = new Metrics();
const tiers = ['economy', 'comfort', 'xl'];
const drivers = tiers.map(
  (tier) => new Driver(metrics, { tier, acceptRate: 1, declineRate: 0 }),
);

// Source the start OTP from the backend instead of the sim's in-process registry.
for (const d of drivers) {
  d.waitForOtp = async (tripId) => {
    for (let i = 0; i < 25; i++) {
      const otp = otpFromDb(tripId);
      if (otp) return otp;
      await wait(200);
    }
    return null;
  };
}

for (const d of drivers) {
  try {
    await d.setup();
    console.log(`  driver online: ${d.tier} @ Brickell`);
  } catch (e) {
    console.log(`  driver ${d.tier} failed to start: ${e.message}`);
  }
}
console.log('demo fleet ready — waiting for a rider to book. Ctrl-C to stop.');

// JWT access tokens expire (~15 min); the sockets stay connected but REST calls
// (arrived/start/complete) would start 401ing mid-trip. Re-login every 10 min to
// keep each driver's token fresh so long demo sessions don't silently break.
setInterval(async () => {
  for (const d of drivers) {
    if (!d.phone) continue;
    try {
      const { token } = await login(d.phone);
      d.token = token;
    } catch (e) {
      console.log(`  token refresh failed for ${d.tier}: ${e.message}`);
    }
  }
  console.log('  refreshed driver tokens');
}, 10 * 60 * 1000);

// Keep the process (and the sockets) alive indefinitely.
setInterval(() => {}, 1 << 30);
