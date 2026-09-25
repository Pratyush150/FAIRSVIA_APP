# Driver app benchmark: Ola, Uber, Rapido, inDrive, Careem, Yandex Pro

**Written 2026-09-25.** The owner hasn't used the Ola driver app and asked us
to borrow the good ideas from the big driver apps. This page lists what
those apps give drivers, what RideVela's driver app has today (checked in
the code, not assumed), and what each gap is worth.

## How to read the competitor columns

- **Y**: confirmed from a source listed at the bottom, in this session.
- **Y\***: widely known, but not re-checked in this session.
- **N**: a source says the feature is missing.
- **?**: no public evidence found. That means we couldn't confirm it, not
  that the app lacks it.

**How strong the evidence is:**

- Uber and Careem: mostly official help pages.
- Ola, Rapido and inDrive: mostly Play Store listings and press.
- Yandex Pro: third-party blogs and driver forums, so treat those details as
  likely, not official.

The web research took about 15 minutes, so some "?" cells would probably
turn into Y with more digging.

## Matrix

| # | Feature | Uber | Ola | Rapido | inDrive | Careem | Yandex Pro | RideVela today (code) | Value / effort |
|---|---|---|---|---|---|---|---|---|---|
| 1 | **Earnings dashboard** (today/week, per-trip, online hours) | Y | Y | Y | ? | Y | Y | **Before:** today/week total, trip count and average per trip only (`DriverEarningsPage`). **Now:** online time, earnings per online hour, a 7-day bar chart, the trip list and cancellation-fee income. **Built in this pass.** | High / M |
| 2 | Acceptance / cancellation rate shown to the driver | Y | Y | ? | ? | ? | Y\* | No. Declines are recorded per trip in Redis for dispatch, but no rate is computed or shown. | Med / M |
| 3 | **Demand heatmap / busy areas** | Y (Guidance Heatmap) | ? | Y | ? | ? (third-party only) | Y | **Before:** no. Surge demand lived only in Redis for pricing, with a 5-minute TTL and an admin-only snapshot. **Now:** "busy areas" shading on the driver map from the last hour's ride requests. **Built in this pass.** | High / M |
| 4 | Destination / "go home" filter | Y (2 per day) | Y (GoTo) | ? | Y (the driver picks orders by destination) | ? | Y (Home, Errands, My District) | **Built.** Destination mode — see the note under the priorities list. | High / L (dispatch change) |
| 5 | **Request card**: pickup ETA/distance, trip distance, upfront fare, rider rating, accept countdown | Y | ? | Y | Y (plus the rider's offered price) | ? | ? | **Already there.** `OfferOverlay` has fare, surge label, the trip label (distance and time), approach ETA, rider name and rating, pickup and drop-off addresses, the pickup note, and a countdown ring that turns red at 5 s or less. Nothing to add. | — |
| 6 | Incentives / quests ("10 trips → ₹X") | Y (Quest, Boost) | Y | Y | ? | Y | Y | No. | High / L (rules engine, ledger, admin) |
| 7 | **Rider no-show wait timer + fee to driver** | Y (fee after 7 min on Economy) | ? | Y | N | Y (5–10 min) | ? | **Before:** the backend had `POST /trips/:id/driver-cancel` with no fee, and the driver app had no cancel at all. A driver whose rider never came out was stuck. **Now:** a countdown from arrival, then "Rider didn't show", which charges the rider the cancellation fee. **Built in this pass.** | High / S–M |
| 8 | Navigation hand-off (Google Maps / Waze) | Y | ? | ? | ? | ? | ? (built-in navigator) | **Already there.** A "Navigate" button on the en-route and on-trip sheets (`_LifecycleSheet._navigate`, `core/navigation`). | — |
| 9 | Break reminders / fatigue driving-hour limit | Y (12 h, then 6 h off) | ? | ? | ? | ? | Y (about 10–12 h) | **Built.** 12 h online, reset by a 6 h break (Uber rule) — see the note under the priorities list. | Med / S (now that online time exists) |
| 10 | Wallet / payout history / cash-out | Y (Instant Pay) | Y (daily cash-out) | Y\* | ? | Y (instant) | ? | **Already there.** `DriverPayoutsPage` has the balance, ledger history and withdraw, plus Stripe Connect. | — |
| 11 | Ratings & feedback | Y | Y | Y | ? | Y | Y | **Already there.** The driver rates the rider after each trip, and the driver's own rating shows on their Account profile card. | — |
| 12 | Safety (SOS, share trip, audio) | Y | Y | Y | Y | ? | ? | **Partly.** The driver has a safety sheet (`openDriverSafety`: emergency and SOS). Trip sharing is rider-side only. No audio recording. | Med / M |
| 13 | Document expiry reminders | ? | ? | ? | ? | ? | ? | No. `driver_profiles` has no expiry dates. | Med / M (needs a schema change) |
| 14 | In-app support | Y\* | Y | Y\* | Y | Y | Y\* | **Already there.** Support threads (`SupportPage`). | — |

## Notable ideas we are not taking now

- **Rapido and Ola: zero commission or a subscription instead of a
  commission.** Ola charges ₹67 a day. Rapido autos pay a ₹9–29 daily login
  fee. This is a business-model decision for the owner, not an app feature.
- **Ola Prime Plus Minimum Business Guarantee** (Bengaluru, 2023): a daily
  earnings floor. I found no program called "Ola Driver Guarantee"; this is
  the closest real one.
- **inDrive:** the rider proposes a fare and the driver counters. Its
  commission is about 10–13%, and 0% for the first 6 months in a new city.
- **Yandex Pro:** dispatch priority by rating and activity. "My District"
  mode charges a lower commission for trips within 4–5 km.
- **Uber:** gives drivers with ≥85% acceptance the upfront trip duration
  (Gold tier).

## What was built in this pass (2026-09-25)

### 1. Rider no-show wait and fee (item 7)

**Backend**

- `POST /trips/:id/driver-cancel` accepts `{noShow: true}`.
- It is allowed only when the trip is `arrived` and the server's `arrivedAt`
  is at least `NO_SHOW_WAIT_SEC` old. The default is 300 s, and an env
  override exists.
- Too early returns 400 `NO_SHOW_TOO_EARLY` with `secondsLeft`. Not arrived
  returns 400 `NO_SHOW_NOT_ARRIVED`.
- On success the rider is charged the same fee as a late rider cancel,
  `min(cancellationFee, fareEstimate)`, through the existing
  `chargeCancellationFee`. The driver gets their share.
- No fee is charged when the start code is locked, because the ride was
  blocked on the driver's side.
- The trip payload now carries `noShowWaitSec`.

**App**

- `NoShowTimer` sits on the "Confirm rider" sheet: a progress ring and an
  m:ss countdown from arrival.
- After the wait it shows "Rider didn't show" with the fee amount and a
  confirmation dialog.
- The cubit's `cancelNoShow()` handles the cancel. The server's echo of the
  driver's own cancel no longer shows "The rider cancelled".

### 2. Busy areas on the driver map (item 3)

**Backend** (`GET /drivers/me/demand?lat&lng`, drivers only)

- Counts ride requests from the last 60 minutes, whatever their outcome, on
  a 0.01° grid (about 1.1 km) within about 11 km of the driver.
- A cell with only one request is never returned, so no single rider's
  pickup is revealed.
- Returns at most 12 cells, each with an intensity from 0 to 1.
- Results are cached in Redis for 60 s per 5 km area.

**App**

- `AppMap.heatSpots`: each cell is drawn as two soft teal discs, a halo and
  a core. Opacity is capped at 0.22 so street names stay readable.
- Shown only while the driver is free (no trip, no offer).
- Refreshed at most every 2 minutes.
- The online sheet says "busy areas are shaded".

### 3. Earnings dashboard (item 1)

**Backend** (`GET /drivers/me/earnings`, fields added without breaking the
old ones)

- `onlineSeconds`: online time is now tracked in Redis. The session start is
  recorded on going online. On going offline (by the driver, or forced by the
  server) the time is credited per business day in the market time zone,
  split at local midnight.
- `days`: the last 7 business days, oldest first. The week range now means
  those 7 days, so the chart's bars add up to the total.
- `recentTrips`: up to 50 trips, with addresses, distance, amount earned,
  tip and cash/card.
- `cancellationFees`: cancellation-fee income included in the total.

**App** (`DriverEarningsPage` / `EarningsDashboard`)

- A hero total and three stats: trips, online time, and earnings per online
  hour (per trip when the driver was online under 10 minutes).
- A 7-day bar chart: one hue, today in ink, the other days in the soft tint,
  rounded tops, and a tooltip plus a semantics label on every bar.
- The trip list.
- The offline sheet has an "Earnings" shortcut.

### 4. Offer card (item 5)

Checked and already complete (see the matrix). No change.

## Next candidates, in order

1. **Fatigue limit.** Online time now exists. Warn at 10 h and block at 12 h
   within a rolling 24 h, as Uber does.
   **Built (2026-09-25).** Rule chosen: Uber's published one ("after 12 hours
   of driving, go offline for 6 hours"), i.e. NOT a rolling 24 h window:
   online time adds up across sessions and resets to zero only after one
   continuous offline break of `DRIVER_REST_BREAK_MIN` (default 360); short
   breaks do not reset it. At `DRIVER_MAX_ONLINE_HOURS` (default 12) dispatch
   stops offering the driver trips, the sweeper (every
   `DRIVER_FATIGUE_SWEEP_SEC`, default 30) takes them offline as soon as the
   current trip ends (`driver:status_changed {reason:'fatigue'}` +
   `driver:fatigue_locked` + push), and going online (REST or socket) is
   refused with 409 `DRIVER_REST_REQUIRED` `{restSecondsLeft, restUntil}`
   until the break is done. Warning `DRIVER_FATIGUE_WARN_MIN` (default 30)
   before the limit: `driver:fatigue_warning` + push, once per count. Soft
   `driver:break_reminder` every `DRIVER_BREAK_REMINDER_HOURS` (default 4) of
   one continuous session (non-blocking). Difference from Uber, stated
   plainly: we count ONLINE time (what we track), Uber counts on-trip +
   en-route time, so ours is stricter. State is Redis only
   (`driver:{id}:fatigue` hash, `drivers:fatigue:tracked` set); no migration.
   API: `GET /drivers/me/fatigue`. Code: `backend/src/drivers/fatigue/`, gate in
   `DriversService.setStatus` / `goOffline` and `DispatchService.sweep`. App:
   `apps/driver_app/lib/features/fatigue/fatigue_panel.dart` ("Online today:
   9h 40m of 12h", warning banner, rest card + `DriverRestPage` countdown).
   Sim: `tools/fake-driver-simulator/fatigue-check.mjs`.
2. **Destination mode.** Two uses a day: only offer trips whose drop-off
   brings the driver closer to a chosen point. This is a dispatch filter.
   **Built (2026-09-25).** Rule: while a destination is set, a trip is
   offered only if the pickup is inside the normal dispatch radius (the
   sweep's GEO ring, unchanged) AND
   `dist(dropoff, destination) ≤ 0.7 × dist(driver, destination)`
   (great-circle). Uses per day: `DESTINATION_MODE_USES_PER_DAY` (default 2,
   business day in the Tashkent calendar); moving an active destination does
   not use another and keeps the original clock. Auto-off within 500 m of the
   destination or 2 h after it was set (checked at match time and on GET;
   pushes `driver:destination_off`). State is Redis only
   (`driver:{id}:dest`, `driver:{id}:destUses:{day}`, `driver:{id}:destHome`).
   API: `GET|POST|DELETE /drivers/me/destination-mode` (POST `{lat,lng,label,saveAsHome?}`).
   Code: `backend/src/drivers/destination/`, filter call in
   `DispatchService.sweep`; app: `apps/driver_app/lib/features/driver/destination_mode.dart`.
   Sim: `tools/fake-driver-simulator/destination-mode.mjs`.
3. **Acceptance and cancellation rate** on the earnings page.
4. **Incentives / quests.**
5. **Document expiry reminders.** Needs a migration done the safe way: diff
   plus a transaction plus `migrate resolve`, never a shadow DB.

## Sources

- **Uber**
  - Upfront fares and the request card: https://help.uber.com/en/driving-and-delivering/article/upfront-fares?nodeId=bc83ed7e-6725-41de-afcb-72d263e5589f · https://www.ridester.com/uber-driver-app/
  - Destination filter: https://help.uber.com/en/driving-and-delivering/article/driver-destinations-on-uber?nodeId=2ed197fc-ec16-4f35-9ca0-cacb4ff3ce7a
  - Navigation: https://help.uber.com/en/driving-and-delivering/article/navigation-menu-faq?nodeId=36fdc048-9dc2-467d-ad11-669bdb073afb
  - Instant Pay: https://www.uber.com/us/en/drive/driver-app/instant-pay/
  - Audio recording: https://www.uber.com/us/en/ride/safety/audio-recording/
  - Driving limit: https://help.uber.com/driving-and-delivering/article/driving-time-limit?nodeId=a50a72e1-d315-4154-ac66-b17bd5bd050a
  - Cancellation and wait fees: https://help.uber.com/en/driving-and-delivering/article/request-cancellation-fee?nodeId=41fee0a6-8941-4418-bf25-3327db4f50aa · https://help.uber.com/en/driving-and-delivering/article/how-are-wait-time-fees-calculated?nodeId=7f41997f-a853-46ae-8001-8ab9dee504b0
  - Heatmap: https://www.uber.com/us/en/blog/enhancing-ubers-guidance-heatmap-with-deep-probabilistic-models/
  - Quest: https://help.uber.com/driving-and-delivering/article/earn-extra-with-quest?nodeId=3a43fa72-4fc2-42d0-bc1d-63c4c0bddb9d
- **Ola**
  - Driver app: https://play.google.com/store/apps/details?id=com.olacabs.oladriver
  - Zero commission: https://www.medianama.com/2025/06/223-ola-expands-zero-commission-model-to-cab-drivers/
  - Minimum Business Guarantee: https://inc42.com/features/ola-prime-plus-deeper-crisis-india-ride-hailing-market/
- **Rapido**
  - SaaS model: https://www.business-standard.com/companies/start-ups/after-cabs-rapido-extends-saas-based-zero-commission-model-to-auto-drivers-124021300846_1.html
  - Captain terms, including cancellation fees: https://www.rapido.bike/CaptainTerms
- **inDrive**
  - Model: https://en.wikipedia.org/wiki/InDrive
  - Safety: https://www.citizen.co.za/business/staying-safe-on-the-road-with-indrive-tools-every-driver-and-rider-should-know-about/ · https://www.itweb.co.za/article/indrive-strengthens-safety-with-audio-recording/GxwQD71D3dzvlPVo
  - Unpaid waits (user reviews, weak evidence): https://www.trustpilot.com/review/indrive.com
- **Careem**
  - Captain app: https://play.google.com/store/apps/details?id=com.careem.adma
  - Cancellation policy: https://help.careem.com/hc/en-us/articles/4410001043475-Cancellation-policy · https://www.careem.com/en-AE/captain-terms-rides/
  - Instant pay: https://www.zawya.com/en/press-release/companies-news/careem-partners-with-paysky-to-enable-instant-payments-for-captains-through-yalla-gvetg433
- **Yandex Pro**
  - App: https://play.google.com/store/apps/details?id=ru.yandex.taximeter
  - Modes: https://taxiflow.ru/kak-rabotayut-rezhimy-moy-rayon-po-delam-i-domoy/ (third party)
  - Fatigue limit: https://yandex.ru/q/article/rabotu_v_taksi_uzhe_ogranichivaiut_12_v_b14193c7/ (Yandex Q, not official)
