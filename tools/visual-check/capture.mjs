// Headless visual + health smoke test for the three UberNav web apps.
//
// For each app it:
//   1. Loads the app cold and screenshots the landing/login screen
//      (this is the screen that used to white-screen before the storage fix).
//   2. Logs in for real via the backend (OTP request -> verify), seeds the
//      returned tokens into localStorage exactly as the app stores them, then
//      loads the app so it restores the session and routes to Home — and
//      screenshots the authenticated screen.
//   3. Collects console "UNCAUGHT" errors and any HTTP >=400 responses, so we
//      get a pass/fail health signal, not just a picture.
//
// Flutter web renders to <canvas>, so we drive login by seeding storage rather
// than clicking canvas pixels — this exercises the real restoreSession/getMe
// path and is far more reliable than coordinate clicking.

import { mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import puppeteer from 'puppeteer';

const __dir = dirname(fileURLToPath(import.meta.url));
const SHOTS = join(__dir, 'shots');
mkdirSync(SHOTS, { recursive: true });

const API = process.env.API_BASE_URL || 'http://192.168.1.48:3000/api/v1';
const HOST = process.env.APP_HOST || 'http://192.168.1.48';

const APPS = [
  { name: 'rider', url: `${HOST}:9091`, phone: '+13055550101' },
  { name: 'admin', url: `${HOST}:9090`, phone: '+19900000001' },
  { name: 'driver', url: `${HOST}:9092`, phone: '+13055550102' },
];

const ACCESS_KEY = 'ubernav.access_token';
const REFRESH_KEY = 'ubernav.refresh_token';

async function login(phone) {
  const req = await fetch(`${API}/auth/otp/request`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ phone }),
  }).then((r) => r.json());
  const code = req.devCode;
  const ver = await fetch(`${API}/auth/otp/verify`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ phone, code }),
  }).then((r) => r.json());
  if (!ver.accessToken) throw new Error(`login failed for ${phone}: ${JSON.stringify(ver)}`);
  return ver;
}

// Attach console/network collectors; return a live health record.
function watch(page) {
  const health = { uncaught: [], httpErrors: [] };
  page.on('console', (m) => {
    const t = m.text();
    if (t.includes('UNCAUGHT') || t.includes('Null check operator')) health.uncaught.push(t.slice(0, 200));
  });
  page.on('response', (res) => {
    const s = res.status();
    if (s >= 400) health.httpErrors.push(`${s} ${res.url().replace(HOST, '')}`);
  });
  page.on('pageerror', (e) => health.uncaught.push(`pageerror: ${String(e).slice(0, 200)}`));
  return health;
}

async function waitForFlutter(page) {
  // Flutter injects <flutter-view>/<flt-glass-pane> once the first frame paints.
  await page.waitForSelector('flutter-view, flt-glass-pane', { timeout: 30000 }).catch(() => {});
  await new Promise((r) => setTimeout(r, 3500)); // let layout + first API calls settle
}

async function run() {
  const browser = await puppeteer.launch({
    headless: 'new',
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage'],
  });
  const results = [];

  for (const app of APPS) {
    const result = { app: app.name, shots: [], health: null, error: null };
    try {
      // --- 1. Cold landing screen ---
      const p1 = await browser.newPage();
      await p1.setViewport({ width: 430, height: 920, deviceScaleFactor: 2 });
      const h1 = watch(p1);
      await p1.goto(app.url, { waitUntil: 'networkidle2', timeout: 45000 });
      await waitForFlutter(p1);
      const landing = join(SHOTS, `${app.name}-1-landing.png`);
      await p1.screenshot({ path: landing });
      result.shots.push(landing);
      await p1.close();

      // --- 2. Authenticated Home (seed real tokens) ---
      const tokens = await login(app.phone);
      const p2 = await browser.newPage();
      await p2.setViewport({ width: 430, height: 920, deviceScaleFactor: 2 });
      const h2 = watch(p2);
      await p2.evaluateOnNewDocument(
        (a, r, at, rt) => {
          localStorage.setItem(a, at);
          localStorage.setItem(r, rt);
        },
        ACCESS_KEY, REFRESH_KEY, tokens.accessToken, tokens.refreshToken,
      );
      await p2.goto(app.url, { waitUntil: 'networkidle2', timeout: 45000 });
      await waitForFlutter(p2);
      const home = join(SHOTS, `${app.name}-2-home.png`);
      await p2.screenshot({ path: home });
      result.shots.push(home);
      await p2.close();

      result.health = {
        uncaught: [...h1.uncaught, ...h2.uncaught],
        httpErrors: [...h1.httpErrors, ...h2.httpErrors].filter((e) => !e.includes('favicon')),
      };
    } catch (e) {
      result.error = String(e);
    }
    results.push(result);
    console.log(`\n[${app.name}] ${result.error ? 'ERROR: ' + result.error : 'captured ' + result.shots.length + ' screenshots'}`);
    if (result.health) {
      console.log(`  uncaught errors: ${result.health.uncaught.length}`);
      console.log(`  http >=400:      ${result.health.httpErrors.length}${result.health.httpErrors.length ? ' -> ' + result.health.httpErrors.slice(0, 5).join(', ') : ''}`);
    }
  }

  await browser.close();

  // Summary
  console.log('\n================ VISUAL CHECK SUMMARY ================');
  let ok = true;
  for (const r of results) {
    const healthy = r.health && r.health.uncaught.length === 0 && !r.error;
    if (!healthy) ok = false;
    console.log(`  ${healthy ? 'PASS' : 'FAIL'}  ${r.app.padEnd(7)} shots=${r.shots.length} uncaught=${r.health ? r.health.uncaught.length : 'n/a'}`);
  }
  console.log('=====================================================');
  console.log(ok ? 'ALL APPS HEALTHY ✓' : 'SOME APPS UNHEALTHY ✗');
  process.exit(ok ? 0 : 1);
}

run().catch((e) => {
  console.error(e);
  process.exit(1);
});
