// Book a single ride near Brickell as a real rider, then idle (stay connected so
// the trip stays live). Used to validate the driver app end-to-end: run this,
// and the online emulator driver receives the offer. Prints the trip id + OTP.

import { login, api, connect, phone } from './src/client.mjs';

const pickup = { lat: 25.7615, lng: -80.1929 }; // Brickell — near the demo driver
const dropoff = { lat: 25.7743, lng: -80.1937 }; // Downtown Miami

const { token } = await login(phone());
await connect(token); // keep the rider socket open so the trip isn't abandoned

await api('/trips/estimate', {
  method: 'POST',
  token,
  body: {
    pickupLat: pickup.lat,
    pickupLng: pickup.lng,
    dropoffLat: dropoff.lat,
    dropoffLng: dropoff.lng,
  },
});

const trip = await api('/trips', {
  method: 'POST',
  token,
  body: {
    pickupLat: pickup.lat,
    pickupLng: pickup.lng,
    dropoffLat: dropoff.lat,
    dropoffLng: dropoff.lng,
    tier: 'economy',
    paymentMode: 'card',
    pickupAddr: 'Brickell',
    dropoffAddr: 'Downtown Miami',
  },
});

console.log(`booked trip ${trip.id}  startOtp ${trip.startOtp}`);
setInterval(() => {}, 1 << 30);
