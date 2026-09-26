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
  // Owner rule (price match): RideVela is the cheapest, strictly.
  const minOther = Math.min(...c.quotes.filter((q) => !q.isOurs).map((q) => q.price));
  ok(c.ours.isCheapest && ours.price < minOther, `[${cur}] RideVela cheapest: ${m.fmt(ours.price)} < ${m.fmt(minOther)}`);
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

  if (LIVE === 'INR') {
    console.log('\n── per-tier comparisons (comparisonsByTier + POST tier) ──');
    const by = est.comparisonsByTier || {};
    const tiers = ['economy', 'comfort', 'xl', 'premium'];
    for (const t of tiers) {
      const c = by[t];
      ok(!!c && c.tier === t, `comparisonsByTier.${t} present`);
      if (!c) continue;
      const ourTier = est.tiers.find((x) => x.tier === t);
      ok(c.ours.price === ourTier?.fare, `[${t}] our price = ${t} fare ${ourTier?.fare}`);
      ok(c.quotes.some((q) => !q.isOurs), `[${t}] has competitor quotes`);
      console.log(`   ${t}: ` + c.quotes.map((q) => `${q.displayName} ${q.productName} ₹${q.price}`).join(' | '));
    }

    console.log('\n── price match: RideVela cheapest in every tier (5 km + ~1 km min-fare trip) ──');
    const short = await api('/trips/estimate', {
      method: 'POST',
      token: rider.token,
      // ~1 km in Shivajinagar: a minimum-fare trip.
      body: { pickupLat: 18.53, pickupLng: 73.8475, dropoffLat: 18.5365, dropoffLng: 73.8540 },
    });
    for (const [label, e] of [['5 km', est], [`${(short.distanceM / 1000).toFixed(1)} km`, short]]) {
      for (const t of tiers) {
        const c = e.comparisonsByTier?.[t];
        if (!c) { ok(false, `[${label} ${t}] comparison present`); continue; }
        const minOther = Math.min(...c.quotes.filter((q) => !q.isOurs).map((q) => q.price));
        const fare = e.tiers.find((x) => x.tier === t)?.fare;
        ok(
          c.ours.isCheapest && fare === c.ours.price && fare < minOther,
          `[${label} ${t}] RideVela ₹${fare} (computed ₹${c.ours.priceMatch?.computedFare}) < cheapest competitor ₹${minOther}`,
        );
      }
    }
    ok(
      by.economy && JSON.stringify(by.economy.quotes) === JSON.stringify(est.comparison.quotes),
      'comparison (back-compat) equals comparisonsByTier.economy',
    );
    const uber = (t) => by[t]?.quotes.find((q) => q.provider === 'uber')?.price;
    const u = tiers.map(uber);
    ok(new Set(u).size === 4 && u.every((v, i) => i === 0 || v > u[i - 1]), `Uber price rises across tiers: ${u.join(' < ')}`);
    const r = by.economy?.quotes.find((q) => q.provider === 'rapido')?.price;
    ok(r < uber('economy'), `Rapido (zero-commission) below Uber Go: ₹${r} < ₹${uber('economy')}`);
    const xl = await api('/comparison/estimate', { method: 'POST', token: rider.token, body: { ...MARKETS.INR.trip, tier: 'xl' } });
    ok(xl.tier === 'xl' && xl.quotes.some((q) => q.productName === 'Uber XL'), 'POST /comparison/estimate tier=xl → Uber XL set');
    ok(xl.quotes.find((q) => q.provider === 'uber')?.price === uber('xl'), 'POST tier=xl matches comparisonsByTier.xl');
  }

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
