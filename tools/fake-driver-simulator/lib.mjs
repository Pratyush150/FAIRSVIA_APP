import { io } from 'socket.io-client';

export const BASE = process.env.BASE_URL || 'http://localhost:3000/api/v1';
export const WS = process.env.WS_URL || 'http://localhost:3000';

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
  return `+91${prefix}${String(n).padStart(9, '0').slice(0, 9)}`;
}

export async function onboardDriver(token, tier = 'economy') {
  return api('/drivers/onboarding', {
    method: 'POST',
    token,
    body: {
      vehicleMake: 'Toyota',
      vehicleModel: 'Etios',
      vehicleColor: 'White',
      plateNumber: 'KA01AB' + Math.floor(1000 + (Date.now() % 9000)),
      vehicleTier: tier,
      licenseNo: 'DL-' + (Date.now() % 100000),
    },
  });
}
