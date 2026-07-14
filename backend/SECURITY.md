# UberNav — Security Notes

A security review pass (D2) audited authentication/authorization, injection,
secrets/config/transport, and data exposure. The core authorization model was
found sound; the issues were configuration/hardening. This documents the posture
after the fixes and the responsibilities that remain with the operator.

## Verified sound (no changes needed)

- **Authorization.** Every `admin/*` controller stacks `JwtAuthGuard + RolesGuard`
  with `@Roles(admin)`; `RolesGuard` fails closed. Driver endpoints authorize by
  `userId` ownership + `docsVerified`, not the JWT role (a driver's token stays
  `role: 'rider'` after onboarding, which is not exploitable — no admin action is
  reachable, and `refresh()` re-reads the role from the DB).
- **IDOR.** Trips, payments, tips, payment methods, support tickets, chat,
  ratings, saved places, favorites, and the notification inbox all enforce
  owner-or-admin checks before read/write.
- **WebSocket authz.** Every handler derives identity from the JWT-verified
  `client.data.userId`, never from client-supplied ids; accept/decline route
  through an offeree check; chat/sync enforce trip participation.
- **Injection.** No SQL injection — the only raw query (promo redeem) uses a
  parameterized `Prisma.sql` template. No client-trusted monetary values (fares,
  discounts, payouts are all server-computed). No mass-assignment spreads.
- **Secrets in git.** Only `*.env*.example` placeholders are tracked; real
  `.env` / `.env.prod` / `infra/.env` are gitignored and untracked.
- **Refresh tokens** are stored as SHA-256 hashes and rotated on use; OTP codes
  are stored hashed (SHA-256) and generated with a CSPRNG.

## Fixed in this pass

- **Fail-fast prod config guard** (`common/config/configuration.ts`): the backend
  refuses to boot when `NODE_ENV=production` and any of — JWT secrets unset / the
  dev default / a `change_me` placeholder / <32 chars / equal to each other,
  `DATABASE_URL` unset, or `SMS_PROVIDER=mock`. This closes the "ships with a
  publicly-known signing key" and "mock SMS in prod" foot-guns.
- **OTP dev-code echo** is now gated on `mock provider + non-production` (config
  `otp.devEcho`) instead of `NODE_ENV !== 'production'`, so a forgotten
  `NODE_ENV` with a real provider can't leak codes; the mock SMS provider no
  longer logs the plaintext code outside dev.
- **OTP length default 6** (was 4) — 10^6 code space resists the ~25-guess/window
  the per-phone limiter allows.
- **CORS** reflects any origin only in dev; production requires an explicit
  `CORS_ORIGINS` allow-list.
- **Security headers** (`X-Content-Type-Options`, `X-Frame-Options`,
  `Referrer-Policy`, `X-DNS-Prefetch-Control`) added in-app, plus at nginx; the
  upstream-address debug header was removed and `/metrics` is 404'd at the edge.
- **WebSocket input validation**: `driver:location` / `driver:status` /
  `trip:accept|decline|sync|message` payloads are now validated DTOs (geographic
  and length bounds) via a gateway `ValidationPipe`.
- **Device-token IDOR**: `unregister` is scoped to the owning `userId`.
- **Error leakage**: client-facing `trip:payment_warning` / `trip:message_error`
  emit generic messages instead of `String(e)`.
- **Input hardening**: `@MaxLength` on trip addresses, promo code, and saved-place
  address.
- **Prod infra**: Postgres/Redis passwords are required from `infra/.env`
  (no hardcoded `ubernav:ubernav`), Redis requires a password, and CI runs
  `npm audit --audit-level=high`.

## Operator responsibilities before production

1. **Set strong secrets** in `backend/.env.prod` and `infra/.env` (the guards
   enforce this, but generate real random values: `openssl rand -base64 48`).
2. **Terminate TLS.** Enable the commented HTTPS block in `infra/nginx/nginx.conf`
   (or an upstream LB) so tokens/OTPs never travel in plaintext; add HSTS + the
   80→443 redirect.
3. **Configure a real SMS provider** (`SMS_PROVIDER` ≠ `mock`).
4. **Set `DRIVER_AUTO_VERIFY=false`** so drivers require document review.
5. **Restrict `/metrics`** to the monitoring network (already 404'd at nginx).

## Recommended follow-ups (not blocking, deliberately deferred)

- **Per-IP rate limiting** (`@nestjs/throttler`) on `/auth/*` and globally. Not
  added here because a global throttle would break the load-test harness; the
  per-phone OTP limiter + 6-digit codes mitigate the immediate brute-force risk.
- **Refresh-token reuse detection**: on presentation of an already-revoked (but
  known) refresh token, revoke the whole family; add an authenticated logout /
  revoke-all.
