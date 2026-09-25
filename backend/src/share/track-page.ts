/**
 * The public tracking page: one self-contained HTML document, no build step.
 * Leaflet (from jsDelivr) + OpenStreetMap tiles — no Google key in public
 * HTML. The page polls `../track/<token>` (same origin) every 3 s, glides the
 * car between fixes, and stops polling once the trip has ended or the link
 * has expired. Every server string is written with textContent (never
 * innerHTML), so a driver name or place label cannot inject markup.
 */

const LEAFLET = 'https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist';

export const TRACK_PAGE_CSP = [
  "default-src 'none'",
  `script-src 'unsafe-inline' https://cdn.jsdelivr.net`,
  `style-src 'unsafe-inline' https://cdn.jsdelivr.net`,
  'img-src https://tile.openstreetmap.org data:',
  "connect-src 'self'",
  "base-uri 'none'",
  "form-action 'none'",
  "frame-ancestors 'none'",
].join('; ');

const STYLE = `
:root{--teal:#0FA3A8;--navy:#0B3C49;--ink:#12202a;--muted:#5b6b75;--card:#fff;--bg:#eef3f4}
*{box-sizing:border-box}html,body{margin:0;height:100%;font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;color:var(--ink);background:var(--bg)}
#map{position:fixed;inset:0}
.top{position:fixed;top:12px;left:12px;right:12px;z-index:500;display:flex;align-items:center;gap:8px;pointer-events:none}
.brand{pointer-events:auto;background:var(--card);border-radius:999px;padding:8px 14px;font-weight:700;letter-spacing:.2px;box-shadow:0 2px 10px rgba(0,0,0,.12);display:flex;align-items:center;gap:8px}
.dot{width:10px;height:10px;border-radius:50%;background:var(--teal)}
.live{margin-left:auto;pointer-events:auto;background:var(--teal);color:#fff;border-radius:999px;padding:6px 12px;font-size:13px;font-weight:600}
.live.off{background:#8a979e}
.card{position:fixed;left:12px;right:12px;bottom:12px;z-index:500;max-width:520px;margin:0 auto;background:var(--card);border-radius:18px;padding:16px 18px;box-shadow:0 6px 24px rgba(0,0,0,.18)}
.status{font-size:19px;font-weight:700;margin:0 0 4px}
.eta{color:var(--teal);font-weight:700}
.sub{color:var(--muted);font-size:14px;margin:2px 0}
.car{display:flex;justify-content:space-between;align-items:center;margin-top:10px;padding-top:10px;border-top:1px solid #e3eaec;gap:10px}
.plate{font-family:ui-monospace,Menlo,monospace;font-weight:700;border:2px solid var(--navy);border-radius:6px;padding:2px 8px;white-space:nowrap}
.route{margin-top:8px;font-size:14px}.route div{margin:3px 0}
.pin{display:inline-block;width:9px;height:9px;border-radius:50%;margin-right:8px}
.caricon{width:30px;height:30px;border-radius:50%;background:var(--navy);border:3px solid #fff;box-shadow:0 2px 6px rgba(0,0,0,.35);display:flex;align-items:center;justify-content:center;transition:transform .6s linear}
.caricon:after{content:"";width:0;height:0;border-left:6px solid transparent;border-right:6px solid transparent;border-bottom:11px solid #fff;transform:translateY(-1px)}
.foot{color:var(--muted);font-size:12px;margin-top:8px}
`;

const SCRIPT = `
(function(){
  var TOKEN = document.body.getAttribute('data-token');
  var FEED = '../track/' + TOKEN;
  var $ = function(id){ return document.getElementById(id); };
  var map = L.map('map', { zoomControl: false }).setView([41.3111, 69.2797], 13);
  L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
    maxZoom: 19, attribution: '&copy; OpenStreetMap contributors'
  }).addTo(map);
  function pinIcon(c){ return L.divIcon({ className: '', iconSize: [16,16], iconAnchor: [8,8],
    html: '<div style="width:16px;height:16px;border-radius:50%;background:'+c+';border:3px solid #fff;box-shadow:0 1px 4px rgba(0,0,0,.4)"></div>' }); }
  var carIcon = L.divIcon({ className: '', iconSize: [30,30], iconAnchor: [15,15], html: '<div class="caricon" id="caricon"></div>' });
  var pickupM = null, dropoffM = null, carM = null, fitted = false, timer = null;
  var from = null, to = null, t0 = 0, DUR = 2800;

  var LABELS = {
    finding_driver: 'Finding a driver',
    driver_on_the_way: 'Driver on the way',
    driver_arrived: 'Driver has arrived',
    on_trip: 'On the way',
    completed: 'Trip ended',
    ended: 'Trip ended'
  };

  function fmtEta(s){ if (s == null) return ''; var m = Math.max(1, Math.round(s/60)); return m + ' min'; }

  function glide(ts){
    if (!carM || !from || !to) return;
    var k = Math.min(1, (ts - t0) / DUR);
    carM.setLatLng([from[0] + (to[0]-from[0])*k, from[1] + (to[1]-from[1])*k]);
    if (k < 1) requestAnimationFrame(glide);
  }

  function render(d){
    $('status').textContent = LABELS[d.status] || 'Trip update';
    var eta = '';
    if (d.etaSec != null && d.status === 'driver_on_the_way') eta = 'Arriving in ' + fmtEta(d.etaSec);
    if (d.etaSec != null && d.status === 'on_trip') eta = 'Arriving at destination in ' + fmtEta(d.etaSec);
    $('eta').textContent = eta;
    $('driver').textContent = d.driverFirstName ? d.driverFirstName : (d.ended ? '' : 'Waiting for a driver');
    $('vehicle').textContent = d.vehicleLabel || '';
    $('plate').textContent = d.plate || '';
    $('plate').style.display = d.plate ? '' : 'none';
    $('from').textContent = d.pickup.label || 'Pickup';
    $('to').textContent = d.dropoff.label || 'Destination';

    if (!pickupM) pickupM = L.marker([d.pickup.lat, d.pickup.lng], { icon: pinIcon('#0FA3A8') }).addTo(map);
    if (!dropoffM) dropoffM = L.marker([d.dropoff.lat, d.dropoff.lng], { icon: pinIcon('#0B3C49') }).addTo(map);

    if (d.lat != null && d.lng != null) {
      var p = [d.lat, d.lng];
      if (!carM) { carM = L.marker(p, { icon: carIcon, zIndexOffset: 1000 }).addTo(map); from = to = p; }
      else { var cur = carM.getLatLng(); from = [cur.lat, cur.lng]; to = p; t0 = performance.now(); requestAnimationFrame(glide); }
      var ci = $('caricon'); if (ci && d.heading != null) ci.style.transform = 'rotate(' + d.heading + 'deg)';
    } else if (carM) { map.removeLayer(carM); carM = null; }

    if (!fitted) {
      var pts = [[d.pickup.lat, d.pickup.lng], [d.dropoff.lat, d.dropoff.lng]];
      if (d.lat != null) pts.push([d.lat, d.lng]);
      map.fitBounds(pts, { paddingTopLeft: [30, 70], paddingBottomRight: [30, 230], maxZoom: 16 });
      fitted = true;
    }

    if (d.ended) stop(d.status === 'completed' ? 'Trip ended' : 'This trip has ended');
  }

  function stop(msg){
    if (timer) { clearInterval(timer); timer = null; }
    $('status').textContent = msg; $('eta').textContent = '';
    $('live').textContent = 'Ended'; $('live').className = 'live off';
    if (carM) { map.removeLayer(carM); carM = null; }
  }

  function poll(){
    fetch(FEED, { cache: 'no-store', credentials: 'omit' }).then(function(r){
      if (r.status === 404) { stop('This link has expired'); return null; }
      if (!r.ok) return null; // 429 / blip: try again next tick
      return r.json();
    }).then(function(d){ if (d) render(d); }).catch(function(){});
  }
  poll();
  timer = setInterval(poll, 3000);
})();
`;

function shell(body: string, token = ''): string {
  return `<!doctype html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="robots" content="noindex,nofollow">
<meta name="theme-color" content="#0FA3A8">
<title>RideVela · Live trip</title>
<link rel="stylesheet" href="${LEAFLET}/leaflet.css" crossorigin="anonymous">
<style>${STYLE}</style>
</head><body data-token="${token}">${body}</body></html>`;
}

/** The live page. `token` must already be validated against TOKEN_RE (it is
 *  interpolated into an attribute; the regex admits only [A-Za-z0-9_-]). */
export function trackPageHtml(token: string): string {
  return shell(
    `<div id="map"></div>
<div class="top"><div class="brand"><span class="dot"></span>RideVela</div><div class="live" id="live">Live</div></div>
<div class="card">
  <p class="status" id="status">Loading trip…</p>
  <p class="sub"><span class="eta" id="eta"></span></p>
  <div class="car"><div><div id="driver" style="font-weight:600"></div><div class="sub" id="vehicle"></div></div><span class="plate" id="plate" style="display:none"></span></div>
  <div class="route"><div><span class="pin" style="background:#0FA3A8"></span><span id="from"></span></div><div><span class="pin" style="background:#0B3C49"></span><span id="to"></span></div></div>
  <div class="foot">Shared by a RideVela rider. Updates every few seconds.</div>
</div>
<script src="${LEAFLET}/leaflet.js" crossorigin="anonymous"></script>
<script>${SCRIPT}</script>`,
    token,
  );
}

export function expiredPageHtml(): string {
  return shell(
    `<div class="top"><div class="brand"><span class="dot"></span>RideVela</div></div>
<div class="card"><p class="status">This link has expired</p>
<p class="sub">Live trip links stop working an hour after the trip ends.</p></div>`,
  );
}
