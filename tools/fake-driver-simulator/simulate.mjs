// Spawns N roaming online drivers that auto-accept offers and drive to the
// pickup. Use this WITH the real rider app to get matched to a simulated
// driver. (Starting the trip needs the rider's OTP, so the simulated driver
// stops at "arrived" — continue from the real driver app to finish.)
//
//   DRIVERS=5 npm run simulate
import { api, connect, login, onboardDriver, phone, wait } from './lib.mjs';

const N = parseInt(process.env.DRIVERS || '3', 10);
const CENTER = {
  lat: parseFloat(process.env.LAT || '12.9611'),
  lng: parseFloat(process.env.LNG || '77.6387'),
};

async function spawnDriver(i) {
  const d = await login(phone('90'));
  await onboardDriver(d.token);
  const sock = await connect(d.token);

  const pos = {
    lat: CENTER.lat + (Math.random() - 0.5) * 0.01,
    lng: CENTER.lng + (Math.random() - 0.5) * 0.01,
  };
  const send = (speed = 5) =>
    sock.emit('driver:location', {
      lat: pos.lat,
      lng: pos.lng,
      heading: Math.floor(Math.random() * 360),
      speed,
    });

  sock.emit('driver:status', { status: 'online' });
  await wait(200);
  send();
  setInterval(() => {
    pos.lat += (Math.random() - 0.5) * 0.0006;
    pos.lng += (Math.random() - 0.5) * 0.0006;
    send();
  }, 4000);

  sock.on('trip:offer', (offer) => {
    console.log(`[driver ${i}] offer ${offer.tripId} ₹${offer.fare} → accepting`);
    sock.emit('trip:accept', { tripId: offer.tripId });
  });

  sock.on('trip:assigned', async ({ tripId }) => {
    try {
      const trip = await api(`/trips/${tripId}`, { token: d.token });
      // Drive to pickup in a few steps.
      for (let s = 1; s <= 4; s++) {
        pos.lat += (trip.pickup.lat - pos.lat) / (5 - s);
        pos.lng += (trip.pickup.lng - pos.lng) / (5 - s);
        send(14);
        await wait(1500);
      }
      await api(`/trips/${tripId}/arrived`, { method: 'POST', token: d.token });
      console.log(
        `[driver ${i}] arrived for ${tripId} — waiting for rider OTP ` +
          `(continue from the real driver app to start/complete)`,
      );
    } catch (e) {
      console.log(`[driver ${i}] lifecycle error: ${e.message}`);
    }
  });

  console.log(
    `[driver ${i}] online near ${pos.lat.toFixed(4)},${pos.lng.toFixed(4)}`,
  );
}

async function main() {
  console.log(`Spawning ${N} simulated drivers around ${CENTER.lat},${CENTER.lng}…`);
  for (let i = 0; i < N; i++) {
    await spawnDriver(i + 1);
    await wait(150);
  }
  console.log('Drivers online. Request a ride from the rider app. Ctrl-C to stop.');
}

main().catch((e) => {
  console.error('simulator failed:', e.message);
  process.exit(1);
});
