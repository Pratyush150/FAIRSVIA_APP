// Helper for the dispatch durability test: logs in a fresh rider and creates a
// trip, printing TRIPID=<id>. Fake non-responding drivers must already be
// injected into Redis so the trip parks in `matching` (the worker offers and
// waits). The bash harness then crashes + restarts the backend and checks the
// trip still gets processed.
import { login, api, phone } from './lib.mjs';

const pickup = { lat: 12.9611, lng: 77.6387 };
const dropoff = { lat: 12.9674, lng: 77.5904 };

const rider = await login(phone('91'));
const trip = await api('/trips', {
  method: 'POST',
  token: rider.token,
  body: {
    pickupLat: pickup.lat,
    pickupLng: pickup.lng,
    dropoffLat: dropoff.lat,
    dropoffLng: dropoff.lng,
    tier: 'economy',
    pickupAddr: 'DurabilityTest',
    dropoffAddr: 'MG Road',
  },
});
console.log('TRIPID=' + trip.id);
process.exit(0);
