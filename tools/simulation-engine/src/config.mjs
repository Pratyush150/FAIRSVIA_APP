// Central config. Everything is env-overridable so the engine can target the
// local dev stack (default) or a remote/prod-like host.

export const BASE = process.env.BASE_URL || 'http://localhost:3000/api/v1';
export const WS = process.env.WS_URL || 'http://localhost:3000';

// OSRM routing (self-hosted). Used to drive road-following actor motion and to
// pick realistic pickup/dropoff routes. Empty string => fall back to
// straight-line interpolation (still works, just less realistic).
export const OSRM = process.env.OSRM_BASE_URL || 'http://localhost:5000';

// Prometheus metrics endpoint on the backend, scraped to correlate client-side
// observations with server-side queue depth / counters.
export const METRICS_URL = process.env.METRICS_URL || `${BASE.replace(/\/api\/v1$/, '')}/metrics`;

// Simulation time compression: a real 10-minute drive is boring to wait for, so
// actor motion advances `TIME_SCALE`x faster than wall-clock. 1 = real time.
export const TIME_SCALE = Number(process.env.TIME_SCALE || 30);

// Location heartbeat cadence (wall-clock ms) while a driver is moving.
export const TICK_MS = Number(process.env.TICK_MS || 250);

// Assumed driving speed (m/s) when no per-segment speed is available (~22 mph).
export const DRIVE_SPEED_MPS = Number(process.env.DRIVE_SPEED_MPS || 10);
