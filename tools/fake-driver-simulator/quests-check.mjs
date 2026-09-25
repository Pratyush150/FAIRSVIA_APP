// Driver incentives end-to-end against the running backend (Socket.IO + REST):
//   1. Admin creates a quest: "complete 3 trips in the next hour → 150 bonus".
//   2. A driver declines one real offer, then accepts and completes 3 real
//      rides (offer → accept → arrive → OTP start → complete).
//   3. After the 3rd completion the driver gets quest:completed; the quest
//      reads 3/3 completed+paid; exactly one 'bonus' ledger row of 150; the
//      earnings dashboard includes it (bonuses = 150).
//   4. GET /drivers/me/stats: accepted 3, declined 1 → acceptance 75%.
//   5. Whole-unit split (INR/UZS market): every driverPayout is whole.
// Run: node quests-check.mjs   (needs the backend + ubernav_postgres).
import { execSync } from 'node:child_process';
import { api, connect, login, once, onboardDriver, phone, wait } from './lib.mjs';

function assert(cond, msg) {
  if (!cond) throw new Error('ASSERT FAILED: ' + msg);
}
const psql = (sql) =>
  execSync(`docker exec ubernav_postgres psql -U ubernav -d ubernav -tAc "${sql}"`).toString().trim();

// A quiet corner of Pune (away from the demo drivers) so only our driver is near.
const pickup = { lat: 18.6012, lng: 73.7188 };
const dropoff = { lat: 18.5902, lng: 73.7388 };

async function requestTrip(rider) {
  return api('/trips', {
    method: 'POST',
    token: rider.token,
    body: {
      pickupLat: pickup.lat, pickupLng: pickup.lng,
      dropoffLat: dropoff.lat, dropoffLng: dropoff.lng,
      tier: 'premium', paymentMode: 'cash',
    },
  });
}

async function main() {
  const admin = await login('+19900000001');
  assert(admin.user.role === 'admin', 'admin login');
  const now = Date.now();
  const quest = await api('/admin/quests', {
    method: 'POST',
    token: admin.token,
    body: {
      title: `Sim quest ${now % 100000}: complete 3 trips`,
      tiers: ['premium'],
      targetTrips: 3,
      startsAt: new Date(now - 60_000).toISOString(),
      endsAt: new Date(now + 3600_000).toISOString(),
      bonusAmount: 150,
    },
  });
  console.log(`1. admin created quest ${quest.id.slice(0, 8)}: ${quest.title} (bonus ${quest.bonusAmount} ${quest.currency})`);

  const driver = await login(phone('95'));
  await onboardDriver(driver.token, 'premium');
  const dSock = await connect(driver.token);
  dSock.emit('driver:status', { status: 'online' });
  await wait(300);
  dSock.emit('driver:location', { lat: pickup.lat + 0.001, lng: pickup.lng, heading: 0, speed: 0 });
  await wait(400);
  const questDone = [];
  dSock.on('quest:completed', (e) => questDone.push(e));

  const rider = await login(phone('96'));
  const rSock = await connect(rider.token);

  // --- decline one real offer ---
  {
    const offerP = once(dSock, 'trip:offer', 20000);
    const trip = await requestTrip(rider);
    const offer = await offerP;
    assert(offer.tripId === trip.id, 'offer for our trip');
    dSock.emit('trip:decline', { tripId: offer.tripId });
    await wait(500);
    await api(`/trips/${trip.id}/cancel`, { method: 'POST', token: rider.token, body: {} }).catch(() => undefined);
    console.log(`2. declined offer ${trip.id.slice(0, 8)} (rider then cancelled)`);
    await wait(500);
  }

  // --- 3 real rides ---
  const payouts = [];
  for (let i = 1; i <= 3; i++) {
    dSock.emit('driver:location', { lat: pickup.lat + 0.001, lng: pickup.lng, heading: 0, speed: 0 });
    await wait(300);
    const offerP = once(dSock, 'trip:offer', 20000);
    const acceptedP = once(rSock, 'trip:accepted', 25000);
    const trip = await requestTrip(rider);
    const offer = await offerP;
    assert(offer.tripId === trip.id, `offer ${i} for our trip`);
    dSock.emit('trip:accept', { tripId: offer.tripId });
    await acceptedP;
    dSock.emit('driver:location', { lat: pickup.lat, lng: pickup.lng, heading: 90, speed: 8 });
    await wait(300);
    await api(`/trips/${trip.id}/arrived`, { method: 'POST', token: driver.token });
    const rv = await api(`/trips/${trip.id}`, { token: rider.token });
    await api(`/trips/${trip.id}/start`, { method: 'POST', token: driver.token, body: { otp: rv.startOtp } });
    dSock.emit('driver:location', { lat: dropoff.lat, lng: dropoff.lng, heading: 90, speed: 0 });
    await wait(400);
    const receipt = await api(`/trips/${trip.id}/complete`, { method: 'POST', token: driver.token });
    payouts.push(receipt);
    await wait(300);
    const qs = await api('/drivers/me/quests', { token: driver.token });
    const q = qs.find((x) => x.id === quest.id);
    console.log(
      `   ride ${i}: fare ${receipt.fareFinal} ${receipt.currency} → driver ${receipt.driverPayout} + platform ${receipt.platformFee}` +
        ` | quest ${q.progress}/${q.target} completed=${q.completed} paid=${q.paid}`,
    );
    if (i < 3) assert(!q.completed && !q.paid, `not complete after ${i}`);
  }

  // --- the bonus ---
  await wait(500);
  assert(questDone.some((e) => e.questId === quest.id), 'driver got quest:completed');
  const ev = questDone.find((e) => e.questId === quest.id);
  console.log(`3. driver ← quest:completed: "${ev.message}"`);
  const q = (await api('/drivers/me/quests', { token: driver.token })).find((x) => x.id === quest.id);
  assert(q.progress === 3 && q.completed && q.paid, 'quest 3/3 paid');
  const bonusRows = psql(
    `select count(*)||':'||coalesce(sum(amount),0) from ledger_entries where driver_id='${driver.user.id}' and type='bonus'`,
  );
  assert(bonusRows === '1:150.00', `exactly one 150 bonus row (got ${bonusRows})`);
  const earn = await api('/drivers/me/earnings?range=today', { token: driver.token });
  assert(earn.bonuses === 150, `earnings bonuses 150 (got ${earn.bonuses})`);
  const rideSum = payouts.reduce((a, r) => a + (r.driverPayout ?? 0), 0);
  console.log(`   earnings today: total ${earn.total} = rides ${rideSum} + bonus ${earn.bonuses}; ledger bonus rows ${bonusRows}`);
  assert(Math.abs(earn.total - (rideSum + 150)) < 0.01, 'earnings total includes the bonus');

  // --- rates ---
  const stats = await api('/drivers/me/stats', { token: driver.token });
  console.log(`4. stats: offers ${stats.offers}, accepted ${stats.accepted}, declined ${stats.declined}, expired ${stats.expired} → acceptance ${stats.acceptanceRate}, cancellation ${stats.cancellationRate}`);
  assert(stats.accepted === 3 && stats.declined === 1 && stats.acceptanceRate === 0.75, 'acceptance 75%');
  assert(stats.cancellationRate === 0, 'no cancellations');

  // --- whole-unit split ---
  const currency = payouts[0].currency;
  if (currency === 'INR' || currency === 'UZS') {
    for (const r of payouts) {
      assert(Number.isInteger(r.driverPayout), `whole driver payout (${r.driverPayout})`);
      assert(Math.abs(r.driverPayout + r.platformFee - r.fareFinal) < 0.005, 'split sums to fare');
    }
    console.log(`5. whole-unit split OK in ${currency}: ${payouts.map((r) => `${r.fareFinal}=${r.driverPayout}+${r.platformFee}`).join(', ')}`);
  }

  await api(`/admin/quests/${quest.id}`, { method: 'PATCH', token: admin.token, body: { active: false } });
  dSock.emit('driver:status', { status: 'offline' });
  dSock.close();
  rSock.close();
  console.log('\n✅ QUESTS SIM OK — decline + 3 real rides → quest 3/3 → one 150 bonus → in earnings; acceptance 75%');
  process.exit(0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
