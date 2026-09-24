// A driver that goes online and never answers an offer — keeps the rider app
// in "finding your driver" for as long as you need (radar, "Still looking…").
//   START_LAT=18.5300 START_LNG=73.8475 node idle-driver.mjs [minutes]
import { connect, login, onboardDriver, phone, wait } from './lib.mjs';

const MINUTES = Number(process.argv[2] || 3);
const at = {
  lat: Number(process.env.START_LAT ?? 25.766),
  lng: Number(process.env.START_LNG ?? -80.1955),
};
const driver = await login(phone('91'));
await onboardDriver(driver.token, 'economy');
const sock = await connect(driver.token);
sock.emit('driver:status', { status: 'online' });
sock.on('trip:offer', (o) => console.log(`📨 offer ${o.tripId ?? ''} — ignoring`));
console.log(`🟡 online at ${at.lat},${at.lng}, ignoring offers for ${MINUTES} min`);
const end = Date.now() + MINUTES * 60_000;
while (Date.now() < end) {
  sock.emit('driver:location', { ...at, heading: 0, speed: 0 });
  await wait(3000);
}
sock.emit('driver:status', { status: 'offline' });
sock.close();
process.exit(0);
