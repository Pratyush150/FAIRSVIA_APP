# Vamos — Florida Ride-Hailing Marketing Website: COLD-START BUILD BRIEF

**For:** a fresh Claude Code session (or human dev) with zero prior context.
**Prepared:** August 2026 · **Status:** buildable spec, ready to execute.
**Companion doc (READ IT):** `./florida-gtm-strategy.md` — the master strategy. This brief is the *build* layer; the strategy is the *why*. Where this brief says "see Strategy §N," go read that section rather than trusting a paraphrase.

> **Brand name:** **Vamos** — *working name, pending trademark clearance* (shortlist: Vamos / Cabana / Sunroute / Palma / Verano; Strategy §6). Put "working name, pending trademark clearance" in the footer and anywhere the name is first introduced. Every brand string must come from ONE constant (`BRAND_NAME`) so a rename is one edit.

---

## 0. The honesty legend (read before writing one line of copy)

Three tags run through this whole build. They are load-bearing. Never let the site claim a 🔧 or 🔮 as if it ships today.

| Tag | Meaning | Site rule |
|---|---|---|
| ✅ **HAVE** | Real, working code today (many vendor integrations are "real-when-keyed, mock-by-default"). | May be marketed **once keyed** — see per-item notes. |
| 🔧 **BUILD-BEFORE-LAUNCH** | Thin, mocked, or absent; required before we can honestly claim it (or legally launch). | **Never** appears as a shipped feature. |
| 🔮 **FUTURE / NUANCED** | Real but nuanced, or a later ambition. | Only with the nuance stated; never oversold. |

### 🚫 THE HARD "NEVER CLAIM" LIST (grep-enforced at Definition of Done, §10)
These are non-negotiable. If any appears on the site as a live promise, the build is **rejected**.

1. **Insurance** — absent in code, **legally mandatory** (F.S. 627.748; Period 3 = $1M). Hard launch blocker. **No insurance claim of any kind — not "insured," "$1M coverage," "protected" — until the policy is bound.** (Strategy §14, §20 #1)
2. **SOS / "emergency" / "we call 911" / "share your trip with a contact"** — the in-app SOS is an **audit-log entry only**: no 911 dispatch, no contact notification, no trip-share delivery. Never market it as emergency response. (Strategy §14)
3. **Referral / "refer a friend" / "invite bonus"** — **absent in code**; only generic promo codes exist. No referral offer until built. (Strategy §7, §16)
4. **Live competitor pricing / "cheaper than Uber" as a measured fact** — the in-app "price comparison" is our own **internal self-disclaimed model**, not live Uber/Lyft quotes. Never present competitor prices, and don't lead on "cheaper." (Strategy §1, §7)
5. **Turn-by-turn navigation / live re-routing / "dynamic route updates"** — absent; OSRM computes the route **once** at booking. Don't imply live re-routing. (Strategy §7, §14)
6. Softer, still-banned-until-real: **"verified riders" / rider ID check** (absent 🔧), **car seats** (absent), **live per-driver ETA countdown** (absent 🔧), any **specific "average driver earnings" number** (contested — sell the *structure*, "see every dollar on every receipt," not a figure; Strategy §11).

### ✅ What you CAN say today (the full honest inventory)
Full ride lifecycle; production dispatch (Redis GEO, **favorite-driver priority**, presence heartbeat); real-time driver tracking; ride tiers (Economy/Comfort/XL/Premium) + **live surge engine with a published admin ceiling**; **OTP ride-start**; two-way ratings; ride history; **scheduled rides**; **promo codes**; saved places; **favorite drivers**; receipts; Stripe payments + tips + refunds + Connect payouts (**real-when-keyed**) + **CASH mode**; driver earnings ledger; support tickets + in-trip chat + push; **Checkr background checks (real-when-keyed)**; phone-OTP + JWT auth; admin app.
> "Real-when-keyed" (Stripe, Checkr) may be described in present tense on the site **only once the live key is in prod**. Until then the copy is written but the claim is gated behind launch. (Strategy §14)

### 🔮 Map/geocoding reality
Maps and geocoding are **self-hosted OSRM + Nominatim (OpenStreetMap)**. A Google provider exists in-app *if keyed* but is not the default. **Build the marketing map on OpenStreetMap/MapLibre, never Google Maps JS.** (§4 hero spec.)

---

## 1. Context for a fresh session

**What this is.** You are building the **marketing website** for **Vamos**, a new Florida-first ride-hailing brand. The *product* already exists: a **Flutter** rider/driver/admin app suite backed by a **NestJS + Postgres/PostGIS + Redis** modular-monolith backend (that's the rest of this repo). You are NOT building the app; you are building the public site that sells it.

**This is a separate codebase from the app.** Live it under `marketing/site/` (or a sibling repo). **Do NOT call the app's backend** (`192.168.1.48:3000/api/v1`) from the marketing site — those endpoints are for the app, not for public web forms. Marketing forms capture to their own lightweight store (§2).

**Pre-launch reality — be honest about it.** The app is **not in the App Store or Play Store yet.** So the download CTA is a **waitlist**, not "Download now." Say so plainly. The primary jobs of this site, in order:
1. **Credibility** — a Florida-native, honest brand a stranger will trust.
2. **Rider signups** → waitlist ("See your price" as the recurring verb, funnels to waitlist pre-launch).
3. **Driver applications** → "Apply to drive" (a real, capturable multi-step form).
4. **App-download intent** — banked as waitlist emails/SMS now; swap to store badges + QR at launch.

**The rules that govern this build** (from `CLAUDE.md` + Strategy §How-to-read):
- **Absolute honesty.** Never claim a 🔧/🔮 as shipped. If something isn't real, the site doesn't say it is.
- **Don't silently reduce goals.** If a page can't be honestly built (e.g. `/refer`), ship it as a "coming soon" stub, labeled — don't fake it.
- **Validate everything.** Lighthouse/CWV green, WCAG 2.2 AA, and the honesty grep (§10) are gates, not nice-to-haves.

---

## 2. Tech recommendation

### Stack (RECOMMENDATION — pick A unless the team wants zero-framework)

**Option A (recommended): Next.js (App Router) + Tailwind CSS, statically exported.**
- **Why:** file-based routing maps 1:1 to the SEO URL architecture (§7); React Server Components + `output: 'export'` give a static, CDN-hostable, fast site (meets the CWV budget); `generateStaticParams` makes the **city/airport/route page templates** (the whole SEO scale play) trivially data-driven from one JSON/MDX source; MDX powers `/blog`; built-in `<head>`/metadata API handles per-page title/meta/schema. Tailwind + CSS variables cleanly encode the design tokens (§6) incl. dark mode.
- **Constraints:** no server runtime at launch (static export) — forms post to an external endpoint (below). No secrets in the client bundle.

**Option B (zero-framework): semantic HTML + vanilla CSS (+ a tiny build step: Eleventy/11ty).**
- **Why:** if the team wants no React/Node toolchain, 11ty gives the same data-driven templating (`.njk` + JSON data files) over plain HTML/CSS, smallest possible payload, easiest to keep CWV perfect. Costs you React component ergonomics and MDX niceties.

Either way: **Inter** (body/UI) + **one variable display face** (headlines) self-hosted as `woff2` (no Google Fonts network dependency — perf + privacy). **MapLibre GL JS** for the map hero (§4). No Google Maps.

### Folder structure (Option A)
```
marketing/site/
├── app/
│   ├── layout.tsx                # <html>, theme bootstrap, header/footer, skip-link
│   ├── page.tsx                  # Homepage (§4)
│   ├── how-it-works/page.tsx
│   ├── riders/page.tsx
│   ├── drivers/page.tsx          # + driver-apply form (§5)
│   ├── safety/page.tsx           # ✅-only claims (§5)
│   ├── pricing/page.tsx
│   ├── cities/page.tsx
│   ├── cities/[city]/page.tsx    # template; generateStaticParams from data/cities.ts
│   ├── airports/page.tsx
│   ├── airports/[code]/page.tsx  # template; data/airports.ts
│   ├── business/page.tsx
│   ├── promotions/page.tsx
│   ├── refer/page.tsx            # 🔧 "coming soon" stub — NO live offer
│   ├── about/page.tsx
│   ├── blog/[slug]/page.tsx      # MDX
│   ├── help/page.tsx
│   ├── contact/page.tsx
│   ├── waitlist/page.tsx         # (a.k.a. /download pre-launch)
│   ├── terms/page.tsx
│   └── privacy/page.tsx
├── components/                   # design-system components (§6)
│   ├── ui/ (Button, Card, Badge, Accordion, Field, ...)
│   ├── MapHero.tsx
│   ├── FareBar.tsx
│   ├── WaitlistForm.tsx
│   └── DriverApplyForm.tsx
├── content/
│   ├── data/{cities,airports,routes,faqs}.ts   # single source for templated pages
│   └── blog/*.mdx
├── styles/tokens.css             # CSS variables: color/type/space/radius (§6)
├── lib/{brand.ts,analytics.ts,seo.ts}
├── public/{img,fonts,map}/       # self-hosted photos, woff2, static map fallback
└── scripts/honesty-grep.mjs      # §10 banned-claims scanner (CI gate)
```

### Forms pre-backend (waitlist + driver-apply)
Static export can't process a POST itself. Use ONE of:
- **Managed form endpoint** (Formspree / Basin / Netlify Forms / Web3Forms) → emails the team + optional Google Sheet/Airtable mirror. Fastest.
- **A tiny serverless function** (Vercel/Netlify function or a 20-line Cloudflare Worker) → writes to a managed DB (Supabase/Airtable) + sends notification. More control.
- **Spam control:** honeypot field + rate-limit; add hCaptcha/Turnstile only if abused (both self-hostable-ish, no Google reCAPTCHA for privacy parity).
- **NOT the app backend.** Repeat: do not wire these to `api/v1`.
- **Consent:** explicit opt-in checkbox for SMS/email; FL FDBR treats precise geolocation as sensitive (Strategy §4) — collect only what you need (email, name, zip, "rider or driver"), privacy-first.

### Analytics — event list to instrument
Use a privacy-respecting analytics tool (Plausible/PostHog self-host, or GA4 if required). Fire these named events:
```
page_view                         (auto)
cta_click            {location, label}   # every "See your price" / "Apply to drive"
waitlist_start / waitlist_submit  {role: rider|driver, city}
driver_apply_start
driver_apply_step    {step: 1..N}
driver_apply_submit
map_hero_interact    {action: pan|search}
faq_open             {question_id}
city_select          {city}
airport_select       {code}
promo_view / promo_copy
app_badge_click      {store}        # post-launch
outbound_click       {href}
```
Instrument a single **conversion funnel** mirroring Strategy §10.

### Performance / SEO budget (Core Web Vitals — gates, not goals)
| Metric | Target |
|---|---|
| LCP | ≤ 2.0 s (mobile, throttled) |
| INP | ≤ 200 ms |
| CLS | ≤ 0.05 |
| Lighthouse Perf / SEO / Best-Practices / A11y | ≥ 95 each (≥ 100 A11y goal) |
| JS shipped (homepage) | ≤ 120 KB gzip; map lib lazy-loaded, not in critical path |
| Fonts | self-hosted woff2, `font-display: swap`, ≤ 2 families |
| Images | AVIF/WebP, responsive `srcset`, explicit width/height, lazy below fold |

Map hero must **not** block LCP: server-render a static map image (public/map/tampa-static.avif) as the LCP element; hydrate MapLibre after load / on interaction / only when `prefers-reduced-motion: no-preference`.

---

## 3. Sitemap / information architecture

Priority: 🔴 launch MVP · 🟡 fast-follow · 🟢 later. (This flattens Strategy §8's deeper SEO tree into the launch page set; the `/ride/florida/...` and `/routes/...` SEO patterns from §8 are implemented via the templates in §7.)

| Route | Page title (browser) | Purpose | Primary CTA | Pri |
|---|---|---|---|---|
| `/` | Vamos — Florida rides, minus the surprises | Convert cold traffic; trust + wedge | See your price | 🔴 |
| `/how-it-works` | How Vamos works | Explain the rider product step-by-step | See your price | 🔴 |
| `/riders` | Ride with Vamos | Rider value + segments | See your price | 🔴 |
| `/drivers` | Drive with Vamos | Recruit drivers; the apply funnel | Apply to drive | 🔴 |
| `/safety` | Safety at Vamos | Honest (✅-only) trust page | See what's real | 🔴 |
| `/pricing` | Vamos pricing & surge ceiling | Explain fair pricing honestly | See your price | 🔴 |
| `/cities` | Where Vamos operates | City directory (SAB-honest) | Pick your city | 🔴 |
| `/cities/tampa` | Rideshare in Tampa \| Vamos | Launch-city commercial page | See your price in Tampa | 🔴 |
| `/cities/[city]` | Rideshare in {City} \| Vamos | City template (jacksonville, orlando, miami…) | See your price in {City} | 🟡 |
| `/airports/tpa` | Tampa Airport (TPA) rides \| Vamos | Highest-intent airport hub | Schedule your airport ride | 🟡¹ |
| `/airports/[code]` | {Airport} ({CODE}) rides \| Vamos | Airport template | Schedule your airport ride | 🟢¹ |
| `/waitlist` (`/download`) | Get Vamos | Capture app-download intent (waitlist) | Join the waitlist | 🔴 |
| `/promotions` | Vamos offers | First-ride credit (promo codes ✅) | Claim your first-ride credit | 🟡 |
| `/refer` | Refer a friend — coming soon | **🔧 stub only**, no live offer | Join the waitlist | 🟢² |
| `/business` | Vamos for business | B2B intent capture (no billing yet 🔮) | Talk to us | 🟢 |
| `/about` | About Vamos | Founder story, local-first mission | Join the waitlist | 🟡 |
| `/blog` + `/blog/[slug]` | {Post} \| Vamos | SEO/content engine (Strategy §12, §17) | Contextual | 🟡 |
| `/help` | Help & FAQ | Support hub | Contact us | 🟡 |
| `/contact` | Contact Vamos | Support/PR/driver questions | Send message | 🟡 |
| `/terms` | Terms of Service | Legal | — | 🔴 |
| `/privacy` | Privacy Policy | Legal (FDBR-aware) | — | 🔴 |

¹ **Airport pages ship only after that airport's TNC permit is secured** (Strategy §14, §20 #2). Build the template now; **don't publish/index** an airport page until permitted. Never quote MIA/FLL/TPA per-trip fees (only MCO's $7 is verified — Strategy §2).
² `/refer` exists so the nav/SEO slot is reserved, but shows only "Referrals are coming — join the waitlist to be first." **No bonus amount, no mechanic.**

**Global nav (header):** Riders · Drivers · Safety · Pricing · Cities · [See your price]. Split rider/driver clearly. **Footer:** Product (How it works, Pricing, Cities, Safety) · Company (About, Blog, Careers→stub, Contact) · Legal (Terms, Privacy) · Cities we serve. Footer carries the "working name, pending trademark clearance" line and the honest "not yet in app stores — join the waitlist" note.

---

## 4. Homepage — full build spec, section by section

Voice = **Vamos**: warm, plain-spoken, Florida-confident, never hypey, never over-promising. Real copy below — use it. Section order and rationale track Strategy §9; copy here is the build-ready version. Brand string via `BRAND_NAME`.

Layout container: max-width 1200px, 24px gutters (16px mobile). One accent (`--accent`, coral) only. Section vertical rhythm: 96px desktop / 64px mobile.

---

### Section 1 — Live-map hero
- **Purpose:** answer "does this actually work *here*?" in 2 seconds; transaction-first like Uber but leading with the trust promise.
- **Copy:**
  - **Headline (display face):** `Florida rides, minus the surprises.`
  - **Subhead:** `Pick a driver you trust. See your price before you book. Pay cash or card. Vamos is built for Florida — airports, cruise ports, and everywhere in between.`
  - **Primary CTA:** `See your price` → `/waitlist` pre-launch (deep-link to app post-launch).
  - **Secondary CTA:** `Join the waitlist` + a QR (pre-launch the QR points to `/waitlist`; swap to app stores at launch). **Do NOT say "Download now" pre-launch.**
- **Layout:** split hero — left: input card overlay (Pickup ▸ / Destination ▸ fields + primary CTA), right/behind: the map. On mobile the map is a full-bleed band with the card stacked below.
- **The map (build with the self-hosted OSM stack, NOT Google):**
  - Use **MapLibre GL JS** (open-source) with an **OpenStreetMap raster/vector tile source** — either our self-hosted tiles or a keyless OSM raster style — centered on the **Tampa** service area (`~27.9506, -82.4572`, zoom ~12).
  - Add an **animated pickup pin** (CSS/GL pulse) + a couple of drifting "car" markers to signal liveness. Purely illustrative — it is NOT live driver data (don't label it as real vehicles).
  - **Attribution:** OpenStreetMap contributor credit is required and must be visible.
  - **LCP-safe:** ship `public/map/tampa-static.avif` as the initial painted element; lazy-init MapLibre on idle/interaction. If `prefers-reduced-motion: reduce`, keep the static image, no animation.
  - Fields are UI-only pre-backend (they route to `/waitlist` with the typed pickup captured as intent) — **do not wire to `api/v1`**.
- **Asset:** real Tampa street context (via OSM tiles); if a photo band is used instead of a map on very small screens, use **real Florida street photography** (§6), never AI/3D.
- **Claims gate:** all ✅. "See your price before you book" = fare estimate (✅). Fine.

---

### Section 2 — Trust bar (the three-promise strip)
- **Purpose:** state the wedge in one scroll (Strategy §9.2, §7).
- **Copy — Headline:** `Three things every Florida ride should be.`
  - Card 1 — **No surge surprises** — `Prices can rise when it's busy, but never past a ceiling we publish.` (surge ceiling ✅)
  - Card 2 — **A driver you trust** — `Favorite a driver and they get priority to pick you up again.` (favorite-driver dispatch ✅)
  - Card 3 — **Cash or card** — `Ride without a credit card. Pay the way you want.` (cash mode ✅)
  - **CTA:** `See how it works` → `/how-it-works`.
- **Layout:** 3 flat hairline cards, equal width; stack to 1 column < 720px. Each card: coral line-icon, bold label, one sentence. No drop shadows.
- **Claims gate:** all ✅.

---

### Section 3 — How it works (condensed)
- **Purpose:** de-risk "how does this work" for a new brand.
- **Copy — Headline:** `From tap to receipt, no guesswork.`
  - Steps (all ✅): `1. See your price` (estimate + pick a tier) · `2. Match with a driver` (or your favorite) · `3. Start with a code` (OTP ride-start) · `4. Track it live` (real-time GPS) · `5. Pay & rate` (cash or card, two-way ratings, receipt).
  - **CTA:** `See the full walkthrough` → `/how-it-works`.
- **Layout:** horizontal 5-step tracker (numbered nodes on a hairline rail); vertical stack on mobile.
- **Claims gate:** all ✅. **Do NOT** add "live re-routing" or "turn-by-turn" to the tracking step.

---

### Section 4 — Price-certainty explainer (surge-ceiling proof)
- **Purpose:** make "no surprises" concrete; neutralize surge-shock (Strategy §9.3).
- **Copy — Headline:** `Surge with a ceiling — not a blank check.`
  - **Body:** `When it's busy, prices can rise — but never past a cap we publish. No $65 rides to the airport.`
  - **CTA:** `See your price`.
- **Component:** `<FareBar>` — an annotated horizontal fare-anatomy bar: `Base + Time + Distance` segments in neutral, then a **capped surge band highlighted in coral** with a hard "ceiling" stop line labeled *"published cap."* Animated grow-in on scroll-reveal (respect reduced-motion).
- **Claims gate:** ✅ surge engine + admin ceiling. **Never** cite the internal price-comparison model as a competitor quote (🔮). Don't put a specific dollar cap number unless it's the real configured value.

---

### Section 5 — Favorite-driver / trust
- **Purpose:** sell human continuity (Strategy §9.4).
- **Copy — Headline:** `Ride with someone you've ridden with before.`
  - **Body:** `Favorite a driver, and Vamos gives them priority to pick you up again. Every ride starts with a verification code, so you always know it's the right car.`
  - **Trust chips (✅ only):** `OTP ride-start` · `Two-way ratings` · `Driver, car & plate shown before you get in` · `Live GPS tracking` · `Background checks via Checkr` *(this chip is gated — render only once Checkr is keyed in prod; until then omit it, don't fake it)*.
  - **CTA:** `See how we keep rides safe` → `/safety`.
- **Layout:** two-column — left: illustration of "re-request your driver"; right: trust chips as hairline badges.
- **Claims gate:** ✅. **No SOS, no insurance, no "verified riders."**

---

### Section 6 — Built for Florida
- **Purpose:** own local — the moat incumbents can't template (Strategy §9.5, §3 gap #1).
- **Copy — Headline:** `From the terminal to the ship to your front door.`
  - **Body:** `Vamos knows Florida — record airport traffic, three of the world's busiest cruise ports, snowbird season, and every event weekend in between.`
  - **CTA:** `Find your city` → `/cities`.
- **Layout:** a stylized FL map or horizontal chip row naming **TPA · MCO · MIA · FLL · JAX** and **Port Tampa Bay · PortMiami · Port Canaveral · Port Everglades**. Tampa emphasized (launch city).
- **Claims gate:** naming airports/ports is fine (geographic fact). **Airport *service* claims are gated on permits** — phrase as "built for" / "knows," not "book your MCO ride" until permitted.

---

### Section 7 — Driver CTA band
- **Purpose:** recruit supply (Strategy §9.8, §11).
- **Copy — Headline:** `Drive with Vamos — keep more of every fare.`
  - **Sub:** `See your pay itemized on every ride. Get paid fast. No mystery math, no exclusivity.`
  - **CTA:** `Apply to drive` → `/drivers`.
- **Layout:** full-width coral-tinted band (or near-black inverse), single strong CTA.
- **Claims gate:** ✅ earnings ledger + Stripe Connect payouts (fast pay gated on keying). **No earnings number.**

---

### Section 8 — Cities / availability
- **Purpose:** honest "where we are" — Tampa first.
- **Copy — Headline:** `Starting in Tampa. Florida next.`
  - **Body:** `We're launching in Tampa Bay and adding cities across Florida. Join the waitlist and we'll tell you the day Vamos reaches you.`
  - **CTA:** `See Tampa` → `/cities/tampa`.
- **Claims gate:** honest about pre-launch. Don't imply live service in cities without supply (doorway/thin-content and honesty risk, Strategy §12).

---

### Section 9 — Social proof (honest)
- **Purpose:** credibility without fake scale (Strategy §9.6, §3 gap #3).
- **Copy — Headline:** `Real riders. Real drivers. Real Florida.`
  - **Pre-launch content:** a **waitlist counter** ("N Floridians already in line" — only if real), **founding-driver quotes** (attributed, real people). **No invented review counts, no borrowed App Store stars.**
- **Layout:** testimonial cards with real name + city + photo (or initial avatar if no photo). Source attribution where a review is external.
- **Claims gate:** everything here must be **verifiable**. If we have zero real quotes at build time, ship the section as the waitlist counter + founder note only.

---

### Section 10 — Promo / waitlist
- **Purpose:** reduce first-purchase risk; capture the lead (Strategy §9.7).
- **Copy — Headline:** `Your first ride's on us — up to $10 off.` *(final $ set at launch; promo codes are ✅)*
  - **Body:** `Join the waitlist now and we'll send your first-ride credit the day Vamos launches in your city.`
  - **CTA:** `Join the waitlist` → `<WaitlistForm>` (email + city + rider/driver toggle).
- **Claims gate:** promo codes ✅. Phrase the credit as a launch offer (honest — app isn't live yet). **No referral.**

---

### Section 11 — FAQ
- **Purpose:** answer objections + AI-Overview SEO (FAQPage schema, Strategy §12).
- Use 6–8 of the FAQ set from §8 of this brief (accordion). Mark up with FAQPage schema (§7).
- **Claims gate:** every answer honest per §8.

---

### Section 12 — Final CTA
- **Copy — Headline:** `Get Vamos. Get going.`
  - **Sub (pre-launch):** `The app is almost here. Join the waitlist and be first to ride.`
  - **CTA:** `Join the waitlist` + QR. **Post-launch:** swap to App Store / Google Play badges + QR.
- **Claims gate:** **no "Download now" until the app is actually in stores.**

---

### Section 13 — Footer
- 4 columns: **Product · Company · Legal · Cities we serve**. Include the honest `/safety` link (not an over-claim). Carry: "**Vamos** is a working name, pending trademark clearance." and "Not yet in the App Store or Google Play — join the waitlist." Language toggle EN/ES optional (Strategy §6 bilingual note). OSM attribution if the footer mini-map is used.

---

## 5. Key landing pages — build specs

### 5a. For Riders (`/riders`)
- **Hero:** `Every ride should feel fair.` / sub: `A driver you trust, a price you saw first, paid cash or card. That's the whole idea.` / CTA `See your price`.
- **How it works** row (mirror §4.3, all ✅).
- **Tiers:** Economy · Comfort · XL · Premium (✅). One line each; no fabricated prices.
- **Why Vamos:** surge ceiling · favorite driver · cash or card · scheduled rides · saved places (all ✅).
- **Segments strip** (from Strategy §5): commuter, tourist, student, family, senior/snowbird, nightlife — one honest line + the real feature each cares about. (Families: **do not claim car seats.**)
- **Safety teaser** → `/safety`. **FAQ** (rider subset). **Final CTA** `See your price`.
- **Wireframe:** extend Strategy §19 "For Riders."

### 5b. For Drivers (`/drivers`) — CRITICAL, full spec
This page must recruit and capture applications. Framing = **structural transparency, never an earnings number** (Strategy §11).
- **Hero headline:** `Florida drivers, keep more of every fare. No mystery math.`
  - City-swap variant for paid search: `Drive Tampa. Keep more of every fare.`
  - **Sub:** `See your pay itemized on every ride. Get paid fast. Add Vamos alongside Uber and Lyft — most drivers run more than one app.`
  - **Primary CTA:** `Apply to drive` (scrolls to / opens `<DriverApplyForm>`).
- **Earnings framing block:** the itemized-receipt graphic — **"$18 fare → see exactly what you keep."** Line items: fare, our fixed commission (shown), tips (100% yours), your take. Tagline: **"See every dollar on every receipt."** (✅ ledger.) **No average-earnings figure.**
- **What's real (✅ chips):** itemized earnings ledger · fast payouts (Stripe Connect — *gated on keying*) · favorite-driver priority = repeat riders · online/offline control · accept/decline · in-app support + chat.
- **Requirements checklist** (company policy, not "the law" — Strategy §11): `21+` · `Valid U.S. license, 1+ year` · `Vehicle passes inspection` · `Pass a background check (via Checkr)` · `Eligible vehicle`. Footnote: 21+/inspection are our policy/insurer floor, not all statutory.
- **Multi-step apply form** `<DriverApplyForm>` (captures to the marketing store, §2 — **NOT** `api/v1`). Fields:
  - Step 1 — Contact: `firstName`, `lastName`, `phone` (OTP-style field, but pre-backend just validate format), `email`, `city` (select).
  - Step 2 — Eligibility (checkboxes/attestations): `age21Plus`, `licensedOneYear`, `hasEligibleVehicle`, `vehicleYear`, `vehicleMakeModel`, `consentBackgroundCheck`.
  - Step 3 — Availability & source: `hoursPerWeek`, `alreadyDrivesFor` (Uber/Lyft/Empower/inDrive/none — multi-select), `referralSource`.
  - Step 4 — Consent + submit: SMS/email opt-in checkbox, privacy link, `submit`.
  - **Honesty note in the form:** "Document upload and full onboarding happen after you're invited." — because the **doc-upload pipeline is 🔧** (`docsVerified` is a manual admin toggle today, Strategy §11). Don't imply instant approval.
  - Show a `driver_apply_step` event per step and `driver_apply_submit` on finish.
- **Objection-busters** (accordion, verbatim honest — Strategy §11):
  - *Will I get enough rides?* → `We're new in Tampa, so drive us alongside Uber and Lyft, not instead. No exclusivity, ever.`
  - *How fast do I get paid?* → `Fast payouts through our payments partner.` (gated on keying)
  - *What if I'm deactivated?* → `We publish an appeal process with a human review step.` *(the appeal SLA is 🔧 — only ship this line once the workflow exists; until then omit.)*
  - *Is this legal in Florida?* → `Yes — we operate as a compliant TNC under Florida law (F.S. 627.748).` *(state only what counsel confirms.)*
  - *What does it cost me?* → `One transparent, fixed commission, shown on every receipt. No subscription, no hidden take.`
- **Wireframe:** Strategy §19 "For Drivers."

### 5c. Safety (`/safety`) — ✅ CLAIMS ONLY
Format: borrow Waymo's *evidentiary* approach but with only what's real (Strategy §14). **Under-claim, over-deliver.**
- **Hero:** `Safety you can actually verify.`
- **"What's real today" grid (✅):** OTP ride-start · two-way ratings · live GPS trip tracking · driver + car + plate shown before you get in · electronic receipt with route/time/distance · favorite drivers · **background checks via Checkr** *(gated — show only once keyed)*.
- **Florida law block:** `Florida's TNC law (F.S. 627.748) sets the safety floor we build on.` Mention **$1M active-trip coverage — ONLY once insurance is bound** (until then, omit the coverage figure entirely).
- **Named FL safety partner:** placeholder block, populate only once a real partner is secured (à la Lyft's Council).
- **🚫 HARD BANS on this page:** no "SOS," no "emergency button," no "we call 911," no "share your trip with a contact," no insurance claim until bound, no "verified riders." (Strategy §14, §1.)
- **Wireframe:** Strategy §19 "Safety."

### 5d. City template — Tampa filled in (`/cities/tampa`)
Data-driven from `content/data/cities.ts`. **Doorway-page guardrail (Strategy §12): each city page MUST carry unique, dated local content — never just a name-swap** (post-Mar-2024 Google penalized name-swap city pages, 80%+ lost rankings). Mandatory unique blocks per city:
- **H1:** `Rideshare in Tampa` + `See your price in Tampa`.
- **Local trip metrics** (dated "as of Aug 2026"): avg time / **price *range*** / distance for real local trips. Date-stamp everything.
- **Popular Tampa routes** (internal links to route pages): TPA ↔ Downtown Tampa · TPA ↔ Busch Gardens · Downtown ↔ Port Tampa Bay.
- **Why Vamos in Tampa:** surge ceiling · cash or card · local-first · scheduled rides (all ✅).
- **Local hooks (real):** Tampa Bay ~3.42M metro, TPA airport, **Port Tampa Bay cruise**, Busch Gardens, USF (student safe-ride angle), downtown/Ybor nightlife (surge-ceiling angle). TPA waiting lot: 2402 N Westshore Blvd (informational).
- **Local FAQ** (≥1 Tampa-specific Q, schema-marked, §7).
- **TNC-compliance line + LAST-UPDATED stamp** + `See your price`.
- **🚫** Do NOT quote a TPA airport pickup fee ($6.50/$20 min is unverified/conflicting — Strategy §2). Only MCO's $7 is verified, and that's Orlando.
- **Wireframe:** Strategy §19 "City landing page."

### 5e. Airport template — TPA (`/airports/tpa`)
**Publish only once the TPA TNC permit is secured** (Strategy §14). Build now, gate publish/index.
- **H1:** `Tampa Airport (TPA) Rides` + `Schedule your airport ride` (✅ scheduled rides).
- **Trip metrics:** TPA → Downtown ~15 min, price *range* (dated). **No unverified airport-fee claim.**
- **Pickup instructions** by terminal/level + waiting-lot note (2402 N Westshore Blvd).
- **Schedule-your-ride block** (✅). Surge-ceiling reassurance. Popular routes. Local FAQ. Compliance + last-updated.
- **IATA-code URL** (`/airports/tpa`) — codes are globally unique, template generalizes to mco/mia/fll/jax (Strategy §12). **Don't publish MIA/FLL until permitted; never quote their fees.**
- **Wireframe:** Strategy §19 "Airport landing page."

### 5f. Pricing (`/pricing`)
- **Hero:** `A fair price, and you see it first.`
- **Explain honestly:** base + time + distance + a **surge band with a published ceiling**; `<FareBar>` reused. `When it's busy, prices can rise — but never past a cap we publish.`
- **Cash or card** section (✅).
- **"Exact fares live in the app"**: `Your exact fare shows in the app before you confirm — tap "See your price."` (fare estimate ✅). Explain there's no exact number on the web because it depends on the trip.
- **🚫** Never present the internal price-comparison model as competitor pricing; don't lead on "cheaper" (Strategy §7).

### 5g. How It Works (`/how-it-works`)
Full rider walkthrough (expand §4.3): See your price → choose tier/favorite → match → OTP start → live track → pay (cash/card) → rate + receipt. All ✅. **No re-routing/turn-by-turn.** Add a short "for drivers" cross-link.

---

## 6. Design system spec

Tokens track Strategy §15 (the dominant 2026 convention: near-monochrome base + exactly ONE functional accent + one display face + flat hairline components). Encode as CSS variables in `styles/tokens.css`.

### Color tokens
```css
:root {                         /* LIGHT (default) */
  --canvas:        #FAFAF8;     /* warm off-white */
  --canvas-2:      #F5F4F0;     /* alt surface */
  --ink:           #141414;     /* near-black text (not pure black) */
  --ink-2:         #55524C;     /* muted text */
  --hairline:      #E5E3DE;     /* neutral-gray borders */
  --accent:        #FF5A36;     /* WARM CORAL — the ONE functional accent */
  --accent-press:  #E64826;     /* pressed/hover */
  --accent-tint:   #FFE9E3;     /* coral wash for bands */
  --accent-ink:    #FFFFFF;     /* text on accent (verify 4.5:1) */
  --success:       #1F7A4D;
  --focus-ring:    #1655D6;     /* high-contrast focus (blue is fine here, non-brand) */
}
:root[data-theme="dark"], @media (prefers-color-scheme: dark) { /* guard per your framework */
  --canvas:        #121110;
  --canvas-2:      #1B1A18;
  --ink:           #F5F4F0;
  --ink-2:         #B7B2A9;
  --hairline:      #2C2A27;
  --accent:        #FF6B4A;     /* slightly lifted coral for dark */
  --accent-press:  #FF8163;
  --accent-tint:   #2A1A15;
  --accent-ink:    #141414;
  --focus-ring:    #7FA6FF;
}
```
Rules (Strategy §15): **reserve the accent for CTAs, live/active states, money-or-motion moments only.** Blue=Uber/Waymo, pink=Lyft, green=Wise, yellow=Ramp/Bolt — coral is uncontested + Florida-sun. **Dark mode is structural, not optional.** No rainbow "friendly taxi" palette.

### Type scale
- **Body/UI:** **Inter** (self-hosted variable woff2). Base 16px, scale 1.2 (minor-third): 12.8 / 16 / 19.2 / 23 / 28 / 33.5 / 40 / 48 / 58.
- **Display (headlines only):** **one distinctive variable face** — recommend a free, distinctive variable display: **Clash Display** (Fontshare), **Space Grotesk**, or **Fraunces** (warm variable serif) — pick ONE, self-host, use for hero + section H2s only. Tight leading ~1.0–1.1, oversized, confident (Strategy §15). This buys the "proprietary type" signal without commissioning a face. Verify license permits web embedding.
- Weights: body 400/500/600; display 500–700. Line-height: body 1.5, headings 1.05–1.15.

### Spacing / radius / elevation
```
space: 4 8 12 16 24 32 48 64 96 (px)
radius: card 14px · button 8px · pill 999px · input 10px
depth: BORDER, not shadow — 1px solid var(--hairline). Shadows off (or ≤ a 1px hairline glow).
```

### Component inventory
- **Buttons:** primary (accent fill, `--accent-ink`), secondary (ink outline/hairline), ghost (text). 8px radius, 44px min tap height. Loading + disabled states.
- **Nav:** sticky header, hairline bottom border, rider/driver split, persistent `See your price`; mobile drawer.
- **Cards:** flat, hairline border, 14px radius, no shadow.
- **MapHero:** MapLibre GL + OSM tiles, static-image LCP fallback, reduced-motion aware (§4).
- **FareBar:** annotated surge-ceiling bar (§4.4).
- **Forms/Field:** label always visible, 10px radius, hairline border, error text tied via `aria-describedby`, 44px targets.
- **Accordion:** FAQ + objection-busters; button-based, `aria-expanded`, keyboard operable.
- **Badge/Chip:** trust chips (✅ features), hairline pill.
- **Testimonial:** real name + city + avatar; source attribution slot.
- **CTA block:** waitlist form + QR (pre-launch) / store badges (post-launch) — one component, a `phase` prop.
- **Step tracker:** numbered nodes on a hairline rail.

### Motion principles
Functional, not decorative (Strategy §15): (1) live-map hero is the single highest-value animation; (2) subtle scroll-reveal on trust/stat sections; (3) **no scroll-jacking/parallax**. Everything honors `prefers-reduced-motion: reduce` (map goes static, reveals become instant). Coral used for "money-or-motion" moments (FareBar grow-in, live pin).

### Iconography
One consistent line-icon set (e.g. Lucide/Phosphor), 1.5px stroke, inherits `currentColor`, accent only on active. No emoji as UI icons.

### Imagery / art direction
- **Lead with real Florida photography** (Strategy §15): real cars, real drivers, real Tampa/FL streets — answers the core "is this real, will a real car come?" anxiety. **No stocky AI faces, no 3D renders for people.** Reserve tasteful illustration/3D only for abstract concepts (surge mechanics, earnings ledger).
- **What to shoot:** Tampa street pickups (daylight + golden hour), a real driver greeting a rider, phone-in-hand "start with a code" moment, airport curb + cruise terminal context, diverse riders (commuter, senior/snowbird, student, family), cash-and-card moment. Warm, natural light; candid > posed; coral accents in-scene where natural.
- Formats: AVIF/WebP, `srcset`, explicit dimensions.

### Accessibility checklist (WCAG 2.2 AA — build to it from day one; Strategy §15)
- **Contrast:** body/UI ≥ 4.5:1, large text ≥ 3:1, non-text/UI ≥ 3:1. Verify coral-on-canvas and text-on-coral both pass (coral fill needs `--accent-ink` white/near-black chosen to pass).
- **Focus:** visible focus indicator (≥ 3:1, ≥ 2px) on every interactive element (WCAG 2.2 Focus Appearance/Not Obscured). Logical tab order. Skip-to-content link.
- **Motion:** honor `prefers-reduced-motion`; no motion-only information; nothing auto-plays with sound.
- **Forms:** visible labels (not placeholder-only), errors announced + `aria-describedby`, targets ≥ 24×24 (aim 44×44), inputs grouped with `<fieldset>/<legend>` in the multi-step apply form.
- **Structure:** one `<h1>`/page, ordered headings, landmarks (`header/nav/main/footer`), alt text on all meaningful images (empty alt on decorative), lang attribute, `prefers-color-scheme` + manual theme toggle.
- **Target: Lighthouse a11y 100.** (Litigation context: 3,117 federal web-accessibility suits in 2025, +27% YoY — Strategy §15.)

---

## 7. SEO build spec

### Scalable URL architecture (city → metro → state → new-states)
This brief's launch routes (§3) sit on top of the Strategy §12 production pattern. Implement templates so the site scales without new code:
```
/cities/                         ← city directory (state hub role)
/cities/tampa/                   ← metro commercial page   (data/cities.ts)
/cities/{city}/                  ← generalizes across FL, then TX/etc.
/airports/{iata}/                ← IATA codes globally unique → no state prefix
/airports/{iata}/pickup/         ← (later) pickup detail
/routes/{origin}-to-{destination}/  ← combinatorial: airport × landmark/port (later)
/drivers/{city}/                 ← driver mirror (later)
/blog/{slug}/
```
IATA codes are globally unique (zero prefix needed). Keep depth flat (~3 levels) to hold link equity near root (Strategy §12). Generate templated pages via `generateStaticParams` from the `content/data/*` files — **but only for cities/airports with real service/permits** (no auto-gen for zero-supply cities).

### Per-page `<title>` / meta templates (variables in `{}`)
| Page | `<title>` | meta description |
|---|---|---|
| Home | `Vamos — Florida rides, minus the surprises` | `Pick a driver you trust, see your price before you book, pay cash or card. Vamos is built for Florida.` |
| City | `Rideshare in {City}, FL — fair prices, no surge surprises \| Vamos` | `Book a ride in {City} with a driver you trust and a price with a published ceiling. Cash or card. See your price.` |
| Airport | `{Airport} ({CODE}) rideshare & pickup guide \| Vamos` | `Rides to and from {Airport} ({CODE}). Schedule ahead, see your price first, no surge surprises. Cash or card.` |
| Drivers | `Drive with Vamos in {City} — keep more of every fare` | `See your pay itemized on every ride, get paid fast, no exclusivity. Apply to drive with Vamos.` |
| Route | `{Origin} to {Destination} by rideshare — time, price range & tips \| Vamos` | `How long and how much from {Origin} to {Destination}, updated {Month Year}. See your price with Vamos.` |
| Safety | `Safety at Vamos — what we can actually verify` | `OTP ride-start, live tracking, two-way ratings, background checks. The honest safety facts, no over-claims.` |
Keep titles ≤ ~60 chars, descriptions ≤ ~155. `{City}`, `{CODE}` from data files.

### Heading structure
One `<h1>` per page = the page's core query (`Rideshare in Tampa`). `<h2>` = major blocks (routes, why, FAQ). `<h3>` = individual FAQs/routes. No skipped levels.

### schema.org (JSON-LD) to embed
- **Sitewide (`Organization` + `LocalBusiness`/`TaxiService`):** name, url, logo, `areaServed` (`GeoCircle` per city), `sameAs`. Configure Google Business Profile as a **service-area business** (SAB) — don't fake a storefront (Strategy §12).
- **City/Airport pages:** `TaxiService` (subtype of `Service`) with `provider` = the LocalBusiness, `areaServed`.
- **FAQ blocks:** **`FAQPage`** — Google **removed FAQ rich results May 7 2026**, so don't build the plan around FAQ SERP snippets, **but keep the markup**: FAQPage pages are ~3.2× likelier to surface in AI Overviews (Strategy §12).
- **All pages:** `BreadcrumbList` matching the URL hierarchy.
- **Blog:** `Article`/`BlogPosting` with `datePublished`/`dateModified`.
- **Date-stamp every fare figure** in `dateModified` + visible "as of {Month Year}."

### City/Airport content-block template (with the doorway-page warning)
**🔴 Doorway-page guardrail (Strategy §12):** Google penalizes near-identical pages that differ only by a swapped city name (post-Mar-2024: 80%+ of such pages lost rankings, up to 63% traffic drop). The *architecture* scales; the *content* must not be templated boilerplate. **Every city/airport page MUST have, uniquely:**
1. Dated local fare **ranges** (not a single national number).
2. ≥ 1 locally-specific FAQ (real local question).
3. Real named local landmarks / routes / ports.
4. Unique `<title>`, meta, and `<h1>`.
5. **No page generated for a city/airport with zero real driver supply or (airports) no permit.**

### Internal linking
Home → city directory → city page → its route pages; city ↔ its airport; drivers-home → driver-city. Blog posts link to the relevant commercial city/airport page (MOFU/BOFU → conversion). Breadcrumbs on every deep page.

### Pre-launch indexation plan
- `robots.txt` + XML sitemap: **allow** the launch MVP (home, how-it-works, riders, drivers, safety, pricing, cities, /cities/tampa, waitlist, legal).
- **`noindex` (or don't publish) until real:** any airport page without a permit; any city with no supply; `/refer` (stub); `/business` if unstaffed.
- Register GBP as SAB; submit sitemap to Search Console; verify canonical tags (self-referencing) on every page.
- Post-launch: weekly Search Console near-miss optimization (Strategy §17).

---

## 8. Copy bank (approved, honest, Vamos voice)

**Tagline:** `No surge surprises. A driver you trust.`
**Positioning line:** `The Florida ride that treats you fairly — pick a driver you trust, pay a price with no surprises, cash or card.`

**Headline variants (approved):**
1. `Florida rides, minus the surprises.` (home hero)
2. `No surge surprises. A driver you trust.`
3. `Three things every Florida ride should be.`
4. `Surge with a ceiling — not a blank check.`
5. `Ride with someone you've ridden with before.`
6. `From the terminal to the ship to your front door.`
7. `Every ride should feel fair.` (riders)
8. `Florida drivers, keep more of every fare. No mystery math.` (drivers)
9. `Safety you can actually verify.` (safety)
10. `Starting in Tampa. Florida next.`

**Elevator paragraph:**
`Vamos is a Florida-first ride-hailing app built on one idea: rides should feel fair. Pick a driver you trust and they get priority to pick you up again. See your price before you book, with a surge ceiling we publish — so busy nights never turn into a blank check. Pay cash or card. We're starting in Tampa and building out across Florida — airports, cruise ports, snowbird season, and every event weekend in between.`

**Differentiator one-liners** (Strategy §7):
- Favorite-Driver Priority — `Favorite a driver, and they get priority to pick you up again.` (✅)
- Surge Ceiling — `Prices can rise when it's busy — never past a cap we publish.` (✅)
- Cash or Card — `Ride without a credit card. Pay the way you want.` (✅)
- Fair Driver Pay — `Every driver sees their pay itemized on every receipt.` (✅ ledger)
- Florida-Native — `Built for Florida's airports, cruise ports, snowbirds and events.`

**Driver pitch lines** (Strategy §11 — no earnings number):
- `See every dollar on every receipt.`
- `Get paid fast. No mystery math.`
- `Add Vamos alongside Uber and Lyft — most drivers run more than one app.`
- `One transparent, fixed commission. No subscription, no hidden take.`

**Trust one-liners (honest, ✅ only):**
- `Every ride starts with a verification code.`
- `See your driver, car and plate before you get in.`
- `Watch your ride on a live map, start to finish.`
- `Two-way ratings on every trip.`
- `Drivers pass a background check via Checkr before their first ride.` *(gated — only once keyed)*
> **Banned trust lines:** anything about insurance, SOS/911, emergency contacts, trip-share delivery, verified riders — until real (§0).

**FAQ set (10–15, all honest — reuse across home/help/city with FAQPage schema):**
1. **Where does Vamos operate?** — `We're launching in Tampa Bay and expanding across Florida. Join the waitlist and we'll tell you the day we reach your city.`
2. **Can I download the app now?** — `Not yet — Vamos isn't in the App Store or Google Play yet. Join the waitlist and you'll be first to know when it goes live.`
3. **How does "no surge surprises" work?** — `When demand is high, prices can rise — but never past a ceiling we publish. No runaway fares.`
4. **Can I pay with cash?** — `Yes. Vamos supports cash or card — no credit card required.`
5. **What is a "favorite driver"?** — `Favorite a driver you liked, and Vamos gives them priority to pick you up again on future rides.`
6. **How do I know my ride is safe?** — `Every ride starts with a verification code, you see your driver, car and plate up front, and you can watch the trip on a live map. Drivers pass a background check via Checkr.` *(background-check line only once keyed)*
7. **Do you have an SOS/emergency button?** — `Not yet. We're building safety features carefully and won't advertise anything until it's real. For emergencies, always call 911.` *(honest — SOS is 🔧)*
8. **Is Vamos cheaper than Uber or Lyft?** — `We don't compete on being the cheapest — we compete on a fair, predictable price with a published surge ceiling. Your exact fare shows in the app before you confirm.` *(never present competitor prices)*
9. **Can I schedule a ride in advance?** — `Yes — scheduled rides are supported, great for airport pickups and regular commutes.`
10. **How do I become a driver?** — `Apply to drive on our drivers page. After you apply and we invite you, you'll complete onboarding and a background check.`
11. **How much do drivers earn?** — `Your pay is itemized on every ride and you keep 100% of your tips. We don't quote an "average" because real earnings depend on when and where you drive.`
12. **What does it cost a driver to use Vamos?** — `One transparent, fixed commission, shown on every receipt. No subscription, no hidden take.`
13. **Do you serve the airport?** — `We're built for Florida airports and adding them as we secure the required permits. Check your city's page for current service.` *(airport service is permit-gated)*
14. **Is Vamos legal in Florida?** — `Yes — Vamos operates as a compliant transportation network company under Florida law (F.S. 627.748).`
15. **Do you provide car seats?** — `Not at this time.` *(honest — absent)*

---

## 9. Text wireframes (build-ready, with component names)

**Homepage** (`app/page.tsx`)
```
┌──────────────────────────────────────────────────────────┐
│ <Header> VAMOS  Riders Drivers Safety Pricing Cities [See price]│
├──────────────────────────────────────────────────────────┤
│ <MapHero>  [MapLibre+OSM, static-AVIF LCP, animated pin]  │
│   <Card> Pickup ▸  Destination ▸   "Florida rides, minus  │
│          [ See your price ]         the surprises."        │
│                                     [Join waitlist ▸ QR]   │
├──────────────────────────────────────────────────────────┤
│ <TrustBar> [Card:No surge][Card:Driver you trust][Card:Cash]│
├──────────────────────────────────────────────────────────┤
│ <StepTracker> price▸match▸code▸track▸pay  (all ✅)          │
├──────────────────────────────────────────────────────────┤
│ <FareBar> ▓▓▓▓░ cap in coral  "Surge with a ceiling" [See price]│
├──────────────────────────────────────────────────────────┤
│ <TrustSection> Favorite driver | OTP·ratings·plate·tracking│
├──────────────────────────────────────────────────────────┤
│ <FloridaBand> TPA·MCO·MIA·FLL·JAX + cruise ports  [Cities]│
├──────────────────────────────────────────────────────────┤
│ <SocialProof> waitlist counter + founding-driver <Testimonial>│
├──────────────────────────────────────────────────────────┤
│ <PromoBlock> "First ride up to $10 off" <WaitlistForm>    │
├──────────────────────────────────────────────────────────┤
│ <DriverBand> "Keep more of every fare" [Apply to drive ▸] │
├──────────────────────────────────────────────────────────┤
│ <FAQ Accordion + FAQPage schema>                          │
├──────────────────────────────────────────────────────────┤
│ <FinalCTA> "Get Vamos. Get going." [Join waitlist ▸ QR]   │
├──────────────────────────────────────────────────────────┤
│ <Footer> Product|Company|Legal|Cities  ·"working name…"·  │
└──────────────────────────────────────────────────────────┘
```

**For Drivers** (`app/drivers/page.tsx`)
```
┌──────────────────────────────────────────────────────────┐
│ <DriverHero> "Florida drivers, keep more of every fare.   │
│   No mystery math."               [Apply to drive]        │
├──────────────────────────────────────────────────────────┤
│ <ReceiptGraphic> $18 fare → fixed commission → you keep $ │
│   "See every dollar on every receipt."   (NO avg number)  │
├──────────────────────────────────────────────────────────┤
│ <Badge row> Itemized ledger · Fast payout* · Favorite     │
│   repeat riders · Online/offline · Accept/decline  (✅)    │
├──────────────────────────────────────────────────────────┤
│ <RequirementsChecklist> 21+ · license 1yr · inspection ·  │
│   background check (Checkr) · eligible vehicle            │
├──────────────────────────────────────────────────────────┤
│ <DriverApplyForm> Step1 Contact ▸ Step2 Eligibility ▸     │
│   Step3 Availability ▸ Step4 Consent+Submit               │
│   note: "docs & onboarding after you're invited" (🔧)     │
├──────────────────────────────────────────────────────────┤
│ <ObjectionAccordion> rides? pay speed? deactivation*?     │
│   legal? cost?                                            │
├──────────────────────────────────────────────────────────┤
│ <FinalCTA> [Apply to drive ▸]   <Footer>                  │
└──────────────────────────────────────────────────────────┘
  * gated: fast-payout & appeal-SLA lines only once real/keyed
```

**City page** (`app/cities/[city]/page.tsx`, Tampa shown)
```
┌──────────────────────────────────────────────────────────┐
│ <CityHero> H1 "Rideshare in Tampa"  [See your price in Tampa]│
├──────────────────────────────────────────────────────────┤
│ <LocalMetrics> avg time / PRICE RANGE / distance          │
│   "as of Aug 2026"  (dateModified schema)                 │
├──────────────────────────────────────────────────────────┤
│ <RouteLinks> TPA↔Downtown · TPA↔Busch Gardens · ↔Port     │
├──────────────────────────────────────────────────────────┤
│ <WhyBlock> surge ceiling · cash or card · local (✅)       │
├──────────────────────────────────────────────────────────┤
│ <LocalFAQ + FAQPage schema>  (≥1 Tampa-specific Q)        │
├──────────────────────────────────────────────────────────┤
│ <ComplianceLine + LastUpdated>  [See your price] <Footer> │
└──────────────────────────────────────────────────────────┘
  NO TPA airport-fee claim (unverified). Unique content = doorway-safe.
```

---

## 10. Build order & acceptance criteria

### Phased checklist
- **Phase 0 — Scaffold:** Next.js + Tailwind (or 11ty), `tokens.css`, `brand.ts` (`BRAND_NAME`), fonts self-hosted, layout/header/footer, theme toggle + dark mode, analytics wired, `scripts/honesty-grep.mjs` in CI.
- **Phase 1 — Design system (§6):** all `components/ui/*`, MapHero, FareBar, forms, accordion, testimonial, CTA block. Storybook or a `/_kitchen-sink` page. A11y-audited.
- **Phase 2 — Homepage (§4):** all 13 sections, real copy, MapLibre+OSM hero with static LCP fallback.
- **Phase 3 — Riders + Drivers (§5a, §5b):** driver-apply multi-step form → capture endpoint (§2). Waitlist form live.
- **Phase 4 — Safety + Pricing (§5c, §5f):** ✅-only safety; honest pricing.
- **Phase 5 — City + Airport templates (§5d, §5e):** data-driven, Tampa filled, doorway-safe; airport pages built but publish-gated on permits.
- **Phase 6 — Blog / Help / Legal / Cities dir / About / Contact / Waitlist / promotions / refer-stub:** MDX blog, FAQPage help, Terms/Privacy (FDBR-aware).
- **Phase 7 — SEO finish (§7):** schema JSON-LD, sitemap, robots, canonical, GBP-SAB, Search Console.

### DEFINITION OF DONE (all gates must pass)

**🚫 HONESTY REVIEW gate (`scripts/honesty-grep.mjs`, runs in CI — build fails on any hit outside an allowlisted honest-negation context):**
- Grep the built output for banned strings (case-insensitive): `insur`, `\b911\b`, `emergency`, `SOS`, `guarantee`, `guaranteed`, `re-rout`, `reroute`, `turn-by-turn`, `turn by turn`, `cheaper than uber`, `cheaper than lyft`, `refer a friend`, `referral bonus`, `invite bonus`, `verified rider`, `car seat`, `\$1M`, `download now` (pre-launch).
- Allowlist only the **honest negations** (e.g. the FAQ "we don't have an SOS button… call 911"; "not yet in the App Store"). Any *positive claim* of a banned feature = **reject**.
- Manual review: no earnings number on driver pages; no competitor price anywhere; Checkr/insurance/appeal-SLA/fast-payout lines present **only if** their gate flag is true.

**♿ WCAG 2.2 AA gate:** axe-core + Lighthouse a11y = 0 violations / score 100; keyboard-only pass; contrast verified incl. coral; `prefers-reduced-motion` honored; forms labeled + error-announced.

**⚡ Performance/SEO gate:** Lighthouse Perf/SEO/Best-Practices ≥ 95 on mobile; CWV budget (§2) met; every page has unique title/meta/canonical + valid JSON-LD (schema validator clean); sitemap + robots correct; no publish/index of permit-gated or zero-supply pages.

**✅ Functional gate:** waitlist + driver-apply submit to the capture store (NOT `api/v1`) and fire analytics events; all CTAs route correctly; dark mode + theme toggle work; map hero degrades to static image with reduced-motion / no-JS.

---

## How to use this brief (to the future Claude session)

You have everything you need here to build the Vamos marketing site without prior context. **Start by reading `./florida-gtm-strategy.md` in full** — this brief references its sections (§) rather than repeating the rationale, and the strategy is the source of truth for every number, URL, and honesty caveat. Then work top-to-bottom: stand up the stack (§2) and design system (§6) first, build the homepage (§4), then the rider/driver/safety/pricing pages (§5), then the data-driven city/airport templates (§5d–e, §7). Use the **exact copy in §4 and §8** — it's approved Vamos voice, not placeholder. The single rule that overrides all others: **the honesty legend and the "NEVER CLAIM" list (§0) are non-negotiable — never let the site claim insurance, SOS/emergency response, referrals, live competitor pricing, or turn-by-turn/re-routing as shipped, and remember the app isn't in stores yet, so it's a waitlist, not "Download now."** The honesty grep, WCAG 2.2 AA, and CWV gates in §10 are what "done" means. When a fact might be stale (fares, driver payouts, airport fees, permits, vendor-keying status), verify against a primary source before it goes in published copy — only MCO's $7 airport fee is confirmed. Build it fair, build it honest, ship it green.
