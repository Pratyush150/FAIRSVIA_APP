// End-to-end check for the price-comparison API.
//
// Verifies POST /comparison/estimate returns our fare alongside the market's
// modeled competitor fares (INR: Uber/Ola/Rapido; UZS; AED) for the same trip, flags the minimum-price provider,
// marks competitor quotes as estimates (honesty), and that /trips/estimate
// carries the same comparison block.
//
//   node comparison-check.mjs
import { api, login } from './lib.mjs';

let pass = 0;
let fail = 0;
function ok(cond, label) {
  if (cond) {
    pass++;
    console.log(`   ✓ ${label}`);
  } else {
    fail++;
    console.log(`   ✗ ${label}`);
  }
}

// One trip per market with a competitor set. The live backend's own market
// (MARKET_CURRENCY) is checked without a currency override AND via
// /trips/estimate; the others through the verification-only `currency` field.
const MARKETS = {
  INR: {
    // Shivajinagar -> Koregaon Park, Pune (~5 km).
    trip: { pickupLat: 18.53, pickupLng: 73.8475, dropoffLat: 18.5362, dropoffLng: 73.8940 },
    providers: ['uber', 'ola', 'rapido'],
    fmt: (n) => `₹${Math.round(n)}`,
    whole: true,
  },
  UZS: {
    // Amir Temur Square -> Chorsu Bazaar, Tashkent (~4 km).
    trip: { pickupLat: 41.3111, pickupLng: 69.2797, dropoffLat: 41.3265, dropoffLng: 69.2345 },
    providers: ['yandex', 'mytaxi'],
    fmt: (n) => `${Math.round(n).toLocaleString('en-US').replace(/,/g, ' ')} so'm`,
    whole: true,
  },
  AED: {
    // BurJuman -> Dubai Mall (~9 km).
    trip: { pickupLat: 25.2527, pickupLng: 55.3033, dropoffLat: 25.1985, dropoffLng: 55.2796 },
    providers: ['rta_taxi', 'careem', 'uber'],
    fmt: (n) => `AED ${n.toFixed(2)}`,
    whole: false,
  },
};
const LIVE = (process.env.MARKET_CURRENCY || 'INR').toUpperCase();

function checkComparison(c, cur, m) {
  ok(c.currency === cur, `[${cur}] comparison currency is ${c.currency}`);
  const providers = c.quotes.map((q) => q.provider);
  ok(providers.includes('ubernav'), `[${cur}] includes our own quote`);
  for (const p of m.providers) ok(providers.includes(p), `[${cur}] includes ${p}`);
  ok(c.quotes.every((q) => q.currency === cur), `[${cur}] every quote (ours too) is in ${cur}`);
  ok(
    c.quotes.every((q, i) => i === 0 || c.quotes[i - 1].price <= q.price),
    `[${cur}] quotes sorted cheapest first`,
  );
  ok(c.cheapest.price === c.quotes[0].price, `[${cur}] cheapest = ${c.cheapest.displayName} ${m.fmt(c.cheapest.price)}`);
  if (m.whole) ok(c.quotes.every((q) => Number.isInteger(q.price)), `[${cur}] whole-unit prices`);
  const ours = c.quotes.find((q) => q.isOurs);
  ok(ours && ours.estimated === false, `[${cur}] our quote is a real price`);
  ok(c.quotes.filter((q) => !q.isOurs).every((q) => q.estimated === true), `[${cur}] competitors flagged estimated`);
  ok(/Estimates from published fares/.test(c.disclaimer || ''), `[${cur}] disclaimer present`);
  console.log(`   ${(c.distanceM / 1000).toFixed(1)} km / ${c.durationMin} min`);
  for (const q of c.quotes) {
    console.log(`     ${q.displayName.padEnd(11)} ${q.productName.padEnd(14)} ${m.fmt(q.price)}${q.isOurs ? ' ← us' : ' (est.)'}`);
  }
}

const run = async () => {
  const rider = await login(process.env.RIDER_PHONE || '+13055550111');

  for (const [cur, m] of Object.entries(MARKETS)) {
    console.log(`\n── POST /comparison/estimate (${cur}${cur === LIVE ? ', live market' : ', currency override'}) ──`);
    const body = cur === LIVE ? m.trip : { ...m.trip, currency: cur };
    const c = await api('/comparison/estimate', { method: 'POST', token: rider.token, body });
    checkComparison(c, cur, m);
  }

  console.log(`\n── /trips/estimate carries the comparison (${LIVE}) ──`);
  const est = await api('/trips/estimate', { method: 'POST', token: rider.token, body: MARKETS[LIVE].trip });
  ok(!!est.comparison, 'estimate response includes a comparison block');
  ok(est.comparison?.currency === LIVE, `embedded comparison is in ${LIVE}`);

  console.log('\n── unsupported currency is rejected ──');
  let rejected = false;
  try {
    await api('/comparison/estimate', { method: 'POST', token: rider.token, body: { ...MARKETS.INR.trip, currency: 'EUR' } });
  } catch {
    rejected = true;
  }
  ok(rejected, 'currency EUR → 400');

  console.log('\n' + '═'.repeat(32));
  console.log(`  PASSED: ${pass}   FAILED: ${fail}`);
  console.log('═'.repeat(32));
  if (fail > 0) process.exit(1);
};

run().catch((e) => {
  console.error('ERROR:', e.message);
  process.exit(1);
});
