// Unit tests assert the default market (USD, the default fee, Tashkent days),
// exactly as CI runs them — whatever pilot market the dev container's .env
// is set up for.
process.env.MARKET_CURRENCY = 'USD';
process.env.CANCELLATION_FEE = '5';
process.env.BUSINESS_TZ = 'Asia/Tashkent';
