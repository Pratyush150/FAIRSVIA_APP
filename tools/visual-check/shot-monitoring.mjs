// Screenshot the admin Monitoring tab: seed an admin session, load the app,
// click the "Monitoring" nav-rail destination (canvas — click by coordinates),
// wait for the ops snapshot to load, and capture.
import { mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import puppeteer from 'puppeteer';

const __dir = dirname(fileURLToPath(import.meta.url));
const SHOTS = join(__dir, 'shots');
mkdirSync(SHOTS, { recursive: true });

const API = 'http://192.168.1.48:3000/api/v1';
const URL = 'http://192.168.1.48:9090'; // admin
const PHONE = '+19900000001';

async function login() {
  const req = await fetch(`${API}/auth/otp/request`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ phone: PHONE }),
  }).then((r) => r.json());
  const ver = await fetch(`${API}/auth/otp/verify`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ phone: PHONE, code: req.devCode }),
  }).then((r) => r.json());
  return ver;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const tokens = await login();
const browser = await puppeteer.launch({
  headless: 'new',
  args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage'],
});
const page = await browser.newPage();
await page.setViewport({ width: 1100, height: 950, deviceScaleFactor: 2 });
await page.evaluateOnNewDocument(
  (at, rt) => {
    localStorage.setItem('ubernav.access_token', at);
    localStorage.setItem('ubernav.refresh_token', rt);
  },
  tokens.accessToken,
  tokens.refreshToken,
);
await page.goto(URL, { waitUntil: 'networkidle2', timeout: 45000 });
await page.waitForSelector('flutter-view, flt-glass-pane', { timeout: 30000 }).catch(() => {});
await sleep(4000);

// Nav-rail "Monitoring" is the 5th destination — at ~y=360 in CSS pixels.
await page.mouse.click(40, 360);
await sleep(3000); // let the ops snapshot load
const out = join(SHOTS, 'admin-monitoring.png');
await page.screenshot({ path: out });
console.log('captured ' + out);
await browser.close();
