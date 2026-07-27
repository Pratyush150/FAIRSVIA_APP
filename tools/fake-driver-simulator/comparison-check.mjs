// End-to-end check for the price-comparison API.
//
// Verifies POST /comparison/estimate returns our fare alongside modeled
// Uber/Lyft/Empower fares for the same trip, flags the minimum-price provider,
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

// Downtown Miami -> Miami Beach, ~5 mi.
const TRIP = {
  pickupLat: 25.7617,
  pickupLng: -80.1918,
  dropoffLat: 25.7907,
  dropoffLng: -80.13,
};

const run = async () => {
  const rider = await login('+13055550111');

  console.log('\n── POST /comparison/estimate ──');
  const c = await api('/comparison/estimate', {
    method: 'POST',
    token: rider.token,
    body: TRIP,
  });

  const providers = c.quotes.map((q) => q.provider);
  ok(providers.includes('ubernav'), 'includes our own (ubernav) quote');
  ok(providers.includes('uber'), 'includes Uber');
  ok(providers.includes('lyft'), 'includes Lyft');
  ok(providers.includes('empower'), 'includes Empower');

  const sorted = c.quotes.every(
    (q, i) => i === 0 || c.quotes[i - 1].price <= q.price,
  );
  ok(sorted, 'quotes sorted cheapest → most expensive');

  ok(
    c.cheapest && typeof c.cheapest.price === 'number',
    `reports the MINIMUM price provider: ${c.cheapest?.displayName} $${c.cheapest?.price}`,
  );
  ok(
    c.cheapest.price === c.quotes[0].price,
    'cheapest matches the first (lowest) quote',
  );

  const ours = c.quotes.find((q) => q.isOurs);
  ok(ours && ours.estimated === false, 'our quote is a REAL price (not estimated)');
  const competitors = c.quotes.filter((q) => !q.isOurs);
  ok(
    competitors.every((q) => q.estimated === true),
    'every competitor quote is flagged estimated=true (honesty)',
  );
  ok(/estimate/i.test(c.disclaimer || ''), 'response carries the estimate disclaimer');

  ok(
    typeof c.ours.rank === 'number' && c.ours.rank >= 1,
    `our rank is reported: #${c.ours.rank} of ${c.quotes.length}`,
  );
  ok(
    typeof c.ours.maxSavings === 'number' && c.ours.maxSavings >= 0,
    `max savings vs priciest option: $${c.ours.maxSavings}`,
  );
  ok(
    Array.isArray(c.ours.vs) && c.ours.vs.length === competitors.length,
    'per-competitor deltas present',
  );

  console.log('\n── /trips/estimate carries the same comparison block ──');
  const est = await api('/trips/estimate', {
    method: 'POST',
    token: rider.token,
    body: TRIP,
  });
  ok(!!est.comparison, 'estimate response includes a comparison block');
  ok(
    est.comparison && est.comparison.cheapest &&
      typeof est.comparison.cheapest.price === 'number',
    'embedded comparison also flags the minimum price',
  );

  console.log('\n' + '═'.repeat(32));
  console.log(`  PASSED: ${pass}   FAILED: ${fail}`);
  console.log('═'.repeat(32));
  if (c.quotes) {
    console.log('\n  Quotes (this trip):');
    for (const q of c.quotes) {
      const tag = q.isOurs ? ' ← us' : q.estimated ? ' (est.)' : '';
      const min = q.provider === c.cheapest.provider ? '  ★ cheapest' : '';
      console.log(
        `    ${q.displayName.padEnd(9)} $${q.price.toFixed(2)}${tag}${min}`,
      );
    }
  }
  if (fail > 0) process.exit(1);
};

run().catch((e) => {
  console.error('ERROR:', e.message);
  process.exit(1);
});
