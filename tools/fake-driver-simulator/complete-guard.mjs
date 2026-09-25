// Audit 2026-09-25 #4 + owner rule "the trip ends wherever the driver clicks".
// Drives two real rides over Socket.IO + REST:
//   A. driver taps Complete AT THE PICKUP -> trip completes (never refused),
//      charged max(minimum fare, metered) — NOT the up-front estimate.
//   B. RIDER taps "End trip here" (POST /trips/:id/end-early) mid-ride ->
//      completes for both parties at the same short-trip fare.
// Requires the backend running. Run: node complete-guard.mjs
import { api, connect, login, once, onboardDriver, phone, wait } from './lib.mjs';

function assert(cond, msg) {
  if (!cond) throw new Error('ASSERT FAILED: ' + msg);
}

const pickup = { lat: 25.7743, lng: -80.1937 };
const dropoff = { lat: 25.7806, lng: -80.242 }; // ~4.9 km

/** Online driver + rider, one cash ride accepted, arrived and started, the
 *  car still at the pickup. */
async function startedRide(tag) {
  const driver = await login(phone(tag + '3'));
  await onboardDriver(driver.token, 'economy');
  const dSock = await connect(driver.token);
  dSock.emit('driver:status', { status: 'online' });
  await wait(300);
  dSock.emit('driver:location', { lat: pickup.lat + 0.001, lng: pickup.lng + 0.001, heading: 90, speed: 0 });
  await wait(400);
  const rider = await login(phone(tag + '4'));
  const rSock = await connect(rider.token);
  const offerP = once(dSock, 'trip:offer');
  const acceptedP = once(rSock, 'trip:accepted');
  const trip = await api('/trips', {
    method: 'POST',
    token: rider.token,
    body: {
      pickupLat: pickup.lat, pickupLng: pickup.lng,
      dropoffLat: dropoff.lat, dropoffLng: dropoff.lng,
      tier: 'economy', paymentMode: 'cash',
    },
  });
  const offer = await offerP;
  dSock.emit('trip:accept', { tripId: offer.tripId });
  await acceptedP;
  dSock.emit('driver:location', { lat: pickup.lat, lng: pickup.lng, heading: 90, speed: 0 });
  await wait(300);
  await api(`/trips/${trip.id}/arrived`, { method: 'POST', token: driver.token });
  const riderView = await api(`/trips/${trip.id}`, { token: rider.token });
  await api(`/trips/${trip.id}/start`, { method: 'POST', token: driver.token, body: { otp: riderView.startOtp } });
  dSock.emit('driver:location', { lat: pickup.lat, lng: pickup.lng, heading: 90, speed: 0 });
  await wait(1500);
  return { driver, rider, dSock, rSock, trip, minFare: riderView.minFare };
}

async function main() {
  // --- A. Driver completes at the pickup ---
  const a = await startedRide('9');
  console.log(`A. trip ${a.trip.id.slice(0, 8)} started at the pickup; estimate ${a.trip.fareEstimate}, min fare ${a.minFare}`);
  const riderDoneA = once(a.rSock, 'trip:completed');
  const ra = await api(`/trips/${a.trip.id}/complete`, { method: 'POST', token: a.driver.token, body: {} });
  await riderDoneA;
  console.log(
    `   Complete at pickup -> 200, charged ${ra.fareFinal} (basis ${ra.breakdown.fareBasis}, ` +
      `${ra.breakdown.endedAwayFromDropoffM} m short of the drop-off, driven ${ra.distanceM} m, ${ra.durationS} s)`,
  );
  assert(ra.fareFinal < Number(a.trip.fareEstimate), 'NOT charged the full estimate');
  assert(ra.fareFinal === a.minFare, 'charged the minimum fare');
  assert(ra.breakdown.fareBasis === 'minimum', 'basis: minimum');
  assert(ra.breakdown.endedAwayFromDropoffM > 500, 'receipt records where it ended');
  for (const s of [a.dSock, a.rSock]) s.close();

  // --- B. Rider ends the ride early ---
  const b = await startedRide('8');
  console.log(`B. trip ${b.trip.id.slice(0, 8)} started; the RIDER taps "End trip here"`);
  const driverDoneB = once(b.dSock, 'trip:completed');
  const rb = await api(`/trips/${b.trip.id}/end-early`, { method: 'POST', token: b.rider.token, body: {} });
  const dEvt = await driverDoneB;
  console.log(
    `   end-early -> 200, charged ${rb.fareFinal} (basis ${rb.breakdown.fareBasis}, reason "${rb.breakdown.endReason}"); ` +
      `driver got trip:completed with ${dEvt.fareFinal}`,
  );
  assert(rb.fareFinal === b.minFare, 'rider early end: minimum fare');
  assert(dEvt.tripId === b.trip.id, 'driver notified via trip:completed');
  const rec = await api(`/payments/${b.trip.id}/receipt`, { token: b.rider.token });
  assert(rec.breakdown.endedEarly === true && rec.breakdown.fareBasis === 'minimum', 'rider receipt replays it');
  for (const s of [b.dSock, b.rSock]) s.close();

  console.log('\nPASS complete-guard: Complete ends anywhere at a short-trip fare; rider end-early works');
  process.exit(0);
}
main().catch((e) => {
  console.error('❌ FAILED:', e.message);
  process.exit(1);
});
