// Screenshot the admin console's SOS surfaces: the banner shown on other
// tabs while an SOS is unacknowledged, and the Safety tab itself.
import { mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { networkInterfaces } from 'node:os';
import puppeteer from 'puppeteer';

function hostIp() {
  for (const addrs of Object.values(networkInterfaces())) {
    for (const a of addrs ?? []) {
      if (a.family === 'IPv4' && !a.internal && a.address.startsWith('192.168.')) return a.address;
    }
  }
  return 'localhost';
}
const HOST = process.env.APP_HOST ?? hostIp();
const API = process.env.API_BASE_URL ?? `http://${HOST}:3000/api/v1`;
const URL = `http://${HOST}:9090`;
const PHONE = process.env.ADMIN_PHONE ?? '+19900000001';
const SHOTS = join(dirname(fileURLToPath(import.meta.url)), 'shots');
mkdirSync(SHOTS, { recursive: true });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const post = (path, body) =>
  fetch(`${API}${path}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  }).then((r) => r.json());
const { devCode } = await post('/auth/otp/request', { phone: PHONE });
const tokens = await post('/auth/otp/verify', { phone: PHONE, code: devCode });

const browser = await puppeteer.launch({
  headless: 'new',
  args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage'],
});
const page = await browser.newPage();
await page.setViewport({ width: 1280, height: 900, deviceScaleFactor: 1 });
await page.evaluateOnNewDocument((at, rt) => {
  localStorage.setItem('ubernav.access_token', at);
  localStorage.setItem('ubernav.refresh_token', rt);
}, tokens.accessToken, tokens.refreshToken);
await page.goto(URL, { waitUntil: 'networkidle2', timeout: 45000 });
await sleep(6000);
await page.screenshot({ path: join(SHOTS, 'admin-overview-2.png') });
// Safety is the 2nd rail destination (Flutter canvas: click by coordinates).
await page.mouse.click(40, Number(process.env.TAB_Y ?? 150));
await sleep(3000);
await page.screenshot({ path: join(SHOTS, 'admin-content.png') });
console.log('captured admin-overview-2.png, admin-content.png');
await browser.close();
