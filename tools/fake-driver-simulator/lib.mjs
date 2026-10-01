import { io } from 'socket.io-client';

export const BASE = process.env.BASE_URL || 'http://localhost:3200/api/v1';
export const WS = process.env.WS_URL || 'http://localhost:3200';

/** Minimal REST helper against the backend. When `expectError` is set, a
 * non-2xx response is returned as `{ status }` instead of throwing. */
export async function api(
  path,
  { method = 'GET', token, body, expectError = false } = {},
) {
  const res = await fetch(BASE + path, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!res.ok) {
    if (expectError) return { status: res.status };
    throw new Error(`${method} ${path} -> ${res.status}: ${await res.text()}`);
  }
  return res.status === 204 ? null : res.json();
}

/** OTP login (dev mode echoes the code). */
export async function login(phone) {
  const { devCode } = await api('/auth/otp/request', {
    method: 'POST',
    body: { phone },
  });
  const { accessToken, user } = await api('/auth/otp/verify', {
    method: 'POST',
    body: { phone, code: devCode },
  });
  return { token: accessToken, user };
}

/** Connect an authenticated Socket.IO client. */
export function connect(token) {
  return new Promise((resolve, reject) => {
    const socket = io(WS, { auth: { token }, transports: ['websocket'] });
    const t = setTimeout(() => reject(new Error('ws connect timeout')), 6000);
    socket.on('connect', () => {
      clearTimeout(t);
      resolve(socket);
    });
    socket.on('connect_error', (e) => {
      clearTimeout(t);
      reject(e);
    });
  });
}

export const wait = (ms) => new Promise((r) => setTimeout(r, ms));

/** Resolve on the next occurrence of [event], or reject on timeout. */
export function once(socket, event, timeoutMs = 18000) {
  return new Promise((resolve, reject) => {
    const t = setTimeout(
      () => reject(new Error(`timeout waiting for "${event}"`)),
      timeoutMs,
    );
    socket.once(event, (data) => {
      clearTimeout(t);
      resolve(data);
    });
  });
}

let seq = 0;
/** Unique-ish phone number per call. */
export function phone(prefix = '9') {
  seq += 1;
  const n = (Date.now() % 10000000) * 10 + (seq % 10);
  return `+1${prefix}${String(n).padStart(9, '0').slice(0, 9)}`;
}

// Pilot-realistic test drivers (Pune): an Indian name and a Maharashtra
// plate, so screens and demos never show "Driver" with a US plate. Drivers
// need a name before they can go online.
const NAMES = ['Rahul Patil', 'Amit Deshmukh', 'Sneha Kulkarni', 'Vikram Joshi', 'Priya Shinde', 'Sagar Pawar'];
// A vehicle that fits the tier: an auto-rickshaw for 'auto', a scooter for
// 'bike' (Pune's bike taxis are mostly Activas), a sedan for the car tiers.
const VEHICLES = {
  auto: { vehicleMake: 'Bajaj', vehicleModel: 'RE Compact', vehicleColor: 'Green/Yellow' },
  bike: { vehicleMake: 'Honda', vehicleModel: 'Activa 6G', vehicleColor: 'Black' },
};
const CAR = { vehicleMake: 'Maruti Suzuki', vehicleModel: 'Dzire', vehicleColor: 'White' };
/** Onboard [token]'s user as a driver of [tier]: economy, comfort, xl,
 *  premium, auto or bike. */
export async function onboardDriver(token, tier = 'economy') {
  const n = Date.now();
  await api('/users/me', { method: 'PATCH', token, body: { fullName: NAMES[n % NAMES.length] } });
  const letters = String.fromCharCode(65 + (n % 26), 65 + (Math.floor(n / 32) % 26));
  return api('/drivers/onboarding', {
    method: 'POST',
    token,
    body: {
      ...(VEHICLES[tier] ?? CAR),
      plateNumber: `MH12${letters}${String(1000 + (n % 9000))}`,
      vehicleTier: tier,
      licenseNo: 'MH12-' + (n % 100000),
    },
  });
}
