// Reactive on-device demo driver. Unlike demo-live-ride.mjs (fixed Miami start),
// this WATCHES for the ride you book from the rider app — wherever you actually
// are (real GPS) — then brings a driver online ~800m away and drives the full
// lifecycle so you can watch the car glide to you and to the destination:
//   your booking → driver online in your region (90s re-sweep) → accept →
//   drive to pickup → arrive → start (OTP read from backend) → drive → complete.
//
// Run on the box:  node on-device-demo.mjs
import { execSync } from 'node:child_process';
import { api, connect, login, onboardDriver, phone, wait } from './lib.mjs';

function psql(sql) {
  return execSync(
    `docker exec ubernav_postgres psql -U ubernav -d ubernav -tAc "${sql}"`,
  )
    .toString()
    .trim();
}

/** The newest waiting trip (no driver yet) created since the script started. */
function latestWaitingTrip(sinceIso) {
  const row = psql(
    `SELECT id||'|'||pickup_lat||'|'||pickup_lng||'|'||dropoff_lat||'|'||dropoff_lng ` +
      `FROM trips WHERE driver_id IS NULL ` +
      `AND status IN ('requested','matching') ` +
      `AND requested_at > '${sinceIso}' ` +
      `ORDER BY requested_at DESC LIMIT 1`,
  );
  if (!row) return null;
  const [id, pl, pn, dl, dn] = row.split('|');
  return {
    id,
    pickup: { lat: Number(pl), lng: Number(pn) },
    dropoff: { lat: Number(dl), lng: Number(dn) },
  };
}

function readStartOtp(tripId) {
  return psql(`SELECT start_otp FROM trips WHERE id='${tripId}'`);
}

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

/** Stream location from `from` → `to` in small hops so the car glides. */
async function drive(sock, from, to, { steps = 16, gap = 850, label } = {}) {
  const hdg = Math.round(bearing(from, to));
  for (let i = 1; i <= steps; i++) {
    const t = i / steps;
    sock.emit('driver:location', {
      lat: from.lat + (to.lat - from.lat) * t,
      lng: from.lng + (to.lng - from.lng) * t,
      heading: hdg,
      speed: 11,
    });
    if (i === 1 || i === steps || i % 4 === 0) {
      console.log(`  · ${label} ${Math.round(t * 100)}%`);
    }
    await wait(gap);
  }
}

async function main() {
  const sinceIso = new Date(Date.now() - 5000).toISOString();
  const driverPhone = phone('55');
  const driver = await login(driverPhone);
  await onboardDriver(driver.token, 'economy');
  const sock = await connect(driver.token);
  console.log(`• demo driver ${driver.user.id} connected`);
  console.log('\n👉 Now open the RIDER app on your phone and book a ride.\n');

  // 1) Wait for YOUR booking to appear, then compute a start ~800m from pickup.
  let trip = null;
  while (!trip) {
    try {
      trip = latestWaitingTrip(sinceIso);
    } catch (e) {
      console.error('poll error:', e.message);
    }
    if (!trip) await wait(2000);
  }
  const start = {
    lat: trip.pickup.lat + 0.006, // ~650m north
    lng: trip.pickup.lng - 0.006, // ~600m west (visible approach drive)
  };
  console.log(
    `\n🟢 Ride ${trip.id} detected at ${trip.pickup.lat.toFixed(5)},` +
      `${trip.pickup.lng.toFixed(5)} — bringing a driver online ~800m away.`,
  );

  // 2) Go online near the pickup; the 90s re-sweep will offer this trip.
  sock.emit('driver:status', { status: 'online' });
  await wait(300);
  const ping = setInterval(() => {
    sock.emit('driver:location', {
      lat: start.lat,
      lng: start.lng,
      heading: 90,
      speed: 0,
    });
  }, 3000);
  sock.emit('driver:location', {
    lat: start.lat,
    lng: start.lng,
    heading: 90,
    speed: 0,
  });

  sock.on('trip:offer', async (offer) => {
    clearInterval(ping);
    console.log(`\n🚕 OFFER ${offer.tripId} — $${offer.fare}. Accepting…`);
    sock.emit('trip:accept', { tripId: offer.tripId });
    const token = (await login(driverPhone)).token;
    const pickup = { lat: offer.pickup.lat, lng: offer.pickup.lng };
    const dropoff = { lat: offer.dropoff.lat, lng: offer.dropoff.lng };

    await wait(600);
    console.log('→ driving to pickup (watch the car glide on your phone)');
    await drive(sock, start, pickup, { label: 'to pickup' });

    await api(`/trips/${offer.tripId}/arrived`, { method: 'POST', token });
    console.log('📍 ARRIVED at pickup');
    await wait(1500);

    const otp = readStartOtp(offer.tripId);
    console.log(`🔑 start OTP (from backend) = ${otp} → starting`);
    await api(`/trips/${offer.tripId}/start`, {
      method: 'POST',
      token,
      body: { otp },
    });
    console.log('▶️  TRIP STARTED');

    console.log('→ driving to dropoff');
    await drive(sock, pickup, dropoff, { steps: 20, label: 'to dropoff' });

    const receipt = await api(`/trips/${offer.tripId}/complete`, {
      method: 'POST',
      token,
    });
    console.log(
      `\n🏁 TRIP COMPLETE — fare $${receipt.fareFinal ?? receipt.fare}. ` +
        `Your phone should show the receipt + rating.\n`,
    );
    await wait(1500);
    sock.close();
    process.exit(0);
  });

  sock.on('trip:message', (m) => {
    if (!m || m.from === driver.user.id) return;
    setTimeout(
      () =>
        sock.emit('trip:message', {
          tripId: m.tripId,
          text: 'On my way, 2 min 🚗',
        }),
      800,
    );
  });
}

main().catch((e) => {
  console.error('demo failed:', e.message);
  process.exit(1);
});
