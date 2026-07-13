import { io } from 'socket.io-client';

export const BASE = process.env.BASE_URL || 'http://localhost:3000/api/v1';
export const WS = process.env.WS_URL || 'http://localhost:3000';

/** REST helper. Throws an Error with `.status` on non-2xx; times out cleanly. */
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

export function connect(token) {
  return new Promise((resolve, reject) => {
    const socket = io(WS, { auth: { token }, transports: ['websocket'] });
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

export function onceEvent(socket, event, timeoutMs) {
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new Error(`timeout: ${event}`)), timeoutMs);
    socket.once(event, (data) => {
      clearTimeout(t);
      resolve(data);
    });
  });
}

export const wait = (ms) => new Promise((r) => setTimeout(r, ms));

export async function onboardDriver(token, tier = 'economy') {
  return api('/drivers/onboarding', {
    method: 'POST',
    token,
    body: {
      vehicleMake: 'Toyota',
      vehicleModel: 'Etios',
      vehicleColor: 'White',
      plateNumber: 'KA' + Math.floor(1000 + Math.random() * 8999),
      vehicleTier: tier,
      licenseNo: 'DL-' + Math.floor(Math.random() * 1e6),
    },
  });
}

// Run-scoped phone generator: unique within a run (counter), unlikely to clash
// across runs (random run id). Stays under the 20-char column limit.
const RUN = Math.floor(1000 + Math.random() * 9000);
let seq = 0;
export function phone() {
  seq += 1;
  return `+9197${RUN}${String(seq).padStart(5, '0')}`;
}

// --- stats -----------------------------------------------------------------

export function percentile(sortedAsc, p) {
  if (sortedAsc.length === 0) return 0;
  const idx = Math.min(sortedAsc.length - 1, Math.ceil((p / 100) * sortedAsc.length) - 1);
  return sortedAsc[Math.max(0, idx)];
}

export function stats(samples) {
  const s = [...samples].sort((a, b) => a - b);
  const sum = s.reduce((a, b) => a + b, 0);
  return {
    count: s.length,
    min: s[0] ?? 0,
    max: s[s.length - 1] ?? 0,
    avg: s.length ? sum / s.length : 0,
    p50: percentile(s, 50),
    p95: percentile(s, 95),
    p99: percentile(s, 99),
  };
}

export function printStats(label, samples, unit = 'ms') {
  const s = stats(samples);
  console.log(
    `  ${label.padEnd(16)} n=${String(s.count).padEnd(6)} ` +
      `avg=${s.avg.toFixed(0)}${unit}  p50=${s.p50}${unit}  ` +
      `p95=${s.p95}${unit}  p99=${s.p99}${unit}  max=${s.max}${unit}`,
  );
}

/** Run `total` tasks across `conc` workers pulling from a shared cursor. */
export async function runPool({ conc, total, task }) {
  let next = 0;
  const worker = async (wid) => {
    for (;;) {
      const i = next++;
      if (i >= total) return;
      await task(i, wid);
    }
  };
  await Promise.all(Array.from({ length: conc }, (_, w) => worker(w)));
}
