// Helper for the dispatch durability test: logs in a fresh rider and creates a
// trip, printing TRIPID=<id>. Fake non-responding drivers must already be
// injected into Redis so the trip parks in `matching` (the worker offers and
// waits). The bash harness then crashes + restarts the backend and checks the
// trip still gets processed.
import { login, api, phone } from './lib.mjs';

const pickup = { lat: 25.7743, lng: -80.1937 };
const dropoff = { lat: 25.7806, lng: -80.2420 };

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
