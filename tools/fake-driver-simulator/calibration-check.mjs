// Proves the price-comparison CALIBRATION loop works end to end:
//   1. Confirms the estimate response carries surge-aware bands + confidence.
//   2. Feeds "observed real Uber fares" (a known ground-truth rate card) as
//      samples via the admin endpoint.
//   3. Re-fetches the model and shows it flipped to calibrated with a low
//      residual — i.e. the model learned the true rates from samples.
//
//   node calibration-check.mjs
import { api, login } from './lib.mjs';

const ADMIN_PHONE = '+13050000001';
const METERS_PER_MILE = 1609.34;

// Ground-truth "real Uber" rate card we pretend to observe in the wild.
const TRUE = { base: 2.0, perMile: 1.35, perMin: 0.28, fee: 2.9, min: 8.5 };
const trueFare = (mi, min) =>
  Math.max(TRUE.base + TRUE.perMile * mi + TRUE.perMin * min + TRUE.fee, TRUE.min);

let pass = 0;
let fail = 0;
const ok = (c, label) => {
  if (c) { pass++; console.log(`   ✓ ${label}`); }
  else { fail++; console.log(`   ✗ ${label}`); }
};

const run = async () => {
  // The admin user is promoted out-of-band (DB) before this runs; logging in
  // now mints a token carrying the admin role.
  const admin2 = await login(ADMIN_PHONE);

  const TRIP = {
    pickupLat: 25.7617, pickupLng: -80.1918,
    dropoffLat: 25.7907, dropoffLng: -80.13,
  };

  console.log('\n── 1. estimate carries bands + confidence ──');
  const c0 = await api('/comparison/estimate', {
    method: 'POST', token: admin2.token, body: TRIP,
  });
  const uber0 = c0.quotes.find((q) => q.provider === 'uber');
  ok(uber0 && uber0.priceLow < uber0.price && uber0.priceHigh > uber0.price,
    `Uber quote has a band: $${uber0?.priceLow}–$${uber0?.priceHigh} (mid $${uber0?.price})`);
  ok(uber0 && ['high', 'medium', 'low'].includes(uber0.confidence),
    `Uber confidence reported: ${uber0?.confidence}`);
  const ours0 = c0.quotes.find((q) => q.isOurs);
  ok(ours0 && ours0.confidence === 'exact', 'our own quote is exact (no band)');
  ok(typeof c0.demandHigh === 'boolean', `demandHigh flag present: ${c0.demandHigh}`);

  console.log('\n── 2. feed observed real Uber fares as samples ──');
  // Varied distance/time so the fit can separate per-mile from per-min.
  const trips = [
    [2, 6], [2, 14], [5, 10], [5, 24], [8, 16], [8, 34], [3, 20], [7, 12],
    [4, 9], [6, 28],
  ];
  let posted = 0;
  for (const [mi, min] of trips) {
    const r = await api('/comparison/samples', {
      method: 'POST', token: admin2.token,
      body: {
        provider: 'uber',
        distanceM: Math.round(mi * METERS_PER_MILE),
        durationS: Math.round(min * 60),
        observedFare: Number(trueFare(mi, min).toFixed(2)),
        surgeAtSample: 1,
        source: 'calibration-check',
      },
    }).catch((e) => ({ error: e.message }));
    if (!r.error) posted++;
  }
  ok(posted >= 8, `posted ${posted}/10 observed fares`);

  console.log('\n── 3. model calibrated itself from the samples ──');
  const models = await api('/comparison/models', { token: admin2.token });
  const uberModel = models.find((m) => m.provider === 'uber');
  ok(uberModel && uberModel.calibrated === true, 'Uber model flipped to calibrated=true');
  ok(uberModel && uberModel.perMile > 1.2 && uberModel.perMile < 1.5,
    `learned perMile ≈ ${uberModel?.perMile?.toFixed(3)} (true 1.35)`);
  ok(uberModel && uberModel.perMin > 0.2 && uberModel.perMin < 0.36,
    `learned perMin ≈ ${uberModel?.perMin?.toFixed(3)} (true 0.28)`);
  ok(uberModel && uberModel.residualPct != null && uberModel.residualPct < 0.03,
    `residual error ${(uberModel?.residualPct * 100).toFixed(2)}% (< 3%)`);

  // Accuracy vs ground truth on a fresh trip.
  const testMi = 6.2, testMin = 22;
  const predicted =
    uberModel.baseFare + uberModel.perMile * testMi + uberModel.perMin * testMin +
    uberModel.bookingFee;
  const actual = trueFare(testMi, testMin);
  const errPct = Math.abs(predicted - actual) / actual * 100;
  ok(errPct < 3, `held-out trip error ${errPct.toFixed(2)}% (predicted $${predicted.toFixed(2)} vs $${actual.toFixed(2)})`);

  console.log('\n' + '═'.repeat(34));
  console.log(`  PASSED: ${pass}   FAILED: ${fail}`);
  console.log('═'.repeat(34));
  if (fail > 0) process.exit(1);
};

run().catch((e) => { console.error('ERROR:', e.message); process.exit(1); });
