# TLS / HTTPS

nginx terminates HTTPS for the production stack. Plain HTTP serves only the
Let's Encrypt challenge and 301-redirects everything else, so bearer tokens and
OTPs never cross the network unencrypted.

| Piece | Job |
|---|---|
| `certbot` service (`certbot-loop.sh`) | First boot: writes a 30-day self-signed placeholder so nginx can start. Then `certbot renew` every 12 h |
| `deploy-hook.sh` | After issue/renew, copies the live cert to the volume nginx reads |
| `nginx-start.sh` | Waits for a cert, starts nginx, reloads every 6 h to pick up renewals |
| `issue-cert.sh` | One-time: obtain the real certificate |

Policy: TLS 1.2 + 1.3 only, Mozilla "intermediate" ciphers, HSTS one year.
That satisfies iOS App Transport Security and Android's cleartext block.

## Going live — the one step that needs the domain owner

The only thing that cannot be automated from here is DNS, because it lives in
the owner's Cloudflare account:

1. In Cloudflare, add an **A record** for the API hostname (e.g.
   `api.ridevela.com`) → the production server's public IP. Set it to
   **DNS only (grey cloud)** for issuance.
2. On that server, in `infra/.env`: `TLS_DOMAIN=api.ridevela.com`,
   `HTTP_PORT=80`, `HTTPS_PORT=443`. Make sure ports 80 and 443 are open.
3. Start the stack, then:
   ```bash
   infra/tls/issue-cert.sh api.ridevela.com ops@ridevela.com --staging   # dry run
   infra/tls/issue-cert.sh api.ridevela.com ops@ridevela.com             # real
   ```
4. Build the apps against it:
   `--dart-define=API_BASE_URL=https://api.ridevela.com/api/v1`, and set the
   Stripe webhook endpoint to `https://api.ridevela.com/api/v1/payments/webhook`.

Renewal after that is automatic.

Note: the recorded API domain was `api.fairsvia.com`, but neither
`api.fairsvia.com` nor `api.ridevela.com` exists in DNS today, so nothing is
bound to the old name yet. Choosing the hostname is the owner's call.

## Verified (2026-09-23, real compose definitions, dev backend as upstream)

- HTTPS → backend `/health/ready`: 200 over HTTP/2
- HTTP → 301 to HTTPS; challenge path still served over HTTP
- TLS 1.2 and 1.3 negotiate; **TLS 1.1 refused by the server** (protocol alert)
- HSTS, nosniff, X-Frame-Options, Referrer-Policy each present exactly once
- `/metrics` blocked (404) at the edge; Socket.IO polling passes through
- Renewal hand-off: a new certificate went through `deploy-hook.sh`, nginx
  reloaded and served it with no restart

**Not verified:** an actual Let's Encrypt issuance. That can't happen until a
hostname resolves to the server.
