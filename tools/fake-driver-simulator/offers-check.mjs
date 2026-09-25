// Offers end to end against the running backend: a fresh rider sees the
// listed offers, books with one, gets the discount, no longer sees a
// one-use offer, and gets it back when the ride is cancelled.
// Run: node offers-check.mjs   (needs the seeded offers:
//   docker exec ubernav_backend npx ts-node scripts/seed-offers.ts)
import { api, login, phone } from './lib.mjs';

function assert(cond, msg) {
  if (!cond) throw new Error('ASSERT FAILED: ' + msg);
}

const pickup = { lat: 18.5204, lng: 73.8567 };
const dropoff = { lat: 18.5793, lng: 73.9089 };

async function main() {
  const rider = await login(phone('93'));
  const offers = await api('/promos/available', { token: rider.token });
  console.log('• offers:', offers.map((o) => `${o.code} (${o.title})`).join(', '));
  const welcome = offers.find((o) => o.code === 'WELCOME50');
  assert(welcome, 'WELCOME50 listed for a new rider');
  assert(welcome.usesLeftForMe === 1, 'one use left');

  const est = await api('/trips/estimate', {
    method: 'POST',
    token: rider.token,
    body: {
      pickupLat: pickup.lat, pickupLng: pickup.lng,
      dropoffLat: dropoff.lat, dropoffLng: dropoff.lng,
    },
  });
  const economy = est.tiers.find((t) => t.tier === 'economy');
  console.log(`• economy fare ${economy.fare} ${est.currency}`);

  const quote = await api('/promos/quote', {
    method: 'POST', token: rider.token,
    body: { code: 'WELCOME50', subtotal: economy.fare },
  });
  console.log(`• quote: -${quote.discount} → ${quote.net}`);
  const expected = Math.min(economy.fare * 0.5, 100);
  assert(Math.abs(quote.discount - expected) < 0.01, `discount ${quote.discount} == ${expected}`);

  const trip = await api('/trips', {
    method: 'POST', token: rider.token,
    body: {
      pickupLat: pickup.lat, pickupLng: pickup.lng,
      dropoffLat: dropoff.lat, dropoffLng: dropoff.lng,
      tier: 'economy', paymentMode: 'cash', promoCode: 'welcome50',
      quotedFare: economy.fare, quotedSurge: est.surge,
    },
  });
  console.log(`• trip ${trip.id}: promo ${trip.promoCode} -${trip.promoDiscount}, fare ${trip.fareEstimate}`);
  assert(trip.promoCode === 'WELCOME50', 'code recorded');
  assert(Math.abs(trip.promoDiscount - expected) < 0.01, 'discount on the trip');

  const after = await api('/promos/available', { token: rider.token });
  assert(!after.some((o) => o.code === 'WELCOME50'), 'WELCOME50 gone once used');
  console.log('• WELCOME50 no longer offered to this rider');

  await api(`/trips/${trip.id}/cancel`, {
    method: 'POST', token: rider.token, body: { reason: 'offers-check' },
  });
  const back = await api('/promos/available', { token: rider.token });
  assert(back.some((o) => o.code === 'WELCOME50'), 'WELCOME50 back after cancel');
  console.log('• cancelled — WELCOME50 offered again');
  console.log('OFFERS CHECK PASSED');
}

main().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
