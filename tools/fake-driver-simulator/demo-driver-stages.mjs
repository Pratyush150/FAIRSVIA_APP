// Drives the DRIVER side of a ride so the whole rider journey can be shown /
// recorded on a real phone (rider app) end-to-end.
//
// Two stages, because the driver legitimately cannot see the rider's start OTP
// (the backend hides it) — the OTP is supplied out-of-band for the demo.
//
//   node demo-driver-stages.mjs accept
//       -> logs in a fixed demo driver, goes online near Brickell, accepts the
//          next offer, waits, marks Arrived, prints the tripId.
//
//   node demo-driver-stages.mjs finish <tripId> <otp>
//       -> logs the SAME driver back in, starts the trip with the OTP and
//          completes it, so the rider lands on the rate/tip/receipt screen.
import { api, connect, login, once, onboardDriver, wait } from './lib.mjs';

// Fixed number so `finish` re-authenticates as the same driver account.
const DEMO_DRIVER_PHONE = '+19800000077';
const NEAR = { lat: 25.7743, lng: -80.1937 }; // Downtown Miami

async function accept() {
  const driver = await login(DEMO_DRIVER_PHONE);
  await onboardDriver(driver.token, 'economy');
  const sock = await connect(driver.token);
  sock.emit('driver:status', { status: 'online' });
  await wait(300);
  sock.emit('driver:location', { ...NEAR, heading: 90, speed: 0 });
  console.log('driver online — waiting for a ride request…');

  const offer = await once(sock, 'trip:offer', 120000);
  console.log(`offer received: ${offer.tripId} ($${offer.fare})`);
  sock.emit('trip:accept', { tripId: offer.tripId });
  await wait(1200);

  // Let the rider watch the car approach for a beat, then arrive.
  for (let i = 0; i < 4; i++) {
    sock.emit('driver:location', { ...NEAR, heading: 90, speed: 10 });
    await wait(900);
  }
  await api(`/trips/${offer.tripId}/arrived`, {
    method: 'POST',
    token: driver.token,
  });
  console.log(`ARRIVED tripId=${offer.tripId}`);
  sock.close();
}

async function finish(tripId, otp) {
  const driver = await login(DEMO_DRIVER_PHONE);
  await api(`/trips/${tripId}/start`, {
    method: 'POST',
    token: driver.token,
    body: { otp },
  });
  console.log('trip started');
  await wait(2500);
  const receipt = await api(`/trips/${tripId}/complete`, {
    method: 'POST',
    token: driver.token,
  });
  console.log(`COMPLETED fare=$${receipt.fareFinal} payout=$${receipt.driverPayout}`);
}

const [stage, a, b] = process.argv.slice(2);
(stage === 'finish' ? finish(a, b) : accept()).catch((e) => {
  console.error('ERROR:', e.message);
  process.exit(1);
});
