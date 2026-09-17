// Focused probe: park a driver mid-trip and report exactly when the
// "driver stopped" advisory fires and what duration it claims.
import { api, connect, login, once, onboardDriver, phone, wait } from './lib.mjs';

const pickup = { lat: 25.7743, lng: -80.1937 };
const dropoff = { lat: 25.7806, lng: -80.242 };

const driver = await login(phone('90'));
await onboardDriver(driver.token, 'economy');
const dSock = await connect(driver.token);
dSock.emit('driver:status', { status: 'online' });
await wait(300);
dSock.emit('driver:location', { lat: pickup.lat + 0.001, lng: pickup.lng + 0.001, speed: 0 });
await wait(400);

const rider = await login(phone('91'));
const rSock = await connect(rider.token);

const offerP = once(dSock, 'trip:offer');
const acceptedP = once(rSock, 'trip:accepted');
const trip = await api('/trips', {
  method: 'POST',
  token: rider.token,
  body: {
    pickupLat: pickup.lat, pickupLng: pickup.lng,
    dropoffLat: dropoff.lat, dropoffLng: dropoff.lng,
    tier: 'economy', pickupAddr: 'P', dropoffAddr: 'D', paymentMode: 'cash',
  },
});
const offer = await offerP;
dSock.emit('trip:accept', { tripId: offer.tripId });
await acceptedP;

dSock.emit('driver:location', { lat: pickup.lat, lng: pickup.lng, speed: 0, accuracy: 5 });
await wait(500);
await api(`/trips/${trip.id}/arrived`, { method: 'POST', token: driver.token });
const full = await api(`/trips/${trip.id}`, { token: rider.token });
const startedP = once(rSock, 'trip:started');
await api(`/trips/${trip.id}/start`, {
  method: 'POST', token: driver.token, body: { otp: full.startOtp },
});
await startedP;

const parked = { lat: pickup.lat, lng: pickup.lng };
const t0 = Date.now();
rSock.on('trip:driver_stopped', (d) => {
  const wall = Math.round((Date.now() - t0) / 1000);
  console.log(
    `EVENT at wall +${wall}s  → stoppedSec=${d.stoppedSec}  phase=${d.phase}`,
  );
});

console.log('parking the driver; pinging the same point every 5s for 240s…');
for (let i = 0; i < 48; i++) {
  dSock.emit('driver:location', { ...parked, speed: 0, accuracy: 5 });
  if (i % 6 === 0) console.log(`  ping at wall +${Math.round((Date.now() - t0) / 1000)}s`);
  await wait(5000);
}

dSock.close();
rSock.close();
process.exit(0);
