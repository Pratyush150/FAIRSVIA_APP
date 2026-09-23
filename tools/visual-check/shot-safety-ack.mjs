// Drives "I'm on it" on the first open incident and captures the result.
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
const API = `http://${HOST}:3000/api/v1`;
const SHOTS = join(dirname(fileURLToPath(import.meta.url)), 'shots');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const post = (p, b) => fetch(`${API}${p}`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(b) }).then((r) => r.json());
const phone = process.env.ADMIN_PHONE ?? '+19900000001';
const { devCode } = await post('/auth/otp/request', { phone });
const t = await post('/auth/otp/verify', { phone, code: devCode });
const browser = await puppeteer.launch({ headless: 'new', args: ['--no-sandbox', '--disable-dev-shm-usage'] });
const page = await browser.newPage();
await page.setViewport({ width: 1280, height: 900 });
await page.evaluateOnNewDocument((a, r) => { localStorage.setItem('ubernav.access_token', a); localStorage.setItem('ubernav.refresh_token', r); }, t.accessToken, t.refreshToken);
await page.goto(`http://${HOST}:9090`, { waitUntil: 'networkidle2', timeout: 45000 });
await sleep(6000);
await page.mouse.click(40, 150);
await sleep(2500);
await page.mouse.click(1187, 166);
await sleep(3000);
await page.screenshot({ path: join(SHOTS, 'admin-safety-acknowledged.png') });
console.log('captured admin-safety-acknowledged.png');
await browser.close();
