// A persistent driver bot for manual/on-device testing. Goes online near a
// fixed point, auto-accepts the first offer, drives to pickup, and auto-replies
// to chat messages. Stays alive until killed (Ctrl-C).
// Run: node driver-bot.mjs   (optionally BOT_LAT / BOT_LNG env)
import { api, connect, login, onboardDriver, phone, wait } from './lib.mjs';

const LAT = Number(process.env.BOT_LAT ?? 25.7743);
const LNG = Number(process.env.BOT_LNG ?? -80.1937);

async function main() {
  const driver = await login(phone('88'));
  await onboardDriver(driver.token, 'economy');
  const sock = await connect(driver.token);
  console.log(`• bot driver ${driver.user.id} connected`);

  sock.emit('driver:status', { status: 'online' });
  await wait(300);
  sock.emit('driver:location', { lat: LAT, lng: LNG, heading: 90, speed: 0 });
  console.log(`• online at ${LAT},${LNG} — waiting for offers`);

  let activeTrip = null;

  sock.on('trip:offer', async (offer) => {
    console.log(`• offer ${offer.tripId} $${offer.fare} → accepting`);
    sock.emit('trip:accept', { tripId: offer.tripId });
    activeTrip = offer.tripId;
    // Nudge to pickup so the rider sees the car move.
    await wait(500);
    sock.emit('driver:location', { lat: LAT, lng: LNG, heading: 90, speed: 8 });
  });

  sock.on('trip:message', (m) => {
    if (!m || m.from === driver.user.id) return; // ignore own echo
    console.log(`• rider: ${m.text}`);
    const reply = 'On my way, be there in 2 min 🚗';
    setTimeout(() => {
      sock.emit('trip:message', { tripId: m.tripId, text: reply });
      console.log(`• bot → rider: ${reply}`);
    }, 800);
  });

  sock.on('trip:cancelled', () => {
    console.log('• trip cancelled by rider');
    activeTrip = null;
  });

  // Keep the driver present with periodic location pings.
  setInterval(() => {
    sock.emit('driver:location', { lat: LAT, lng: LNG, heading: 90, speed: activeTrip ? 6 : 0 });
  }, 4000);

  // Stay alive.
  await new Promise(() => {});
}

main().catch((e) => {
  console.error('bot failed:', e.message);
  process.exit(1);
});
