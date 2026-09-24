// Unit tests assert the default market (USD, the default fee, Tashkent days),
// exactly as CI runs them — whatever pilot market the dev container's .env
// is set up for.
process.env.MARKET_CURRENCY = 'USD';
// Auto / bike are hidden in the product for now (EXTRA_TIERS); suites keep
// exercising them so they stay ready to switch on.
process.env.EXTRA_TIERS = 'auto,bike';
process.env.CANCELLATION_FEE = '5';
process.env.BUSINESS_TZ = 'Asia/Tashkent';
