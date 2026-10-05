// Builds FAIRSVIA's illustrated Home posters and banners (1200x750) into
// packages/design_system/assets/promo_fairsvia/. RideVela uses stock photos;
// FAIRSVIA's shipped look uses these flat-gradient illustrations in its own
// palette, so the two Homes are told apart at a glance. Drawn here (SVG), so
// there is no third-party licence. The left ~45% stays dark and calm: the
// poster headline sits there in white.
//
//   node tools/brand/build_posters.mjs     (uses tools/visual-check's puppeteer)
import { mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import puppeteer from '../visual-check/node_modules/puppeteer/lib/esm/puppeteer/puppeteer.js';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const OUT = join(ROOT, 'packages/design_system/assets/promo_fairsvia');
const W = 1200, H = 750;
const NAVY = '#0A1433', DEEP = '#0F2266', BLUE = '#2F6BFF', SKY = '#5B9DFF', CORAL = '#FF6B4A', PEACH = '#FFB199', WHITE = '#FFFFFF';

const defs = `
<linearGradient id="route" x1="0" x2="1"><stop offset="0" stop-color="${SKY}"/><stop offset="1" stop-color="${CORAL}"/></linearGradient>
<radialGradient id="glow" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="${SKY}" stop-opacity="0.55"/><stop offset="1" stop-color="${SKY}" stop-opacity="0"/></radialGradient>
<radialGradient id="cglow" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="${CORAL}" stop-opacity="0.6"/><stop offset="1" stop-color="${CORAL}" stop-opacity="0"/></radialGradient>
<linearGradient id="fadeL" x1="0" x2="1"><stop offset="0" stop-color="${NAVY}" stop-opacity="0.85"/><stop offset="0.5" stop-color="${NAVY}" stop-opacity="0.15"/><stop offset="1" stop-color="${NAVY}" stop-opacity="0"/></linearGradient>`;
const bg = (a, b, angle = 'x1="0" y1="0" x2="0" y2="1"') =>
  `<linearGradient id="bg" ${angle}><stop offset="0" stop-color="${a}"/><stop offset="1" stop-color="${b}"/></linearGradient><rect width="${W}" height="${H}" fill="url(#bg)"/>`;
// Deterministic "random" for stars/windows.
let seed = 7; const rnd = () => ((seed = (seed * 9301 + 49297) % 233280) / 233280);
const stars = (n, y0 = 0, y1 = 300) => Array.from({ length: n }, () =>
  `<circle cx="${(rnd() * W).toFixed(0)}" cy="${(y0 + rnd() * (y1 - y0)).toFixed(0)}" r="${(0.8 + rnd() * 1.8).toFixed(1)}" fill="${WHITE}" opacity="${(0.35 + rnd() * 0.5).toFixed(2)}"/>`).join('');
const skyline = (y, color, opacity = 1, scale = 1) => {
  let x = 0, out = '';
  while (x < W) {
    const w = (40 + rnd() * 70) * scale, h = (80 + rnd() * 220) * scale;
    out += `<rect x="${x.toFixed(0)}" y="${(y - h).toFixed(0)}" width="${w.toFixed(0)}" height="${(h + 400).toFixed(0)}" rx="6" fill="${color}" opacity="${opacity}"/>`;
    // lit windows
    for (let wy = y - h + 16; wy < y - 10; wy += 22) for (let wx = x + 10; wx < x + w - 12; wx += 18)
      if (rnd() > 0.72) out += `<rect x="${wx.toFixed(0)}" y="${wy.toFixed(0)}" width="7" height="9" rx="1.5" fill="${rnd() > 0.5 ? PEACH : SKY}" opacity="${(0.5 + rnd() * 0.4).toFixed(2)}"/>`;
    x += w + 6 * scale;
  }
  return out;
};
const pin = (x, y, s = 1, c = CORAL) =>
  `<g transform="translate(${x} ${y}) scale(${s})"><circle cx="0" cy="0" r="70" fill="url(#cglow)"/><path d="M0 40 C-20 10 -34 -4 -34 -24 A34 34 0 1 1 34 -24 C34 -4 20 10 0 40Z" fill="${c}"/><circle cx="0" cy="-24" r="13" fill="${WHITE}"/></g>`;
const car = (x, y, s = 1, c = WHITE) =>
  `<g transform="translate(${x} ${y}) scale(${s})"><path d="M-70 0 L-62 -26 Q-58 -36 -46 -38 L-22 -58 Q-14 -64 -2 -64 L30 -64 Q42 -64 50 -56 L70 -36 Q84 -34 88 -22 L90 0 Z" fill="${c}"/><path d="M-14 -54 L28 -54 L48 -38 L-30 -38 Z" fill="${BLUE}" opacity="0.85"/><circle cx="-40" cy="2" r="16" fill="${NAVY}"/><circle cx="-40" cy="2" r="6" fill="${SKY}"/><circle cx="56" cy="2" r="16" fill="${NAVY}"/><circle cx="56" cy="2" r="6" fill="${SKY}"/><rect x="78" y="-28" width="12" height="7" rx="3" fill="${PEACH}"/></g>`;
const route = (d, w = 10) => `<path d="${d}" fill="none" stroke="url(#route)" stroke-width="${w}" stroke-linecap="round"/><path d="${d}" fill="none" stroke="${WHITE}" stroke-width="2" stroke-dasharray="2 18" stroke-linecap="round" opacity="0.6"/>`;

const scenes = {
  // Night city with a glowing route to a coral pin.
  'city_night.jpg': () => bg(NAVY, DEEP) + stars(60) +
    `<circle cx="980" cy="150" r="190" fill="url(#glow)"/><circle cx="980" cy="150" r="46" fill="${PEACH}" opacity="0.9"/>` +
    skyline(560, '#16286E', 1, 1.1) + skyline(640, '#0D1A4D', 1, 0.9) +
    route('M560 700 C700 620 760 560 860 520 S1000 430 1040 400') + pin(1040, 380, 1.1) +
    `<rect width="${W}" height="${H}" fill="url(#fadeL)"/>`,
  // Plane climbing out over runway lights at dusk.
  'airport.jpg': () => bg('#12205A', '#4A3A8C') + stars(30, 0, 200) +
    `<circle cx="1000" cy="560" r="260" fill="url(#cglow)"/>` +
    `<rect x="0" y="600" width="${W}" height="150" fill="#0B1540"/>` +
    Array.from({ length: 14 }, (_, i) => `<circle cx="${380 + i * 62}" cy="${640 + i * 6}" r="5" fill="${i % 2 ? SKY : PEACH}"/>`).join('') +
    `<g transform="translate(900 300) rotate(-18)"><path d="M-170 0 Q-170 -18 -140 -18 L120 -18 Q170 -18 190 0 Q170 18 120 18 L-140 18 Q-170 18 -170 0Z" fill="${WHITE}"/><path d="M-10 -14 L-70 -110 L-30 -110 L60 -14Z" fill="${SKY}"/><path d="M-10 14 L-70 110 L-30 110 L60 14Z" fill="${BLUE}"/><path d="M-160 -12 L-190 -70 L-160 -70 L-120 -14Z" fill="${CORAL}"/>` +
    Array.from({ length: 6 }, (_, i) => `<circle cx="${-90 + i * 34}" cy="-4" r="5" fill="${BLUE}" opacity="0.7"/>`).join('') + `</g>` +
    `<rect width="${W}" height="${H}" fill="url(#fadeL)"/>`,
  // Bright daytime city, coral sun, car on the road.
  'city_day.jpg': () => bg('#3E7BFF', '#9CC2FF') +
    `<circle cx="1010" cy="160" r="220" fill="url(#cglow)"/><circle cx="1010" cy="160" r="70" fill="${PEACH}"/>` +
    skyline(560, '#5B8FF0', 0.9, 1.1) + skyline(620, '#2E5FD6', 1, 0.9) +
    `<rect x="0" y="620" width="${W}" height="130" fill="#1B3FA6"/><rect x="0" y="676" width="${W}" height="8" fill="${WHITE}" opacity="0.15"/>` +
    Array.from({ length: 10 }, (_, i) => `<rect x="${i * 130}" y="676" width="60" height="8" rx="4" fill="${WHITE}" opacity="0.7"/>`).join('') +
    car(880, 660, 1.3) + `<rect width="${W}" height="${H}" fill="url(#fadeL)"/>`,
  // Gift box with a coral ribbon and confetti.
  'offers_night.webp': () => bg(NAVY, '#1C2D7A') + stars(40) +
    `<circle cx="930" cy="400" r="300" fill="url(#glow)"/>` +
    Array.from({ length: 40 }, () => `<rect x="${(600 + rnd() * 560).toFixed(0)}" y="${(60 + rnd() * 600).toFixed(0)}" width="${(6 + rnd() * 10).toFixed(0)}" height="${(10 + rnd() * 16).toFixed(0)}" rx="2" transform="rotate(${(rnd() * 90).toFixed(0)})" fill="${[CORAL, SKY, PEACH, WHITE][Math.floor(rnd() * 4)]}" opacity="0.85"/>`).join('') +
    `<g transform="translate(930 430)"><rect x="-150" y="-60" width="300" height="200" rx="22" fill="${BLUE}"/><rect x="-170" y="-120" width="340" height="80" rx="20" fill="${SKY}"/><rect x="-22" y="-120" width="44" height="260" fill="${CORAL}"/><path d="M0 -120 C-80 -220 -150 -150 -60 -122Z M0 -120 C80 -220 150 -150 60 -122Z" fill="${CORAL}"/>` +
    `<g transform="translate(150 -170) rotate(14)"><path d="M-60 -30 L40 -30 L70 0 L40 30 L-60 30Z" fill="${WHITE}"/><circle cx="40" cy="0" r="7" fill="${NAVY}"/><text x="-14" y="13" font-family="Arial Black,Arial" font-weight="900" font-size="38" fill="${CORAL}" text-anchor="middle">%</text></g></g>` +
    `<rect width="${W}" height="${H}" fill="url(#fadeL)"/>`,
  // Calendar + clock at dusk, crescent moon.
  'schedule_dusk.webp': () => bg('#1A1F5E', '#B5577A') + stars(35, 0, 250) +
    `<path d="M1060 120 A70 70 0 1 0 1100 230 A56 56 0 1 1 1060 120Z" fill="${PEACH}"/>` +
    skyline(640, '#231A57', 1, 0.8) +
    `<g transform="translate(860 360)"><rect x="-150" y="-150" width="300" height="290" rx="34" fill="${WHITE}"/><rect x="-150" y="-150" width="300" height="80" rx="34" fill="${BLUE}"/><rect x="-150" y="-100" width="300" height="30" fill="${BLUE}"/><rect x="-90" y="-180" width="22" height="60" rx="11" fill="${NAVY}"/><rect x="68" y="-180" width="22" height="60" rx="11" fill="${NAVY}"/>` +
    Array.from({ length: 12 }, (_, i) => `<rect x="${-120 + (i % 4) * 64}" y="${-50 + Math.floor(i / 4) * 58}" width="44" height="40" rx="10" fill="${i === 6 ? CORAL : '#E6EDFF'}"/>`).join('') +
    `<g transform="translate(150 120)"><circle r="78" fill="${CORAL}"/><circle r="62" fill="${WHITE}"/><path d="M0 0 L0 -38 M0 0 L28 16" stroke="${NAVY}" stroke-width="9" stroke-linecap="round"/><circle r="7" fill="${NAVY}"/></g></g>` +
    `<rect width="${W}" height="${H}" fill="url(#fadeL)"/>`,
  // Safety: a shield with a check over a car, with soft rings.
  'safety_ride.webp': () => bg(NAVY, '#13307F') + stars(30) +
    `<circle cx="900" cy="370" r="320" fill="url(#glow)"/>` +
    [260, 210, 160].map((r, i) => `<circle cx="900" cy="330" r="${r}" fill="none" stroke="${SKY}" stroke-width="2" opacity="${0.18 + i * 0.1}"/>`).join('') +
    `<g transform="translate(900 300)"><path d="M0 -160 L130 -110 L130 10 C130 100 70 150 0 180 C-70 150 -130 100 -130 10 L-130 -110 Z" fill="${BLUE}"/><path d="M0 -130 L104 -90 L104 10 C104 82 56 124 0 150 Z" fill="${SKY}" opacity="0.35"/><path d="M-52 10 L-14 50 L60 -36" fill="none" stroke="${WHITE}" stroke-width="26" stroke-linecap="round" stroke-linejoin="round"/></g>` +
    car(900, 610, 1.15) + `<rect width="${W}" height="${H}" fill="url(#fadeL)"/>`,
  // Share trip: a phone showing a live route, with signal waves.
  'share_trip.webp': () => bg('#101C55', '#2A4BC0') + stars(30) +
    `<circle cx="920" cy="380" r="300" fill="url(#cglow)"/>` +
    [120, 170, 220].map((r, i) => `<path d="M${1060 + r * 0.5} ${250 - r * 0.6} A${r} ${r} 0 0 1 ${1060 + r * 0.5} ${250 + r * 0.6}" fill="none" stroke="${PEACH}" stroke-width="10" stroke-linecap="round" opacity="${0.8 - i * 0.22}"/>`).join('') +
    `<g transform="translate(880 380) rotate(-8)"><rect x="-150" y="-290" width="300" height="580" rx="44" fill="#0B1540"/><rect x="-132" y="-268" width="264" height="536" rx="30" fill="#E9F0FF"/>` +
    `<path d="M-132 -120 L132 -160 M-132 60 L132 0 M-40 -268 L-10 268 M70 -268 L40 268" stroke="${WHITE}" stroke-width="14"/>` +
    route('M-80 200 C-40 120 40 120 30 40 S-20 -80 60 -160', 12) + pin(60, -180, 0.7) +
    `<circle cx="-80" cy="200" r="16" fill="${BLUE}"/><circle cx="-80" cy="200" r="6" fill="${WHITE}"/></g>` +
    `<rect width="${W}" height="${H}" fill="url(#fadeL)"/>`,
};

mkdirSync(OUT, { recursive: true });
const browser = await puppeteer.launch({ headless: true, args: ['--no-sandbox'] });
const page = await browser.newPage();
await page.setViewport({ width: W, height: H, deviceScaleFactor: 1 });
for (const [name, draw] of Object.entries(scenes)) {
  seed = 7 + name.length; // stable per poster
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" width="${W}" height="${H}"><defs>${defs}</defs>${draw()}</svg>`;
  await page.setContent(`<style>html,body{margin:0}svg{display:block}</style>${svg}`);
  const type = name.endsWith('.jpg') ? 'jpeg' : 'webp';
  await page.screenshot({ path: join(OUT, name), type, quality: 88, clip: { x: 0, y: 0, width: W, height: H } });
}
await browser.close();
console.log('posters written to', OUT);
