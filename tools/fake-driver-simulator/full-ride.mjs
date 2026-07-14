// Scripted end-to-end verification of the full ride lifecycle over Socket.IO.
// Requires the backend running. Run: npm run full-ride
import {
  api,
  connect,
  login,
  once,
  onboardDriver,
  phone,
  wait,
} from './lib.mjs';

function assert(cond, msg) {
  if (!cond) throw new Error('ASSERT FAILED: ' + msg);
}

async function main() {
  const pickup = { lat: 12.9611, lng: 77.6387 };
  const dropoff = { lat: 12.9674, lng: 77.5904 };

  // --- Driver: login, onboard, connect, go online near the pickup ---
  const driver = await login(phone('90'));
  await onboardDriver(driver.token, 'economy');
  const dSock = await connect(driver.token);
  console.log('• driver connected');

  dSock.emit('driver:status', { status: 'online' });
  await wait(300);
  dSock.emit('driver:location', {
    lat: pickup.lat + 0.001,
    lng: pickup.lng + 0.001,
    heading: 90,
    speed: 0,
  });
  await wait(400);
  console.log('• driver online + broadcasting location');

  // --- Rider: login, connect ---
  const rider = await login(phone('91'));
  const rSock = await connect(rider.token);
  console.log('• rider connected');

  // Arm listeners before requesting.
  const matchingP = once(rSock, 'trip:matching');
  const offerP = once(dSock, 'trip:offer');
  const acceptedP = once(rSock, 'trip:accepted');

  // Optionally exercise the cash-settlement path (PAYMENT_MODE=cash).
  const paymentMode = process.env.PAYMENT_MODE === 'cash' ? 'cash' : 'card';
  const trip = await api('/trips', {
    method: 'POST',
    token: rider.token,
    body: {
      pickupLat: pickup.lat,
      pickupLng: pickup.lng,
      dropoffLat: dropoff.lat,
      dropoffLng: dropoff.lng,
      tier: 'economy',
      pickupAddr: 'Indiranagar',
      dropoffAddr: 'MG Road',
      paymentMode,
    },
  });
  assert(trip.status === 'requested', 'trip created in requested');
  assert(trip.paymentMode === paymentMode, `trip paymentMode is ${paymentMode}`);
  console.log(`• trip created ${trip.id} (${trip.status}, ${paymentMode})`);

  await matchingP;
  console.log('• rider ← trip:matching');

  const offer = await offerP;
  assert(offer.tripId === trip.id, 'offer is for this trip');
  console.log(`• driver ← trip:offer  ₹${offer.fare} (${offer.expiresInSec}s)`);

  dSock.emit('trip:accept', { tripId: offer.tripId });
  const accepted = await acceptedP;
  assert(accepted.vehicle.plate, 'rider sees vehicle plate');
  console.log(
    `• rider ← trip:accepted  car=${accepted.vehicle.make} ${accepted.vehicle.model} plate=${accepted.vehicle.plate}`,
  );

  // --- In-trip chat: rider ↔ driver, both directions over WS ---
  const toDriverP = once(dSock, 'trip:message');
  rSock.emit('trip:message', { tripId: trip.id, text: 'Hi, at the black gate' });
  const toDriver = await toDriverP;
  assert(toDriver.text === 'Hi, at the black gate', 'driver receives rider message');
  const toRiderP = once(rSock, 'trip:message');
  dSock.emit('trip:message', { tripId: trip.id, text: 'On my way, 2 min' });
  const toRider = await toRiderP;
  assert(toRider.text === 'On my way, 2 min', 'rider receives driver message');
  console.log('• chat round-trip ok (rider↔driver)');

  // --- Driver drives to pickup; rider receives live location ---
  const locP = once(rSock, 'trip:driver_location');
  dSock.emit('driver:location', { lat: pickup.lat, lng: pickup.lng, heading: 90, speed: 12 });
  const loc = await locP;
  assert(loc.tripId === trip.id, 'driver_location tagged with tripId');
  console.log(`• rider ← trip:driver_location (${loc.lat}, ${loc.lng})`);

  // --- Arrived ---
  const arrivedP = once(rSock, 'trip:arrived');
  await api(`/trips/${trip.id}/arrived`, { method: 'POST', token: driver.token });
  await arrivedP;
  console.log('• rider ← trip:arrived');

  // --- Start with OTP (rider sees it; driver must not) ---
  const riderView = await api(`/trips/${trip.id}`, { token: rider.token });
  const driverView = await api(`/trips/${trip.id}`, { token: driver.token });
  assert(riderView.startOtp, 'rider sees start OTP');
  assert(driverView.startOtp === null, 'driver does NOT see start OTP');
  console.log(`• start OTP = ${riderView.startOtp} (hidden from driver ✓)`);

  const startedP = once(rSock, 'trip:started');
  await api(`/trips/${trip.id}/start`, {
    method: 'POST',
    token: driver.token,
    body: { otp: riderView.startOtp },
  });
  await startedP;
  console.log('• rider ← trip:started');

  // --- Complete ---
  const completedP = once(rSock, 'trip:completed');
  const receipt = await api(`/trips/${trip.id}/complete`, {
    method: 'POST',
    token: driver.token,
  });
  await completedP;
  console.log(`• rider ← trip:completed  ₹${receipt.fareFinal}`);
  assert(receipt.paymentMode === paymentMode, `receipt paymentMode ${paymentMode}`);

  const final = await api(`/trips/${trip.id}`, { token: rider.token });
  assert(final.status === 'completed', 'final status completed');

  // --- Payment: capture split (20% platform fee, 80% driver payout) ---
  assert(receipt.fareFinal > 0, 'receipt has a positive fare');
  const expectedFee = Math.round(receipt.fareFinal * 0.2 * 100) / 100;
  const expectedPayout = Math.round((receipt.fareFinal - expectedFee) * 100) / 100;
  assert(
    receipt.platformFee === expectedFee,
    `platform fee ${receipt.platformFee} === ${expectedFee}`,
  );
  assert(
    receipt.driverPayout === expectedPayout,
    `driver payout ${receipt.driverPayout} === ${expectedPayout}`,
  );
  console.log(
    `• payment split  fare=₹${receipt.fareFinal}  fee=₹${receipt.platformFee}  payout=₹${receipt.driverPayout}`,
  );

  // Receipt endpoint should report the captured ride payment.
  const receiptDoc = await api(`/payments/${trip.id}/receipt`, {
    token: rider.token,
  });
  assert(receiptDoc.payment, 'receipt has a payment record');
  // Card rides are captured through the provider; cash rides are collected in
  // person (no provider charge), so their payment settles as `collected`.
  const expectedStatus = paymentMode === 'cash' ? 'collected' : 'captured';
  assert(
    receiptDoc.payment.status === expectedStatus,
    `payment ${expectedStatus} (${paymentMode})`,
  );
  assert(receiptDoc.payment.method === paymentMode, `payment method ${paymentMode}`);
  assert(receiptDoc.payment.kind === 'ride', 'payment kind is ride');
  console.log(
    `• receipt  status=${receiptDoc.payment.status}  method=${receiptDoc.payment.method}  kind=${receiptDoc.payment.kind}`,
  );

  // --- Tip: goes 100% to the driver payout ---
  const tipRes = await api(`/payments/${trip.id}/tip`, {
    method: 'POST',
    token: rider.token,
    body: { amount: 25 },
  });
  assert(tipRes.tip === 25, 'tip recorded');
  assert(
    tipRes.driverPayout === Math.round((expectedPayout + 25) * 100) / 100,
    'tip added fully to driver payout',
  );
  console.log(`• tip ₹25 → driver payout now ₹${tipRes.driverPayout}`);

  // --- Two-way ratings ---
  const rated = await api(`/trips/${trip.id}/rating`, {
    method: 'POST',
    token: rider.token,
    body: { stars: 5, comment: 'Smooth ride', tags: ['clean_car'] },
  });
  assert(rated.toUser === driver.user.id, 'rider rated the driver');
  console.log(`• rider → driver rating ${rated.stars}★`);

  const ratedBack = await api(`/trips/${trip.id}/rating`, {
    method: 'POST',
    token: driver.token,
    body: { stars: 4 },
  });
  assert(ratedBack.toUser === rider.user.id, 'driver rated the rider');
  console.log(`• driver → rider rating ${ratedBack.stars}★`);

  // Driver's stored average should reflect the 5★ (from default 5.00/0 → 5.00/1).
  const myRating = await api(`/trips/${trip.id}/rating`, { token: rider.token });
  assert(myRating && myRating.stars === 5, "rider's rating persisted");

  // Verify the driver returned to earnings.
  const earnings = await api('/drivers/me/earnings?range=today', {
    token: driver.token,
  });
  assert(earnings.trips >= 1, 'driver earnings reflect the trip');

  // --- Payout ledger + withdrawal (B1) ---
  const bal = await api('/drivers/balance', { token: driver.token });
  assert(bal.balance > 0, 'ledger balance is positive after a paid ride');
  // For a card ride, the ledger holds the net payout + the tip.
  const expectedLedger =
    Math.round((receipt.driverPayout + 25) * 100) / 100;
  assert(
    Math.abs(bal.balance - expectedLedger) < 0.01,
    `ledger balance ₹${bal.balance} === payout+tip ₹${expectedLedger}`,
  );
  assert(
    bal.entries.some((e) => e.type === 'earning') &&
      bal.entries.some((e) => e.type === 'tip'),
    'ledger has earning + tip entries',
  );
  console.log(`• ledger balance ₹${bal.balance} (earning + tip)`);

  // Withdraw part of the balance; it debits and the new balance matches.
  const withdrawAmt = Math.floor(bal.balance / 2);
  const wd = await api('/drivers/balance/withdraw', {
    method: 'POST',
    token: driver.token,
    body: { amount: withdrawAmt },
  });
  assert(wd.withdrawn === withdrawAmt, 'withdrawal amount recorded');
  const afterBal = await api('/drivers/balance', { token: driver.token });
  assert(
    Math.abs(afterBal.balance - (bal.balance - withdrawAmt)) < 0.01,
    'balance debited by the withdrawal',
  );
  // Over-withdrawing the remaining balance is rejected.
  const over = await api('/drivers/balance/withdraw', {
    method: 'POST',
    token: driver.token,
    body: { amount: afterBal.balance + 1000 },
    expectError: true,
  });
  assert(over.status === 400, 'over-withdrawal rejected (400)');
  console.log(`• withdrew ₹${withdrawAmt}, balance now ₹${afterBal.balance}`);

  console.log(
    `\n✅ FULL RIDE OK — requested→matching→accepted→arrived→in_progress→completed` +
      `\n   payment captured (split ₹${receipt.platformFee}/₹${receipt.driverPayout}), tip ₹25, two-way ratings recorded` +
      `\n   driver earnings today: ₹${earnings.total} over ${earnings.trips} trip(s)`,
  );

  // Clean up: take the driver out of the pool before disconnecting.
  dSock.emit('driver:status', { status: 'offline' });
  await wait(200);

  dSock.close();
  rSock.close();
  process.exit(0);
}

main().catch((e) => {
  console.error('❌ FAILED:', e.message);
  process.exit(1);
});
