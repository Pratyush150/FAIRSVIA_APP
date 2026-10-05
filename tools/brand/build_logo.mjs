// Builds the FAIRSVIA logo pack (Road-F) into docs/brand/ and the app icons
// into apps/*: SVG sources, transparent/white/dark/turquoise PNGs, lockups,
// Android mipmaps, the iOS AppIcon set and web icons.
//
//   node tools/brand/build_logo.mjs        (uses tools/visual-check's puppeteer)
import { mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import puppeteer from '../visual-check/node_modules/puppeteer/lib/esm/puppeteer/puppeteer.js';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const OUT = join(ROOT, 'docs', 'brand');
// FAIRSVIA "Ocean Blue": navy, bright blue (TURQ slot), brand blue (TEAL slot).
const NAVY = '#0B1F49', TURQ = '#5B9DFF', TEAL = '#2F6BFF', WHITE = '#FFFFFF';

// The F as a road: a stem running away from you with a lane line, two arms,
// a light edge on the far side. Drawn in a 512 box; `s` scales it about the
// centre (for safe zones).
function vGlyph(fill, lane, s = 1) {
  const t = `translate(256 256) scale(${s}) translate(-256 -256)`;
  return `<g transform="${t}">
    <path d="M134 110 L378 110 L378 188 L226 188 L226 236 L332 236 L332 306 L226 306 L226 410 L134 410 Z" fill="${fill}"/>
    <path d="M180 332 L180 358 M180 378 L180 396" stroke="${lane}" stroke-width="12" stroke-linecap="round"/>
    <path d="M208 306 L226 306 L226 410 L208 410 Z" fill="#FFFFFF" opacity="0.14"/>
  </g>`;
}
const svg = (inner, w = 512, h = 512) =>
  `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${w} ${h}" width="${w}" height="${h}">${inner}</svg>`;
const tile = (bg, v, lane, { rounded = true, s = 1 } = {}) =>
  svg(`<rect width="512" height="512" ${rounded ? 'rx="116"' : ''} fill="${bg}"/>${vGlyph(v, lane, s)}`);

const marks = {
  'fairsvia-mark-rider': tile(TEAL, NAVY, TURQ),
  'fairsvia-mark-driver': tile(NAVY, TURQ, WHITE),
  'fairsvia-glyph-navy': svg(vGlyph(NAVY, TURQ)),
  'fairsvia-glyph-white': svg(vGlyph(WHITE, TURQ)),
  'fairsvia-glyph-turquoise': svg(vGlyph(TURQ, WHITE)),
};
// Full-bleed squares for stores and adaptive/maskable icons (the OS masks the
// corners itself); the F shrinks into the safe zone.
const fullbleed = {
  rider: tile(TEAL, NAVY, TURQ, { rounded: false, s: 0.78 }),
  driver: tile(NAVY, TURQ, WHITE, { rounded: false, s: 0.78 }),
};

const inter = readFileSync(join(ROOT, 'packages/design_system/fonts/Inter-ExtraBold.ttf')).toString('base64');
function lockup(markSvg, textColor, bg) {
  const inner = markSvg.replace(/<svg[^>]*>/, '').replace('</svg>', '');
  return svg(`${bg ? `<rect width="1400" height="400" fill="${bg}"/>` : ''}
    <style>@font-face{font-family:RVInter;src:url(data:font/ttf;base64,${inter})}</style>
    <g transform="translate(40 40) scale(0.625)">${inner}</g>
    <text x="400" y="262" font-family="RVInter, Inter, Arial, sans-serif" font-weight="800" font-size="196"
      letter-spacing="-6" fill="${textColor}">FAIRSVIA</text>`, 1400, 400);
}

mkdirSync(join(OUT, 'svg'), { recursive: true });
mkdirSync(join(OUT, 'png'), { recursive: true });
for (const [name, s] of Object.entries(marks)) writeFileSync(join(OUT, 'svg', `${name}.svg`), s);
writeFileSync(join(OUT, 'svg', 'fairsvia-lockup-light.svg'), lockup(marks['fairsvia-mark-rider'], NAVY));
writeFileSync(join(OUT, 'svg', 'fairsvia-lockup-dark.svg'), lockup(marks['fairsvia-mark-rider'], WHITE));

const browser = await puppeteer.launch({ headless: true, args: ['--no-sandbox'] });
const page = await browser.newPage();
async function png(svgText, w, h, path, bg) {
  await page.setViewport({ width: w, height: h, deviceScaleFactor: 1 });
  await page.setContent(`<style>html,body{margin:0;background:${bg ?? 'transparent'}}svg{display:block;width:${w}px;height:${h}px}</style>${svgText}`);
  await page.screenshot({ path, omitBackground: !bg, clip: { x: 0, y: 0, width: w, height: h } });
}
const P = (f) => join(OUT, 'png', f);

// Marks: transparent + on each background, several sizes.
for (const [name, s] of Object.entries(marks)) {
  for (const size of [1024, 512, 256, 128]) await png(s, size, size, P(`${name}-${size}.png`));
}
for (const [bgName, bg] of [['white', WHITE], ['dark', '#0E0F11'], ['turquoise', TURQ]]) {
  const glyph = bgName === 'dark' ? marks['fairsvia-glyph-turquoise'] : bgName === 'turquoise' ? marks['fairsvia-glyph-navy'] : marks['fairsvia-glyph-navy'];
  await png(glyph.replace('<svg', `<svg style="background:${bg}"`), 1024, 1024, P(`fairsvia-glyph-on-${bgName}-1024.png`), bg);
}
await png(readFileSync(join(OUT, 'svg', 'fairsvia-lockup-light.svg'), 'utf8'), 1400, 400, P('fairsvia-lockup-light-transparent.png'));
await png(readFileSync(join(OUT, 'svg', 'fairsvia-lockup-dark.svg'), 'utf8'), 1400, 400, P('fairsvia-lockup-dark-transparent.png'));
await png(lockup(marks['fairsvia-mark-rider'], NAVY, WHITE), 1400, 400, P('fairsvia-lockup-on-white.png'), WHITE);
await png(lockup(marks['fairsvia-mark-rider'], WHITE, '#0E0F11'), 1400, 400, P('fairsvia-lockup-on-dark.png'), '#0E0F11');

// App icons.
const android = { mdpi: 48, hdpi: 72, xhdpi: 96, xxhdpi: 144, xxxhdpi: 192 };
const ios = { '20x20@1x': 20, '20x20@2x': 40, '20x20@3x': 60, '29x29@1x': 29, '29x29@2x': 58, '29x29@3x': 87,
  '40x40@1x': 40, '40x40@2x': 80, '40x40@3x': 120, '60x60@2x': 120, '60x60@3x': 180, '76x76@1x': 76,
  '76x76@2x': 152, '83.5x83.5@2x': 167, '1024x1024@1x': 1024 };
for (const [app, key] of [['rider_app', 'rider'], ['driver_app', 'driver']]) {
  const rounded = marks[`fairsvia-mark-${key}`];
  const square = fullbleed[key];
  const bg = key === 'rider' ? TEAL : NAVY;
  for (const [d, px] of Object.entries(android)) {
    await png(rounded, px, px, join(ROOT, 'apps', app, 'android/app/src/main/res', `mipmap-${d}`, 'ic_launcher.png'));
  }
  for (const [n, px] of Object.entries(ios)) {
    // iOS icons must be opaque; the OS rounds the corners.
    await png(square, px, px, join(ROOT, 'apps', app, 'ios/Runner/Assets.xcassets/AppIcon.appiconset', `Icon-App-${n}.png`), bg);
  }
  // Android 8+ adaptive icon: a solid background colour + the F on a
  // transparent 108dp foreground, inside the 72dp safe zone (the launcher
  // crops to a circle, squircle or square). Without it the launcher shrinks
  // the legacy square into a white circle.
  const fg = svg(vGlyph(key === 'rider' ? NAVY : TURQ, key === 'rider' ? TURQ : WHITE, 0.62));
  const adaptive = { mdpi: 108, hdpi: 162, xhdpi: 216, xxhdpi: 324, xxxhdpi: 432 };
  const res = join(ROOT, 'apps', app, 'android/app/src/main/res');
  for (const [d, px] of Object.entries(adaptive)) {
    await png(fg, px, px, join(res, `mipmap-${d}`, 'ic_launcher_foreground.png'));
  }
  mkdirSync(join(res, 'mipmap-anydpi-v26'), { recursive: true });
  writeFileSync(join(res, 'mipmap-anydpi-v26', 'ic_launcher.xml'),
    `<?xml version="1.0" encoding="utf-8"?>\n<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n` +
    `  <background android:drawable="@color/ic_launcher_background"/>\n` +
    `  <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n</adaptive-icon>\n`);
  writeFileSync(join(res, 'values', 'ic_launcher_background.xml'),
    `<?xml version="1.0" encoding="utf-8"?>\n<resources>\n  <color name="ic_launcher_background">${bg}</color>\n</resources>\n`);
  const web = join(ROOT, 'apps', app, 'web', 'icons');
  await png(rounded, 192, 192, join(web, 'Icon-192.png'));
  await png(rounded, 512, 512, join(web, 'Icon-512.png'));
  await png(square, 192, 192, join(web, 'Icon-maskable-192.png'), bg);
  await png(square, 512, 512, join(web, 'Icon-maskable-512.png'), bg);
  await png(rounded, 64, 64, join(ROOT, 'apps', app, 'web', 'favicon.png'));
}
await browser.close();
console.log('logo pack written to docs/brand and apps/*/');
