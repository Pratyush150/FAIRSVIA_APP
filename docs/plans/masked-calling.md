# Masked calling (number privacy) — plan

Status: **plan only, nothing built.** Written 2026-09-25. Pilot: Pune, prices in INR.
Every figure below is tagged **[verified: source N]** (read on the cited page on
2026-09-25) or **[assumed]** / **[unverified — quote needed]**. Sources are listed at the end.

## 0. Current state (checked in code, 2026-09-25)

The "Call" buttons dial the **other party's real mobile number**.

- Backend `backend/src/trips/trips.service.ts`:
  - `CONTACTABLE = [accepted, arrived, in_progress]` — numbers are only put in the
    trip payload in these statuses; history never re-exposes them.
  - Rider view: `driver.phone: CONTACTABLE.includes(trip.status) ? driver.phone : undefined`
    — the driver's real `users.phone`, commented "PILOT ONLY … production must use a
    masked/proxy number instead".
  - Driver view: `riderSnapshot()` returns `rider.phone` = the rider's real `users.phone`,
    only to the assigned driver, same "PILOT ONLY" comment.
  - Book-for-someone-else: `passengerPhone` (real number) is stored on the trip and
    returned to the booker (`passenger.phone`).
  - Admin (`backend/src/admin/admin.service.ts`) shows real rider/driver phones — fine
    for ops, but should be audited/role-gated.
- Apps: `apps/rider_app/lib/features/trip/sheets/live_ride_sheets.dart` (`DriverInfoSheet`)
  and `apps/driver_app/lib/features/driver/call_rider_button.dart` (`CallRiderButton`) call
  `dialPhone(phone)` → system dialler with a `tel:` URI (helper in
  `packages/core/lib/src/safety/safety_sheet.dart`). The dialler is injected, so swapping
  the number source needs no UI rewrite.
- There is in-app chat (`backend/src/chat`), which already keeps numbers private.

Consequence today: once a driver has called or been called, the rider's number sits in
the driver's call log forever (and vice versa). The time-window gate limits *API*
exposure, not the phone's own call history.

## 1. Why masking is needed

- **Safety / post-trip harassment.** A driver who has a woman rider's number can call or
  WhatsApp her after the ride; a rider can harass a driver. This is the main reason.
- **DPDP Act 2023 — data minimisation / purpose limitation.** Sharing a personal phone
  number with a stranger is more than the purpose ("coordinate pickup") needs; a masked
  number achieves the purpose with less data. [assumed — legal reading, not legal advice;
  confirm with counsel]
- **Off-platform deals.** Real numbers let drivers solicit "next time call me directly,
  cheaper" rides, which bypass fare, insurance and safety tracking.
- **Disputes.** A provider-bridged call gives a call log (who, when, duration) and,
  optionally, a recording — evidence for "driver asked for extra cash" / "rider never came".
- **Industry practice.** Uber is listed as an Exotel number-masking customer, alongside
  BluSmart, Swiggy, Zomato, Flipkart [verified: source 1]. That Ola/Rapido mask numbers is
  widely reported but **[unverified here]**.

## 2. Provider options (India)

| Provider | Masking model | India numbers / compliance | Price signals | Notes |
|---|---|---|---|---|
| **Exotel** | Virtual-number pool; caller dials the virtual number, Exotel asks your server (webhook) whom to connect, bridges both legs. "2 call-leg price" applies [verified: 1] | Indian company, data in India by default [verified: 3, a competitor's blog] | Contact sales for masking; generic plans ₹9,999 / ₹19,999 / ₹49,499 with credits, 1 credit = ₹1 [verified: 2]; per-minute ~₹0.50–1.50 outbound [verified: 3 — third-party estimate, not Exotel's own page] | Most common choice for Indian mobility; 15-day trial mentioned [verified: 1] |
| **Knowlarity** | Virtual-number calling via Knowlarity server [verified: search summary of 5; page itself failed TLS fetch] | Indian | Masking pricing **[unverified — quote needed]** (contact-centre plans from ₹1,999/agent/month are not the masking product) | Viable alternative quote |
| **Twilio** | Proxy API = purpose-built masking, but **Public Beta, no SLA** [verified: 4]; search snippets of Twilio docs say "Proxy Public Beta is currently closed for new customers… use Conversations and Programmable Voice" — the rendered page I fetched did not show that banner, so treat as **likely closed, confirm** | Indian numbers need extra regulatory docs; DLT handled by you [verified: 3] | Outbound ~₹3.50–5.00/min [verified: 3, third-party] | Most expensive; would mean building masking ourselves on Programmable Voice. Not recommended for India |
| **Plivo** | Build on Voice API (call bridge) | Domestic numbers need Certificate of Incorporation + GST [verified: 6] | Number rental ₹200/month [verified: 6]; ~₹0.75–1.50/min [verified: 3, third-party] | Good API, self-serve |
| **Edesy** (small self-serve reseller) | Two-way masking API + webhooks + recording | — | ₹1.50/min pay-as-you-go, no monthly fee; done-for-you setup from ₹14,999 [verified: 7] | Unclear if ₹1.50 is per leg or per call — **ask**. Small vendor; check reliability |
| MyOperator, Ozonetel, Servetel | Offer masking / click-to-call | Indian | **[unverified — not researched, quote needed]** | Get quotes for leverage |

Compliance notes (all **[assumed / verify with provider]**): Indian virtual numbers are
issued against company KYC (CoI, GST, PAN, authorised-signatory ID, address proof);
TRAI rules on recording disclosure and calling windows apply to commercial calling
[verified that the rules exist per source 3; applicability to rider↔driver transactional
calls to confirm]. DLT registration is for SMS templates, not needed for pure voice
bridging.

## 3. Design

### Two call styles
1. **Inbound to virtual number (recommended).** App shows/dials a virtual number (VN).
   Provider receives the call, webhooks us with `CallFrom` + `CallTo(VN)`, we answer
   with the other party's real number, provider bridges. Works from any dialler.
2. **Click-to-call bridge.** App hits our API; we ask the provider to call party A, then
   B, and join. No number shown at all, but slower to connect and costs both legs as
   outbound. Keep as fallback / for "call back" flows.

### Sequence (inbound-to-VN)

```mermaid
sequenceDiagram
  participant D as Driver app
  participant API as Backend (calling module)
  participant R as Redis
  participant P as Provider (Exotel)
  participant Rider as Rider phone
  Note over API: trip -> accepted
  API->>R: SET mask:{vn}:{driverPhone} = riderPhone (TTL)<br/>SET mask:{vn}:{riderPhone} = driverPhone (TTL)
  D->>API: GET /trips/:id  (payload carries callNumber = vn, never real phone)
  D->>P: dials vn
  P->>API: webhook: from=driverPhone, to=vn (signed)
  API->>R: GET mask:{vn}:{driverPhone}
  API-->>P: connect to riderPhone
  P->>Rider: rings; caller ID shows vn
  P->>API: status webhook (duration, legs, recording url?)
  API->>API: INSERT call_logs (Postgres)
  Note over API: trip ends -> EXPIRE keys to now + N min
```

### Pool sizing
Mapping key is `(vn, caller real number)`, not `vn` alone, so one VN serves many
concurrent trips as long as no single person has two active sessions on the same VN.
Each user has at most one live trip, so the pilot could technically run on **1–2 VNs**.
Recommend **5 for the pilot** [assumed] so a VN can be rotated if it gets spam-flagged,
and so a per-trip VN rotation stops a driver from reusing one VN to reach a past rider.
Scale rule of thumb [assumed]: pool ≥ max(peak concurrent trips ÷ 50, 5); revisit on data.

### Backend sketch — `backend/src/calling/` (new NestJS module)
- `calling.module.ts`, `calling.service.ts` — `openSession(tripId)`, `closeSession(tripId, ttlMin)`,
  `resolve(vn, from)`. Called from trips on status transitions (accepted → open;
  completed/cancelled → close with TTL).
- `providers/` — `MaskingProvider` interface (`allocate`, `verifyWebhook`, `bridge`) with
  `ExotelProvider` and a `FakeMaskingProvider` for tests + the fake-driver simulator
  (same pattern as `auth/sms` providers).
- `calling.controller.ts` — provider webhooks (`/calling/webhook/connect`,
  `/calling/webhook/status`), signature/IP-allowlist verified, rate-limited, no auth guard.
- **Redis** (hot, ephemeral): `mask:{vn}:{from}` → target, `mask:trip:{tripId}` → vn; TTL =
  trip-end + N min. Never Postgres for the hot lookup (matches repo rule).
- **Postgres** (durable): `call_logs(id, trip_id, caller_role, vn, started_at, duration_s,
  status, provider_call_id, recording_url?)` — **store no raw phone numbers here**
  (roles + trip id are enough; numbers live on `users`).
- Trips payload: replace `driver.phone` / `rider.phone` with `callNumber` (VN) when
  `CALL_MASKING=on`; keep today's real-number path behind the flag for the pilot.
- Apps: `dialPhone(callNumber)` — only the field name changes; add "Calls are routed via
  RideVela and may be recorded" copy if recording is on.

### Failure / fallback
- Provider down or webhook times out (target < 2 s [assumed]): the call fails. Fallbacks,
  in order: in-app chat (already private); click-to-call via a secondary provider; for
  **SOS** always the real emergency path (112 / support), never through masking.
- **Do not** silently fall back to exposing real numbers — that defeats the point. If
  the owner wants it as an emergency override, make it explicit and logged.
- Unknown caller (called from a different SIM / withheld CLI): play "call from your
  registered number" and hang up; log it.
- Post-TTL call to a VN: play "this trip has ended, contact support".

## 4. Cost ballpark (INR)

Assumptions **[assumed]**: 40% of rides have one call; average 1.5 min talk; 60-second
pulse ⇒ billed **2 min per leg**; masking = **2 legs** per call. So per 1,000 rides:
400 calls × 2 legs × 2 min = **1,600 leg-minutes**.

| Rides / month | Leg-min | Exotel @ ₹0.50–1.50/leg-min [3] | Edesy @ ₹1.50/min [7] (per call-min ↔ per leg-min) | Twilio @ ₹3.50–5.00 [3] |
|---|---|---|---|---|
| 1,000 | 1,600 | ₹800 – ₹2,400 | ₹1,200 – ₹2,400 | ₹5,600 – ₹8,000 |
| 10,000 | 16,000 | ₹8,000 – ₹24,000 | ₹12,000 – ₹24,000 | ₹56,000 – ₹80,000 |

Plus fixed costs:
- Numbers: 5 VNs × ₹200 = ₹1,000/month at Plivo's listed rental [verified: 6]; Exotel VN
  rental **[unverified — quote needed]**.
- Exotel platform: its listed plans (₹9,999 for 5 months, ₹19,999 for 11 months, etc.,
  with a stated "rental") are the business-phone product; the masking package is
  "contact sales" [verified: 1, 2]. Budget **₹2,000–5,000/month fixed [assumed]** until quoted.
- Recording storage: small; provider-hosted in most plans [assumed].

Order of magnitude: **~₹2–7k/month at 1k rides, ~₹10–30k/month at 10k rides** with an
Indian provider — about ₹1.5–3 per ride. All per-minute rates above are a third-party
blog's estimates (source 3 is itself a competitor, Edesy); get written quotes.

## 5. Owner decisions needed

1. **Provider**: shortlist Exotel (default) + one of Knowlarity / Plivo for a quote.
   Twilio not recommended (Proxy beta/closed, highest India rates).
2. **Pool size**: 5 VNs for pilot? Rotate per trip?
3. **Recording**: yes/no. If yes: consent line in Terms + in-call announcement, retention
   period (e.g. 30 days), who can listen (support role only), DPDP notice update.
4. **Mapping TTL** after trip end: e.g. 30 min (lost items) vs 24 h (support). Longer =
   more harassment window.
5. **Budget** ceiling per month and per ride.
6. **KYC docs** for Indian virtual numbers: Certificate of Incorporation, GST (Plivo
   requires both [verified: 6]); likely also PAN, signatory ID, address proof, and possibly
   a letter of authorisation **[assumed]**. Note memory says launch market may move to
   Uzbekistan — masking providers above are India-only; decide which market first.
7. **Chat first?** Keep in-app chat as the primary contact and calls as secondary, or
   hide the call button until the driver is within N metres?
8. Fallback policy: is exposing real numbers ever allowed (no, recommended)?
9. Scope: also mask `passengerPhone` (book-for-someone-else) — recommended yes.

## Sources (fetched 2026-09-25)

1. Exotel — Number masking use case: https://exotel.com/use-cases/number-masking/
2. Exotel — Pricing (business phone system): https://exotel.com/pricing/business-phone-system/
3. Edesy blog — Twilio vs Exotel India 2026 cost comparison (third-party, competitor):
   https://edesy.in/blog/twilio-vs-exotel-india-cost-comparison-2026
4. Twilio — Proxy docs: https://www.twilio.com/docs/proxy and https://www.twilio.com/docs/proxy/api
   ("closed for new customers" seen only in search-result snippets of Twilio docs pages, e.g.
   https://www.twilio.com/docs/proxy/proxy-changelog — not confirmed on the rendered page)
5. Knowlarity — Number masking: https://www.knowlarity.com/voice/number-masking (page fetch
   failed with a TLS error; content from search summary only)
6. Plivo — India phone number pricing: https://www.plivo.com/virtual-phone-numbers/pricing/in/
7. Edesy — Number masking API pricing: https://edesy.in/number-masking
