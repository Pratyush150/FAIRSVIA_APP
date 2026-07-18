// Driver actor. Goes online, receives dispatch offers, decides accept/decline/
// let-expire (configurable — this is what exercises the offer cascade the old
// auto-accept-only scripts never touched), then drives ROAD-FOLLOWING routes to
// pickup and dropoff via OSRM, streaming location with realistic bearing.

import { api, login, connect, onboardDriver, onceEvent, phone, wait } from './client.mjs';
import { route as osrmRoute, drive, pickHotspot, pickTier } from './geo.mjs';
import { TripRegistry } from './registry.mjs';
import { TICK_MS, TIME_SCALE, DRIVE_SPEED_MPS } from './config.mjs';

export class Driver {
  constructor(metrics, behavior = {}) {
    this.m = metrics;
    this.b = {
      acceptRate: process.env.ACCEPT_RATE != null ? Number(process.env.ACCEPT_RATE) : 0.92, // of offers received
      declineRate: process.env.DECLINE_RATE != null ? Number(process.env.DECLINE_RATE) : 0.05, // explicit decline
      // remainder => let the offer expire (silent)
      goOfflineAfter: Infinity, // rides before ending the shift
      ...behavior,
    };
    this.pos = pickHotspot();
    this.tier = behavior.tier || pickTier();
    this.idle = true;
    this.rides = 0;
    this.stopped = false;
    this.cancelled = new Set(); // tripIds the rider cancelled out from under us
  }

  async setup() {
    this.phone = phone(); // kept so the token can be refreshed by re-login
    const { token } = await login(this.phone);
    this.token = token;
    await onboardDriver(token, this.tier);
    this.socket = await connect(token);
    this.socket.on('disconnect', () => this.m.incr('ws.driver.disconnects'));
    await api('/drivers/status', { method: 'POST', token, body: { status: 'online' } });
    this.emitLocation();
    // Heartbeat presence so we stay in the GEO index while idle.
    this.hb = setInterval(() => { if (!this.stopped) this.emitLocation(); }, 3000);
    this.socket.on('trip:offer', (o) => this.onOffer(o));
    // A real driver app stops navigating the moment the rider cancels; model it
    // so we abort the trip instead of driving to a pickup that no longer exists.
    this.socket.on('trip:cancelled', (c) => {
      if (c?.tripId) { this.cancelled.add(c.tripId); this.m.incr('trips.cancelled_by_rider'); }
    });
    this.m.incr('drivers.online');
  }

  emitLocation(extra = {}) {
    this.socket.emit('driver:location', {
      lat: this.pos.lat, lng: this.pos.lng,
      heading: extra.heading ?? 0, speed: extra.speed ?? 0,
    });
  }

  async onOffer(offer) {
    if (!this.idle || this.stopped) return; // dispatch locks per-driver, but be safe
    this.m.incr('offers.received');
    const roll = Math.random();
    if (roll < this.b.declineRate) {
      this.socket.emit('trip:decline', { tripId: offer.tripId });
      this.m.incr('offers.declined');
      return;
    }
    if (roll >= this.b.declineRate + this.b.acceptRate) {
      this.m.incr('offers.expired_by_driver'); // let it time out (no response)
      return;
    }
    // Accept.
    this.idle = false;
    this.socket.emit('trip:accept', { tripId: offer.tripId });
    this.m.incr('offers.accepted');
    try {
      await onceEvent(this.socket, 'trip:assigned', 8000);
    } catch {
      // Lost the race (another driver won / offer expired). Re-pool.
      this.m.incr('offers.accept_lost');
      this.idle = true;
      return;
    }
    try {
      await this.runTrip(offer);
    } catch (e) {
      this.m.error('driver', 'run_trip', e);
      this.m.fail('driver_trip_error', { actor: 'driver', op: 'run_trip', detail: e.message, status: e.status });
    } finally {
      this.idle = true;
      this.rides += 1;
      if (this.rides >= this.b.goOfflineAfter) await this.goOffline();
    }
  }

  async runTrip(offer) {
    const tripId = offer.tripId;
    const pickup = { lat: offer.pickup.lat, lng: offer.pickup.lng };
    const dropoff = { lat: offer.dropoff.lat, lng: offer.dropoff.lng };
    const aborted = () => this.stopped || this.cancelled.has(tripId);

    // Drive to pickup (road-following). Bail if the rider cancels en route.
    const toPickup = await osrmRoute(this.pos, pickup);
    await drive(toPickup.points, {
      speedMps: DRIVE_SPEED_MPS, tickMs: TICK_MS, timeScale: TIME_SCALE,
      shouldStop: aborted,
      onTick: async (p) => { this.pos = p; this.emitLocation({ heading: p.heading, speed: DRIVE_SPEED_MPS }); },
    });
    if (aborted()) return; // rider cancelled — driver is already back in the pool

    await api(`/trips/${tripId}/arrived`, { method: 'POST', token: this.token });
    this.m.incr('trips.arrived');

    // Get the rider's start OTP from the shared registry and start the trip.
    if (aborted()) return;
    const otp = await this.waitForOtp(offer.tripId);
    if (!otp) {
      // A cancel that lands during the OTP wait is expected churn, not a fault.
      if (!aborted()) {
        this.m.fail('missing_otp', { actor: 'driver', op: 'start', detail: `no OTP for trip ${offer.tripId}` });
      }
      return;
    }
    try {
      await api(`/trips/${offer.tripId}/start`, { method: 'POST', token: this.token, body: { otp } });
      this.m.incr('trips.started');
    } catch (e) {
      this.m.error('driver', 'start', e);
      this.m.fail('start_failed', { actor: 'driver', op: 'start', detail: e.message, status: e.status });
      return;
    }

    // Drive to dropoff (road-following).
    const toDrop = await osrmRoute(pickup, dropoff);
    await drive(toDrop.points, {
      speedMps: DRIVE_SPEED_MPS, tickMs: TICK_MS, timeScale: TIME_SCALE,
      shouldStop: () => this.stopped,
      onTick: async (p) => { this.pos = p; this.emitLocation({ heading: p.heading, speed: DRIVE_SPEED_MPS }); },
    });
    this.pos = dropoff;

    await api(`/trips/${offer.tripId}/complete`, { method: 'POST', token: this.token });
    this.m.incr('trips.completed');
  }

  async waitForOtp(tripId, tries = 30) {
    for (let i = 0; i < tries; i++) {
      const otp = TripRegistry.otp(tripId);
      if (otp) return otp;
      // Stop early if a cancellation lands mid-wait — the trip:cancelled event
      // can arrive slightly after we start polling, so honour it here too.
      if (this.cancelled.has(tripId)) return null;
      await wait(100);
    }
    return null;
  }

  async goOffline() {
    if (this.stopped) return;
    try { await api('/drivers/status', { method: 'POST', token: this.token, body: { status: 'offline' } }); } catch { /* ignore */ }
    this.m.incr('drivers.offline');
  }

  async teardown() {
    this.stopped = true;
    clearInterval(this.hb);
    try { this.socket?.disconnect(); } catch { /* ignore */ }
  }
}
