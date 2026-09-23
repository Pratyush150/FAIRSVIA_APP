// e2e suites share Redis with a running dev server. Without their own queue
// namespace, a suite's workers picked up the dev server's live jobs (dispatch
// offer loops, payment retries) — acting on real data, and making app.close()
// wait on someone else's job past the teardown limit.
process.env.QUEUE_PREFIX = 'e2e';

// e2e runs the mock payment provider, exactly as CI does (no key there). The
// dev container carries Stripe test keys, which otherwise sent every e2e card
// ride to Stripe's API — network-dependent, slow, and not what CI checks.
// Suites that need processor behaviour override PAYMENT_PROVIDER themselves.
process.env.STRIPE_SECRET_KEY = '';

// Market defaults, whatever the dev container's .env says (it may be set up
// for a pilot market): suites assert on dollar amounts and the default fee,
// exactly as CI runs them.
process.env.MARKET_CURRENCY = 'USD';
process.env.CANCELLATION_FEE = '5';
process.env.BUSINESS_TZ = 'Asia/Tashkent';

// The one demo number public-edge.e2e expects to be allowed a login code
// over the public edge.
process.env.OTP_PUBLIC_ECHO_PHONES = '+15550000001';
