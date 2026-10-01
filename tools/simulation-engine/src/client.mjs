// Unified REST + WebSocket + auth client. Supersedes the two divergent
// `lib.mjs` copies (fake-driver-simulator vs load-test) with one shared surface.

import { io } from 'socket.io-client';
import { BASE, WS } from './config.mjs';

/** REST helper. Throws an Error with `.status`/`.bodyText` on non-2xx. */
export async function api(path, { method = 'GET', token, body, timeoutMs = 20000 } = {}) {
  const res = await fetch(BASE + path, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(timeoutMs),
  });
  const text = await res.text();
  if (!res.ok) {
    const e = new Error(`${method} ${path} -> ${res.status}`);
    e.status = res.status;
    e.bodyText = text;
    throw e;
  }
  return text ? JSON.parse(text) : null;
}

/** Phone-OTP login (dev devCode echo). Returns { token, user }. */
export async function login(phoneNum) {
  const { devCode } = await api('/auth/otp/request', {
    method: 'POST',
    body: { phone: phoneNum },
  });
  const { accessToken, user } = await api('/auth/otp/verify', {
    method: 'POST',
    body: { phone: phoneNum, code: devCode },
  });
  return { token: accessToken, user };
}

/** Open a Socket.IO connection with a JWT handshake. */
export function connect(token) {
  return new Promise((resolve, reject) => {
    const socket = io(WS, {
      auth: { token },
      transports: ['websocket'],
      reconnection: false,
    });
    const t = setTimeout(() => reject(new Error('ws connect timeout')), 10000);
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

/** Resolve the next `event`, or reject after `timeoutMs`. */
export function onceEvent(socket, event, timeoutMs = 20000) {
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new Error(`timeout: ${event}`)), timeoutMs);
    socket.once(event, (data) => {
      clearTimeout(t);
      resolve(data);
    });
  });
}

export const wait = (ms) => new Promise((r) => setTimeout(r, ms));

/** Onboard a driver (US vehicle + FL plate). Returns the driver profile. */
export async function onboardDriver(token, tier = 'economy') {
  // Drivers need a name before they can go online (NAME_REQUIRED).
  await api('/users/me', { method: 'PATCH', token, body: { fullName: `Sim Driver ${Date.now() % 10000}` } });
  return api('/drivers/onboarding', {
    method: 'POST',
    token,
    body: {
      vehicleMake: 'Toyota',
      vehicleModel: 'Camry',
      vehicleColor: 'White',
      // Indian format: valid in every market (INR checks the format; others accept any 2–12 letters/digits).
      plateNumber: 'MH12SM' + Math.floor(1000 + Math.random() * 8999),
      vehicleTier: tier,
      licenseNo: 'FL-' + Math.floor(Math.random() * 1e6),
    },
  });
}

// Run-scoped unique phone generator (stays under the 20-char column limit).
const RUN = Math.floor(1000 + Math.random() * 9000);
let seq = 0;
export function phone(prefix = '1985') {
  seq += 1;
  return `+${prefix}${RUN}${String(seq).padStart(5, '0')}`.slice(0, 16);
}
