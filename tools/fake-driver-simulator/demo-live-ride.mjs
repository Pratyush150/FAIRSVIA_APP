// Interactive demo driver for on-device testing. Goes online in Miami, waits
// for a REAL ride requested from the rider app, then drives the full lifecycle
// so you can watch the car move on your phone:
//   accept → drive to pickup → arrive → start → drive to dropoff → complete.
//
// The start OTP is shown only to the rider (your phone). For a hands-off demo
// this bot reads it straight from the backend DB (we own the box) via
// `docker exec ubernav_postgres`. Run: node demo-live-ride.mjs
import { execSync } from 'node:child_process';
import { api, connect, login, onboardDriver, phone, wait } from './lib.mjs';

// Start a few blocks NW of the rider's pinned Miami location so the car has a
// short, visible drive to the pickup.
// START_LAT / START_LNG move it (Pune pilot: 18.5300, 73.8475).
const START = {
  lat: Number(process.env.START_LAT ?? 25.766),
  lng: Number(process.env.START_LNG ?? -80.1955),
};

function bearing(a, b) {
  const dLng = ((b.lng - a.lng) * Math.PI) / 180;
  const y = Math.sin(dLng) * Math.cos((b.lat * Math.PI) / 180);
  const x =
    Math.cos((a.lat * Math.PI) / 180) * Math.sin((b.lat * Math.PI) / 180) -
    Math.sin((a.lat * Math.PI) / 180) *
      Math.cos((b.lat * Math.PI) / 180) *
      Math.cos(dLng);
  return ((Math.atan2(y, x) * 180) / Math.PI + 360) % 360;
}

/** Stream location from `from` → `to` in `steps` hops, ~`gap`ms apart. */
async function drive(sock, from, to, { steps = 14, gap = 850, label }) {
  const hdg = Math.round(bearing(from, to));
  for (let i = 1; i <= steps; i++) {
    const t = i / steps;
    const lat = from.lat + (to.lat - from.lat) * t;
    const lng = from.lng + (to.lng - from.lng) * t;
    sock.emit('driver:location', { lat, lng, heading: hdg, speed: 11 });
    if (i === 1 || i === steps || i % 4 === 0) {
      console.log(`  · ${label} ${Math.round(t * 100)}%`);
    }
    await wait(gap);
  }
}

/** Read the rider's start OTP straight from Postgres (demo shortcut). */
function readStartOtp(tripId) {
  const out = execSync(
    `docker exec ubernav_postgres psql -U ubernav -d ubernav -tAc ` +
      `"SELECT start_otp FROM trips WHERE id='${tripId}'"`,
  )
    .toString()
    .trim();
  return out;
}

async function main() {
  // Keep the phone so we can re-login for a fresh access token when the ride
  // finally arrives — a demo can sit ONLINE for many minutes waiting for you to
  // tap Confirm, and the 15-min access token would otherwise expire and the
  // lifecycle POSTs (arrived/start/complete) would 401 mid-ride.
  const driverPhone = phone('55');
  const driver = await login(driverPhone);
  await onboardDriver(driver.token, 'economy');
  const sock = await connect(driver.token);
  console.log(`• bot driver ${driver.user.id} connected`);

  sock.emit('driver:status', { status: 'online' });
  await wait(300);
  sock.emit('driver:location', {
    lat: START.lat,
    lng: START.lng,
    heading: 90,
    speed: 0,
  });
  console.log(
    `\n🟢 ONLINE in Miami at ${START.lat},${START.lng} — waiting for a ride.\n` +
      `   Tap "Confirm Economy" on your phone now.\n`,
  );

  // Keep presence alive until an offer arrives.
  const ping = setInterval(() => {
    sock.emit('driver:location', {
      lat: START.lat,
      lng: START.lng,
      heading: 90,
      speed: 0,
    });
  }, 4000);

  sock.on('trip:offer', async (offer) => {
    clearInterval(ping);
    console.log(`\n🚕 OFFER ${offer.tripId} — $${offer.fare}. Accepting…`);
    sock.emit('trip:accept', { tripId: offer.tripId });

    // Refresh the access token now that the ride is live — the wait before this
    // offer may have outlived the original token. Same phone → same driver.
    const token = (await login(driverPhone)).token;

    const pickup = { lat: offer.pickup.lat, lng: offer.pickup.lng };
    const dropoff = { lat: offer.dropoff.lat, lng: offer.dropoff.lng };

    // 1) Drive to the pickup.
    await wait(600);
    console.log('→ driving to pickup');
    await drive(sock, START, pickup, { label: 'to pickup' });

    // 2) Arrive.
    await api(`/trips/${offer.tripId}/arrived`, {
      method: 'POST',
      token,
    });
    console.log('📍 ARRIVED at pickup');
    await wait(1200);

    // 3) Start (needs the rider's OTP — read from the backend for the demo).
    const otp = readStartOtp(offer.tripId);
    console.log(`🔑 start OTP (from backend) = ${otp} → starting trip`);
    await api(`/trips/${offer.tripId}/start`, {
      method: 'POST',
      token,
      body: { otp },
    });
    console.log('▶️  TRIP STARTED');

    // 4) Drive to the dropoff.
    console.log('→ driving to dropoff');
    await drive(sock, pickup, dropoff, { steps: 18, label: 'to dropoff' });

    // 5) Complete.
    const receipt = await api(`/trips/${offer.tripId}/complete`, {
      method: 'POST',
      token,
    });
    console.log(`\n🏁 TRIP COMPLETE — fare $${receipt.fareFinal ?? receipt.fare}`);
    console.log('   (Your phone should show the receipt + rating prompt.)\n');

    await wait(1500);
    sock.close();
    process.exit(0);
  });

  sock.on('trip:message', (m) => {
    if (!m || m.from === driver.user.id) return;
    console.log(`💬 rider: ${m.text}`);
    setTimeout(() => {
      sock.emit('trip:message', {
        tripId: m.tripId,
        text: 'On my way — 2 min out 🚗',
      });
    }, 700);
  });

  sock.on('trip:cancelled', () => {
    console.log('• rider cancelled the trip. Exiting.');
    sock.close();
    process.exit(0);
  });
}

main().catch((e) => {
  console.error('demo bot failed:', e.message);
  process.exit(1);
});
