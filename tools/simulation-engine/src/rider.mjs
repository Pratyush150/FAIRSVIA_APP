// Rider actor. Models a realistic rider journey with configurable behavior:
// request an estimate, book a tier, wait for a match, sometimes cancel while
// waiting, ride to completion, then sometimes rate + tip. Every timing and
// outcome is reported into the shared Metrics instance, and anomalies (no
// drivers, socket errors, unexpected states) are recorded as failures.

import { api, login, connect, onceEvent, phone, wait } from './client.mjs';
import { pickTrip, pickTier } from './geo.mjs';
import { TripRegistry } from './registry.mjs';

export class Rider {
  constructor(metrics, behavior = {}) {
    this.m = metrics;
    this.b = {
      cancelWhileSearchingRate: 0.06, // fraction that give up before match
      cancelMaxWaitMs: 8000, // if unmatched by this, may cancel
      rateRate: 0.8,
      tipRate: 0.5,
      paymentMode: 'card',
      // Client-side give-up. This is only a safety net for a genuinely lost
      // socket: it MUST sit above the backend's authoritative match window
      // (MATCH_WINDOW_MS ~45s, during which dispatch keeps re-sweeping and will
      // emit trip:accepted or trip:no_drivers). A real rider waits minutes, not
      // seconds — a too-short client timeout abandons trips dispatch would have
      // filled and races the driver into a missing-OTP start.
      matchTimeoutMs: 50000,
      ...behavior,
    };
    this.socket = null;
    this.token = null;
    this.user = null;
  }

  async setup() {
    const { token, user } = await login(phone());
    this.token = token;
    this.user = user;
    this.socket = await connect(token);
    this.socket.on('disconnect', () => this.m.incr('ws.rider.disconnects'));
  }

  /** Run one full trip. Returns an outcome string for the orchestrator. */
  async ride() {
    const { origin, dest } = pickTrip();
    const tier = pickTier();
    this.m.incr('rides.requested');

    // 1) Fare estimate (the REST hot path).
    try {
      const t0 = Date.now();
      await api('/trips/estimate', {
        method: 'POST',
        token: this.token,
        body: { pickupLat: origin.lat, pickupLng: origin.lng, dropoffLat: dest.lat, dropoffLng: dest.lng },
      });
      this.m.timer('estimate.ms', Date.now() - t0);
    } catch (e) {
      this.m.error('rider', 'estimate', e);
      return 'estimate_failed';
    }

    // 2) Create the trip.
    let trip;
    try {
      const t0 = Date.now();
      trip = await api('/trips', {
        method: 'POST',
        token: this.token,
        body: {
          pickupLat: origin.lat, pickupLng: origin.lng,
          dropoffLat: dest.lat, dropoffLng: dest.lng,
          tier, paymentMode: this.b.paymentMode,
          pickupAddr: origin.__spot?.name, dropoffAddr: dest.__spot?.name,
        },
      });
      this.m.timer('createTrip.ms', Date.now() - t0);
    } catch (e) {
      this.m.error('rider', 'create_trip', e);
      return 'create_failed';
    }
    TripRegistry.register(trip.id, { startOtp: trip.startOtp, riderId: this.user.id });

    // 3) Await a match — racing accept vs. no_drivers vs. our own impatience.
    const requestedAt = Date.now();
    const willCancel = Math.random() < this.b.cancelWhileSearchingRate;
    let matched;
    try {
      matched = await this.awaitMatch(trip.id, willCancel);
    } catch (e) {
      this.m.error('rider', 'await_match', e);
      TripRegistry.done(trip.id);
      return 'match_error';
    }

    if (matched === 'no_drivers') {
      this.m.incr('matches.no_drivers');
      this.m.fail('no_drivers', { actor: 'rider', op: 'match', detail: `${origin.__spot?.name}→${dest.__spot?.name}` });
      TripRegistry.done(trip.id);
      return 'no_drivers';
    }
    if (matched === 'rider_cancelled') {
      this.m.incr('rides.cancelled_searching');
      await this.cancel(trip.id, 'changed_mind');
      TripRegistry.done(trip.id);
      return 'cancelled_searching';
    }
    if (matched === 'timeout') {
      this.m.incr('matches.timeout');
      this.m.fail('match_timeout', { actor: 'rider', op: 'match', detail: `no match in ${this.b.matchTimeoutMs}ms` });
      TripRegistry.done(trip.id);
      return 'match_timeout';
    }

    // matched === accepted payload
    this.m.timer('match.ms', Date.now() - requestedAt);
    this.m.incr('matches.success');

    // 4) Ride to completion (driver drives the car; we await lifecycle events).
    try {
      await onceEvent(this.socket, 'trip:started', 60000);
      this.m.incr('rides.started');
      const receipt = await onceEvent(this.socket, 'trip:completed', 120000);
      this.m.timer('ride.e2e.ms', Date.now() - requestedAt);
      this.m.incr('rides.completed');
      await this.postTrip(trip.id, receipt);
      TripRegistry.done(trip.id);
      return 'completed';
    } catch (e) {
      this.m.error('rider', 'ride_lifecycle', e);
      this.m.fail('stuck_trip', { actor: 'rider', op: 'lifecycle', detail: `trip ${trip.id}: ${e.message}` });
      TripRegistry.done(trip.id);
      return 'stuck';
    }
  }

  awaitMatch(tripId, willCancel) {
    return new Promise((resolve) => {
      let settled = false;
      const done = (v) => { if (!settled) { settled = true; cleanup(); resolve(v); } };
      const onAccepted = (p) => { if (p.tripId === tripId) done(p); };
      const onNoDrivers = (p) => { if (p.tripId === tripId) done('no_drivers'); };
      const cleanup = () => {
        this.socket.off('trip:accepted', onAccepted);
        this.socket.off('trip:no_drivers', onNoDrivers);
        clearTimeout(hardTimer);
        clearTimeout(cancelTimer);
      };
      this.socket.on('trip:accepted', onAccepted);
      this.socket.on('trip:no_drivers', onNoDrivers);
      const hardTimer = setTimeout(() => done('timeout'), this.b.matchTimeoutMs);
      const cancelTimer = willCancel
        ? setTimeout(() => done('rider_cancelled'), this.b.cancelMaxWaitMs + Math.random() * 3000)
        : null;
    });
  }

  async postTrip(tripId, receipt) {
    if (Math.random() < this.b.rateRate) {
      try {
        await api(`/trips/${tripId}/rating`, {
          method: 'POST', token: this.token,
          body: { stars: 4 + Math.round(Math.random()) },
        });
        this.m.incr('ratings.submitted');
      } catch (e) { this.m.error('rider', 'rate', e); }
    }
    if (Math.random() < this.b.tipRate && this.b.paymentMode === 'card') {
      try {
        await api(`/payments/${tripId}/tip`, {
          method: 'POST', token: this.token,
          body: { amount: [2, 3, 5][Math.floor(Math.random() * 3)] },
        });
        this.m.incr('tips.submitted');
      } catch (e) { this.m.error('rider', 'tip', e); }
    }
  }

  async cancel(tripId, reason) {
    try {
      await api(`/trips/${tripId}/cancel`, { method: 'POST', token: this.token, body: { reason } });
    } catch (e) { this.m.error('rider', 'cancel', e); }
  }

  teardown() {
    try { this.socket?.disconnect(); } catch { /* ignore */ }
  }
}
