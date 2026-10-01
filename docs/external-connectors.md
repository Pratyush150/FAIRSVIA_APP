# External Connectors

Every third-party integration, its current state, and exactly what is needed to
switch it on. Audited 2026-09-18 against `backend/.env` and
`backend/src/common/config/configuration.ts`.

**Six vendors. Two are live. One is half-wired. Three are mocked.**

Every connector has a mock fallback, which is why the app runs fully offline and
why the load tests could measure real capacity without touching a vendor.
Provider selection is by config, so switching one on is a config change plus a
container **recreate** — not a code change.

> Env vars come from the compose `env_file` at container **create** time.
> `docker restart` will NOT pick up a changed key. Use:
> `docker compose -p infra up -d --force-recreate --no-deps backend`

---

## Status at a glance

| # | Vendor | Purpose | Module | State |
| --- | --- | --- | --- | --- |
| 1 | **Stripe** | Card payments, payouts | `payments/` | 🟡 Live, webhooks broken |
| 2 | **Google Maps** | Routing, ETA, geocoding | `geo/` | 🟢 Live |
| 3 | **Google FCM** | Push notifications | `notifications/` | 🔴 Mock |
| 4 | **AWS** | SNS (SMS) + SES (email) | `auth/sms/`, `email/` | 🔴 Mock (creds present) |
| 5 | **Twilio** | SMS (alternative to SNS) | `auth/sms/` | 🔴 Mock |
| 6 | **Checkr** | Driver background checks | `background/` | 🔴 Mock |

Twilio and AWS SNS are **alternatives**, selected by `SMS_PROVIDER`
(`twilio` | `sns` | `mock`). Only one will ever be used, so in practice this is
**five vendors**.

---

## 1. Stripe — 🟡 live, but half-wired

Charges work. **Webhooks do not.**

`STRIPE_WEBHOOK_SECRET` is absent, and `handleWebhook()` fails closed:

```ts
if (!secret) throw new BadRequestException('Stripe webhooks are not configured');
```

Good security posture — it does not silently skip verification — but it means
**every Stripe webhook is rejected**. Async events never reach the app:
`payment_intent.succeeded`, refunds settling, disputes, payout status.

Payments still capture synchronously, so this is invisible in testing and
becomes visible in production as payment records that never reach their final
state.

| Key | State |
| --- | --- |
| `STRIPE_SECRET_KEY` | SET (test) |
| `STRIPE_PUBLISHABLE_KEY` | SET (test) |
| `STRIPE_WEBHOOK_SECRET` | **absent — the gap** |
| `STRIPE_CONNECT_RETURN_URL` | defaults to `fairsvia-driver://connect/return` |
| `STRIPE_CONNECT_REFRESH_URL` | defaults to `fairsvia-driver://connect/refresh` |

**To finish:**
1. Create a webhook endpoint in the Stripe dashboard → `POST /api/v1/payments/webhook`
2. Copy the signing secret into `STRIPE_WEBHOOK_SECRET`
3. Recreate the container; confirm a test event is accepted
4. Note: the endpoint must be publicly reachable over **HTTPS** — blocked on TLS
5. Before going live: swap test keys for live keys, and verify the two Connect
   deep-link URLs match the shipped driver app scheme

---

## 2. Google Maps — 🟢 live

The only vendor fully working end to end.

| Key | State |
| --- | --- |
| `GOOGLE_MAPS_API_KEY` | SET |
| `OSRM_BASE_URL` | SET (fallback) |
| `NOMINATIM_BASE_URL` | SET (fallback) |

Provider precedence in `geo.module.ts`: **Google (if key) → self-hosted OSM →
stub**. With both configured it wraps Google in `FallbackGeoProvider`, so a
quota or outage degrades to local OSRM instead of failing.

**This was proven under load.** A test run produced **20,370
`OVER_QUERY_LIMIT`** errors against live Google and users saw **zero** errors —
every call fell back to OSRM.

**Open decisions (cost, not correctness):**
- Every estimate, route and address lookup is a billed call. At the measured
  ceiling (~1,200 rides/hour) quota and cost limits arrive well before the
  server's capacity does.
- Consider making **OSRM the default** and Google the premium path. The
  machinery already exists; it is a precedence decision.
- Set a billing alert and an API quota cap before launch.
- Restrict the key by API and referrer/IP — currently unrestricted as far as
  the backend is concerned.

---

## 3. Google FCM (push) — 🔴 mock — **release blocker**

Boot log confirms: `Using MOCK push provider (no FCM_SERVER_KEY set)`.

No "your driver is arriving" on **either** platform. This is P0 #3 in the iOS
audit and blocks both stores in practice.

| Key | State |
| --- | --- |
| `FCM_SERVICE_ACCOUNT_JSON` | absent — **this is the one to set** |
| `FCM_SERVER_KEY` | empty — legacy API, discontinued; do not use |

The code warns if you set `FCM_SERVER_KEY`: the legacy API is dead, use the
service account. `FcmPushProvider` already implements HTTP v1 with OAuth.

**To go live — Android:**
1. Firebase project → Service Accounts → generate a private key JSON
2. Put it in `FCM_SERVICE_ACCOUNT_JSON`
3. Recreate; boot log should read `Using FCM HTTP v1 push provider (project …)`

**To go live — iOS (additional):**
4. Apple Developer → create an **APNs auth key** (.p8), upload to Firebase
5. Add `GoogleService-Info.plist` to the iOS app
6. Add the `aps-environment` entitlement
7. Wire `firebase_messaging` client-side registration — **the backend token
   endpoint exists; the client side is not wired** (iOS audit P0 #3)

Steps 4–7 need a Mac and cannot be done or verified on this server.

---

## 4. AWS — SNS (SMS) + SES (email) — 🔴 mock, credentials already present

The odd one out: **credentials are set, the switches are off.**

| Key | State |
| --- | --- |
| `AWS_ACCESS_KEY_ID` | SET |
| `AWS_SECRET_ACCESS_KEY` | SET |
| `AWS_REGION` | `us-east-1` |
| `SES_FROM` | `noreply@fairsvia.com` |
| `SMS_PROVIDER` | `mock` ← flip to `sns` |
| `EMAIL_PROVIDER` | `mock` ← flip to `ses` |

There is a hand-rolled SigV4 signer at `common/aws/aws-sigv4.ts` used by both
`ses-email.provider.ts` and `sns-sms.provider.ts`.

**Cheapest win on this page** — no new credentials, two config values.

**Before flipping:**
- **SES starts in sandbox**: you can only send to verified addresses, and you
  must request production access (can take ~24h). Do this early.
- Verify the `fairsvia.com` domain in SES; add SPF/DKIM or mail lands in spam.
- **SNS SMS needs a spend limit raise** and, for US traffic, an origination
  number or toll-free registration — this has lead time and is a common
  launch surprise.
- Confirm the IAM user is scoped to `sns:Publish` and `ses:SendEmail` only.

Consequence today: **OTP codes are not actually delivered.** Fine in dev
(`devEcho` returns the code) — impossible in production.

---

## 5. Twilio — 🔴 mock — alternative to SNS

| Key | State |
| --- | --- |
| `TWILIO_ACCOUNT_SID` | absent |
| `TWILIO_AUTH_TOKEN` | absent |
| `TWILIO_FROM_NUMBER` | absent |

Provider exists (`twilio-sms.provider.ts`), selected by `SMS_PROVIDER=twilio`.

**Pick one: Twilio or SNS, not both.** Twilio is usually simpler to get
delivering (better onboarding, clearer deliverability); SNS is cheaper at
volume and you already hold AWS credentials. Given the credentials situation,
**SNS is the lower-friction path** — but Twilio is the safer choice if OTP
delivery rates matter more than cost.

---

## 6. Checkr — 🔴 mock — **likely a legal blocker**

| Key | State |
| --- | --- |
| `CHECKR_API_KEY` | absent |
| `CHECKR_PACKAGE` | defaults to `driver_standard` |

`background.module.ts` picks `CheckrBackgroundProvider` when the key is set,
otherwise the in-memory mock.

Background checks are typically a **regulatory requirement** for carrying
paying passengers. This is not a technical blocker — the integration is
written — it is a compliance and commercial one:

- Checkr requires a signed commercial agreement and account approval
- Lead time is measured in weeks, not days
- Confirm `driver_standard` is the right package for your jurisdiction
- Check `DRIVER_AUTO_VERIFY` (currently absent) is **not** enabled in prod, or
  drivers self-approve

**Start this first — it has the longest lead time of anything on this page.**

---

## Recommended order

| Order | Connector | Effort | Gated by |
| --- | --- | --- | --- |
| 1 | **Checkr** — begin commercial onboarding | days of waiting | external approval |
| 2 | **AWS SES production access** — request now | ~24h wait | external approval |
| 3 | **AWS SNS/SES** — flip the two switches | minutes | nothing |
| 4 | **FCM Android** — service account JSON | ~1 hour | Firebase access |
| 5 | **Stripe webhooks** — signing secret | ~30 min | needs public HTTPS |
| 6 | **Google Maps** — quota cap, billing alert, key restriction | ~1 hour | nothing |
| 7 | **FCM iOS** — APNs key, plist, entitlement, client wiring | ~half day | **needs a Mac** |
| 8 | **Stripe live keys** — swap test → live | ~30 min | launch readiness |

Items 1 and 2 are waiting on other people — **start them before anything else
on this list.** Item 3 is the cheapest real win.

---

## Verifying any of this

The admin API already has a live probe:

- `GET /api/v1/admin/diagnostics` — which vendors are real vs mock
- `GET /api/v1/admin/diagnostics/probe` — actually pings each configured API
  and reports OK or the exact error. Read-only: sends no SMS or email and
  charges nothing.

Use the probe after every change above. It is the fastest way to confirm a
connector is genuinely live rather than silently mocked.
