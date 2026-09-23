// e2e suites share Redis with a running dev server. Without their own queue
// namespace, a suite's workers picked up the dev server's live jobs (dispatch
// offer loops, payment retries) — acting on real data, and making app.close()
// wait on someone else's job past the teardown limit.
process.env.QUEUE_PREFIX = 'e2e';
