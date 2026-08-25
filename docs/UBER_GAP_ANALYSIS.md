# RideVela vs Uber — Feature Gap Analysis

A page-by-page / capability-by-capability comparison of **RideVela** (this repo) against
the real **Uber** rider + driver + operations product. Purpose: a living checklist of
what's built, what's partial, and what's left — so we can prioritise UI and features
deliberately.

**Status legend**
- ✅ **Done** — fully functional end-to-end.
- 🟡 **Partial** — works but simplified vs Uber (noted).
- 🔌 **Off by default** — real implementation exists in the code but a mock/stub is
  injected unless an API key/env is set (flip a switch to go live).
- ❌ **Missing** — no support (UI and/or backend) at all.

> Method: derived from a full audit of `backend/src` (all 23 modules + Prisma schema)
> and the Flutter apps (`apps/rider_app`, `apps/driver_app`, `apps/admin_app`,
> `packages/core`). Last updated as of the map-fix commit (`2c62a66`).

---

## TL;DR — the shape of the gap

RideVela has a **genuinely complete core ride loop** — request → dynamic-tier fare +
surge → expanding-ring dispatch with re-sweep → live tracking with road-following
approach route → OTP start → odometer-metered fare → payment split → two-way rating +
tip → receipt — plus a real admin ops console. Architecturally it's production-shaped
(provider pattern: real Twilio/Stripe/Checkr/Google/OSM impls all exist, mocks injected
by default).

**What's left splits into three buckets:**

1. **Make it real (integrations that are mocked/absent).** Push notifications (❌ not
   wired), payouts to drivers (❌ no bank rails), email (❌ none), and flipping
   SMS/payments/maps/background-checks from mock → live. These block a real launch more
   than any screen does.
2. **Core parity gaps (UI + light backend).** Editable pickup, card selection at
   checkout, custom tip, rebook, share-trip **live link**, trusted contacts, driver SOS,
   driver onboarding documents, resend-OTP, name/email at signup, and surfacing existing
   admin endpoints (driver approval, promo, surge, fare) in the admin UI.
3. **Expansion products (net-new).** Pooling/shared rides, rider wallet (Uber Cash) &
   split fare, loyalty (Uber One), driver quests/heatmap, ride add-ons (pet/car-seat/WAV),
   business profiles, Reserve-premium, lost & found. All ❌ today.

---

# Part A — Rider journey (page by page)

## A1. Onboarding & Auth
| Uber has | RideVela | Notes / gap |
|---|---|---|
| Phone + SMS OTP | 🔌 | Flow ✅; **SMS is mocked** (Twilio impl exists, `SMS_PROVIDER=twilio` to enable). Dev code echoed on screen. |
| Name + email at signup | ❌ | Only phone captured at signup; name/email edited later in profile. |
| Profile photo | ❌ | No avatar upload (initials only). |
| Resend OTP w/ countdown | ❌ | No resend button/timer on the OTP screen. |
| Email / social / Apple login | ❌ | Phone-only. |
| Referral code at signup | ❌ | No referrals anywhere. |
| Rider vs driver signup path | 🟡 | Single app-per-role; role is backend-assigned, no in-app "become a driver". |

## A2. Home screen
| Uber has | RideVela | Notes / gap |
|---|---|---|
| Map + "Where to?" | ✅ | Real OSM tiles, draggable sheet, search pill. |
| Saved-place shortcuts (Home/Work) | ✅ | Quick-pick rows start a ride in one tap. |
| Recent destinations on home | 🟡 | Recents appear in search, not on the home card. |
| Product/suggestion shortcuts, promos banner | ❌ | No "ride again", promos carousel, or product tiles on home. |
| Nearby-driver dots + ETA on home | ❌ | No idle "cars near you" preview. |

## A3. Destination & pickup
| Uber has | RideVela | Notes / gap |
|---|---|---|
| Destination autocomplete | ✅ | Debounced backend Places (OSM Nominatim / Google). |
| Set location on map | ❌ | No "set pickup/drop on map" pin drag. |
| **Editable pickup** | ❌ | **Pickup is always current location** — cannot change it. High-value gap. |
| Pickup notes / instructions | ❌ | None. |
| Multi-stop | ✅ | Add/remove, **max 3**, re-estimates each change. |
| Saved places in search | ✅ | Full CRUD (Home/Work/custom). |
| Venue/airport pickup points | ❌ | No curated pickup zones. |

## A4. Product / ride selection
| Uber has | RideVela | Notes / gap |
|---|---|---|
| Multiple tiers w/ price + ETA + capacity | ✅ | economy/comfort/xl/premium, backend-driven, seats + "min away" + fare. |
| Upfront pricing + surge indicator | ✅ | Surge banner when multiplier > 1 (capped 2.0×). |
| Schedule / Reserve | 🟡 | Scheduled rides ✅ (5 min–30 days); no Reserve premium/guarantees/wait-time. |
| Promo applied to quote | ✅ | Server-priced, discount chip + net fare. |
| **Payment selection at checkout** | 🟡 | **Card/Cash toggle only** — cannot choose a specific saved card. |
| Ride for someone else | ❌ | No third-party rider. |
| Ride options / add-ons (Pet, Car seat, WAV, Assist) | ❌ | Fixed tiers, no add-ons. |
| Pool / shared ride tier | ❌ | Solo rides only; no rider-to-rider matching. |

## A5. Booking confirmation
| Uber has | RideVela | Notes / gap |
|---|---|---|
| Confirm pickup pin | ❌ | No confirm-pickup step (pickup fixed). |
| Driver notes / requirements | ❌ | None. |
| Confirm & request | ✅ | Creates trip (tier/promo/payment/schedule/stops). |

## A6. Matching / finding a driver
| Uber has | RideVela | Notes / gap |
|---|---|---|
| Finding-driver animation | ✅ | Custom pulse-radar. |
| Cancel while searching | ✅ | Backend cancel. |
| Expanding search / re-broadcast | ✅ | Expanding ring 3→9 km, **45 s re-sweep** on busy fleet, favourite-driver priority. |
| "No cars available" recovery | 🟡 | `no_drivers` event exists; rider-side retry/upsell UI is minimal (see task #69). |

## A7. Driver en route
| Uber has | RideVela | Notes / gap |
|---|---|---|
| Live driver tracking on map | ✅ | Marker + **road-following approach route** (driver→pickup), camera frames the leg. |
| ETA to pickup | 🟡 | "min away" shown on selection; no live-updating countdown card. |
| Driver card: name, rating, car, plate | ✅ | Name, rating, vehicle label, plate, avatar. |
| **Driver + car photo** | ❌ | No real photos (initials avatar). |
| In-app message | ✅ | Real chat (REST + socket). |
| **In-app call (masked number)** | ❌ | No calling. |
| **Share trip (live link)** | 🟡 | Safety sheet "share status" **copies text to clipboard** — not a live tracking link. |
| PIN / start verification | ✅ | 6-digit start OTP the rider shares with the driver. |
| Cancel w/ fee preview | 🟡 | Cancel ✅; fee is charged server-side (only after accept/arrive) but no explicit fee-preview UI. |

## A8. On trip
| Uber has | RideVela | Notes / gap |
|---|---|---|
| Live route + ETA | ✅ | Trip route drawn; driver position streamed. |
| Safety toolkit access | 🟡 | Shield → safety sheet (see A13). |
| Add stop / change destination mid-trip | ❌ | Stops are set pre-trip only. |
| Share trip status live | 🟡 | Clipboard copy only. |
| In-trip chat | ✅ | Yes. |

## A9. Trip completion
| Uber has | RideVela | Notes / gap |
|---|---|---|
| Fare breakdown + receipt | ✅ | Fare + tip + total; cash-due note; odometer-based final fare. |
| Rate driver (stars) | ✅ | 1–5, one per trip. |
| Compliments / feedback tags | 🟡 | Backend stores rating **tags**; no dedicated compliments UI. |
| **Tip** | 🟡 | **Fixed $2/$3/$5 only** — no custom amount, no tip-later. |
| Favourite the driver | ✅ | Toggle on completion. |
| **Report an issue / lost item** | 🟡 | Only via generic support tickets; no contextual "report on this trip" / lost-and-found flow. |
| **Rebook this trip** | ❌ | History is view-only → receipt; no one-tap rebook. |

## A10. Activity / history
| Uber has | RideVela | Notes / gap |
|---|---|---|
| Past trips list | ✅ | `/trips/history`, tap → receipt. |
| Receipt detail | ✅ | Fare breakdown, refund line, driver payout view. |
| Rebook / help on a past trip | ❌ | No rebook or per-trip help deep-link. |
| Email receipt | ❌ | No email system at all. |

## A11. Account & profile
| Uber has | RideVela | Notes / gap |
|---|---|---|
| Account hub | ✅ | Role-aware `AccountMenuPage`. |
| Edit profile | 🟡 | **Name + email only**; phone read-only; **no photo**, no emergency contacts. |
| Saved places | ✅ | Full CRUD. |
| Communication / privacy / language settings | ❌ | No settings screens; no i18n. |
| Manage devices / sessions | 🟡 | Device push token register/unregister exists (backend); no UI to manage sessions. |

## A12. Wallet & payments
| Uber has | RideVela | Notes / gap |
|---|---|---|
| Add/list cards | 🟡 🔌 | Add card is **brand + last-4 mock** (no real PAN/tokenization); Stripe impl exists but off. |
| Set default / delete card | ❌ | Neither. |
| Apple Pay / Google Pay / PayPal / Venmo | ❌ | None. |
| **Rider wallet / Uber Cash / gift cards** | ❌ | No stored balance for riders (only driver payout ledger). |
| **Split fare** | ❌ | `Payment` is single-payer; no split model. |
| Business / personal profiles | ❌ | Single profile. |
| Payment history | ✅ | Via trip receipts. |

## A13. Safety
| Uber has | RideVela | Notes / gap |
|---|---|---|
| Safety toolkit entry (rider) | 🟡 | Shield button → safety sheet. |
| Emergency 911/112 button | 🟡 | Emergency number **displayed**, not auto-dialled. |
| SOS to platform | ✅ | `POST /trips/:id/sos` logs an auditable event w/ lat/lng. |
| **Real emergency dispatch** | ❌ | Audit-only; no outbound to emergency services. |
| **Trusted contacts + auto-notify** | ❌ | No contacts list; no SMS/call-out (needs SMS). |
| **Live trip-share link** | ❌ | Clipboard text only, no shareable URL. |
| RideCheck / crash detection / audio recording | ❌ | None. |
| PIN verification | ✅ | Start OTP serves this role. |

## A14. Help & support
| Uber has | RideVela | Notes / gap |
|---|---|---|
| Support tickets + threads | ✅ | Create (6 categories), reply, status flow. |
| Help center articles / FAQ | ❌ | No knowledge base. |
| Contextual "help with this trip" | 🟡 | Only generic tickets; not trip-scoped. |
| Live chat with agent | 🟡 | Ticket threads only (async), no live agent chat. |

## A15. Promotions & loyalty
| Uber has | RideVela | Notes / gap |
|---|---|---|
| Promo codes | ✅ | Flat/percent, min-subtotal, global + per-user limits, race-safe redemption. |
| **Invite friends / referrals** | ❌ | None. |
| **Uber One / membership / rewards** | ❌ | Only one-off codes; no subscription/loyalty. |

## A16. Notifications
| Uber has | RideVela | Notes / gap |
|---|---|---|
| In-app inbox | ✅ | Persisted, unread badge, mark-read/all. |
| **Push (FCM/APNs)** | ❌ | **Mocked — no real provider wired** (falls back to mock even with a key). |
| Trip-milestone copy | ✅ | Canonical messages per state. |

---

# Part B — Driver journey

## B1. Onboarding / KYC
| Uber has | RideVela | Notes / gap |
|---|---|---|
| Vehicle details | 🟡 | Make, model, plate, tier (color optional, not in dialog). |
| **Document upload** (license, insurance, registration) | ❌ | No document UI. |
| **Background check** | 🔌 | Checkr impl exists; **mock + `DRIVER_AUTO_VERIFY` on by default** (auto-approves in dev). |
| Vehicle inspection | ❌ | None. |
| Profile photo | ❌ | None. |
| Bank / payout onboarding | ❌ | No Stripe Connect onboarding. |

## B2. Going online / earning mode
| Uber has | RideVela | Notes / gap |
|---|---|---|
| Go online/offline | ✅ | REST + socket, reconnect re-announce. |
| Online gate on verification | ✅ | Requires `docsVerified` (auto in dev). |
| **Demand heat-map** | ❌ | None. |
| **Destination filter / trip planner** | ❌ | None. |

## B3. Receiving & handling trips
| Uber has | RideVela | Notes / gap |
|---|---|---|
| Offer card w/ countdown | ✅ | Fare, miles, pickup, timer, haptics, auto-decline. |
| **Dropoff / rider rating on offer** | ❌ | Offer shows pickup + fare + distance only. |
| Accept / decline | ✅ | Socket. |
| Arrive → start (OTP) → complete | ✅ | Full lifecycle; cash-collect prompt. |
| Rate rider | ✅ | 1–5 on completion. |
| In-trip chat | ✅ | Yes. |

## B4. Navigation
| Uber has | RideVela | Notes / gap |
|---|---|---|
| Turn-by-turn / nav handoff (Google/Waze) | ❌ | No navigation; driver sees map only. |
| Mid-trip re-route / ETA | ❌ | None. |

## B5. Earnings & payouts
| Uber has | RideVela | Notes / gap |
|---|---|---|
| Earnings today/week | ✅ | Total, trips, avg/trip. |
| Payout ledger | ✅ | Signed entries (earning/tip/commission/withdrawal). |
| **Withdraw to bank / instant pay** | 🟡 | Withdraw action exists but **payout is mock** — records ledger entry, no real transfer/Connect. |
| Weekly statements / tax docs (1099) | ❌ | None. |

## B6. Incentives
| Uber has | RideVela | Notes / gap |
|---|---|---|
| **Quests / boosts / streaks** | ❌ | No driver incentive engine. |
| Surge zones for drivers | 🟡 | Surge engine exists (pricing) but no driver-facing heatmap. |

## B7. Ratings & account
| Uber has | RideVela | Notes / gap |
|---|---|---|
| Rating average | ✅ | Running avg. |
| Acceptance / cancellation rates | ❌ | Not tracked/shown. |
| Pro / tiers / rewards | ❌ | None. |

## B8. Driver safety & support
| Uber has | RideVela | Notes / gap |
|---|---|---|
| **Driver SOS / safety toolkit** | ❌ | **Driver has no safety button** (rider does). |
| Support tickets | ✅ | Shared support system. |

---

# Part C — Admin / operations console

Existing tabs (Flutter web): **Overview, Trips, Users, Drivers, Monitoring, Live, Support** — all functional (live tabs auto-refresh 6 s).

| Uber ops has | RideVela | Notes / gap |
|---|---|---|
| Headline metrics | ✅ | Users, drivers, online, active/completed trips, gross + platform revenue. |
| Trip management + refunds | ✅ | List + partial/full refund. |
| User management | ✅ | Search + activate/deactivate. |
| System monitoring | ✅ | HTTP throughput, queue health, trip funnel. |
| Live fleet map | 🟡 | Custom scatter (no real tiles, by design). |
| Support queue | ✅ | Threaded tickets, reply, status. |
| **Driver approval / KYC review** | 🟡 | **Backend endpoint exists** (`PATCH /admin/drivers/:id/verify`) but **Drivers tab is read-only** — not surfaced in UI. |
| **Promo management UI** | 🟡 | Backend CRUD exists (`/admin/promos`); **no admin UI**. |
| **Pricing / surge control UI** | 🟡 | Backend exists (`/admin/fares`, `/admin/surge`); **no admin UI**. |
| Zones / geofences / city config | ❌ | None. |
| User/driver drill-down detail | ❌ | List rows only. |
| Fraud / risk tooling | ❌ | None. |
| SOS/safety monitor | 🟡 | `GET /admin/safety` exists; no admin UI surface. |

> Note: several admin **backends are built but not yet exposed in the admin app** — a
> high-leverage, low-cost win (wire existing endpoints into new tabs).

---

# Part D — Platform / infrastructure (cross-cutting)

| Concern | Status | Detail |
|---|---|---|
| SMS / OTP | 🔌 | Mock default; **Twilio** real impl (`SMS_PROVIDER=twilio`). |
| Payments (charge/capture/refund) | 🔌 | Mock default; **Stripe** real impl (`STRIPE_SECRET_KEY`). |
| **Driver payouts** | ❌ | Mock only — **no Stripe Connect / bank rails** at all. |
| **Push notifications** | ❌ | Mock only — **FCM/APNs not implemented** (mock even when key set). |
| **Email** | ❌ | **No email system anywhere** (receipts, verification, etc.). |
| Maps / routing / places | ✅ 🔌 | Stub default; **OSM (OSRM+Nominatim) wired & running**, **Google** also available. |
| Background checks | 🔌 | Mock default; **Checkr** real impl (`CHECKR_API_KEY`). |
| Localization / i18n | ❌ | English only; no localization framework. |
| Accessibility (a11y) | 🟡 | Dark mode ✅; no dedicated a11y pass documented. |
| Deep links / universal links | ❌ | None (blocks share-trip links, notification tap-through). |
| iOS build | 🟡 | Code kept iOS-ready; **cannot be built on this Linux box** (needs macOS/Xcode). |

---

# Part E — Whole product lines not present

All ❌ — net-new if pursued:
- **Uber Pool / shared rides** (rider-to-rider matching).
- **Rider wallet (Uber Cash), gift cards, split fare.**
- **Uber One membership / loyalty / rewards.**
- **Uber Eats / courier / package / grocery.**
- **Rentals, Transit, Intercity, Hourly, Reserve-premium.**
- **Business / corporate profiles + expense reporting.**
- **Ride add-ons:** Pet, Car seat, WAV (wheelchair), Assist, quiet/temperature prefs.
- **Lost & found workflow.**
- **Fraud / risk scoring, airport queueing / geofenced dispatch.**

---

# Prioritised roadmap (suggested build order)

### Tier 1 — "Make it real" (unblocks a real pilot; mostly integration, not screens)
1. **Real push notifications (FCM/APNs)** — the one integration with *no* impl yet. High impact (trip alerts).
2. **Real payments** — flip Stripe on; add real card tokenization (Stripe PaymentSheet) + set-default/delete.
3. **Driver payouts** — Stripe Connect onboarding + real transfers (replaces mock withdrawal).
4. **Real SMS** — flip Twilio on; add **resend-OTP** button/timer.
5. **Email** — provider + email receipts / verification.
6. **Signup polish** — collect name/email at signup; profile photo.

### Tier 2 — Core parity (UI-led, backend mostly ready)
7. **Editable pickup** (drag pin / search pickup) + confirm-pickup step.
8. **Card selection at checkout** (choose saved card, not just card/cash).
9. **Custom tip amount** + tip-after-trip.
10. **Rebook** from history; **report issue / lost item** scoped to a trip.
11. **Share-trip live link** (needs deep links) + **trusted contacts** + **driver SOS**.
12. **Driver onboarding documents** UI (license/insurance/photo) wired to Checkr.
13. **Surface existing admin endpoints**: driver approval, promo, surge, fare-config tabs.
14. **In-app call** (masked) — provider-dependent.

### Tier 3 — Expansion (net-new products)
15. Rider **wallet (Uber Cash)** + **split fare**.
16. **Referrals / invite** + **loyalty (Uber One)**.
17. Driver **quests / boosts** + **demand heatmap**.
18. **Ride add-ons** (Pet/Car-seat/WAV) + ride-for-someone-else.
19. **Pooling / shared rides.**
20. **Business profiles**, Reserve-premium, zones/geofences, fraud tooling.

---

*This document is a snapshot; update it as features land. Each ✅/🟡/❌ maps to concrete
code paths audited in `backend/src` and the Flutter apps.*
