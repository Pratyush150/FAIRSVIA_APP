/**
 * Competitor fare MODELS for the price-comparison feature.
 *
 * ── Honesty note (read this) ────────────────────────────────────────────────
 * Uber, Lyft, and Empower do NOT expose a public real-time pricing API:
 *   • Uber retired its public Price Estimates API in 2019 (partner-only since).
 *   • Lyft shut down its public developer API.
 *   • Empower is driver-owned (drivers set their own fares); it has no API.
 * Scraping their apps would violate their Terms of Service.
 *
 * So these are NOT live quotes. Each competitor price is *modeled* from that
 * company's PUBLISHED rate card (base + per-mile + per-minute + booking/service
 * fee + trip minimum) applied to the same distance/time we route for our own
 * trip. Every modeled quote is flagged `estimated: true` and the API response
 * carries a disclaimer, so a rider is never misled into thinking it's a live
 * Uber/Lyft price.
 *
 * These are approximations for the Miami / South-Florida market and are meant to
 * be tuned. When a real partner/live pricing integration becomes available it
 * can be dropped in behind the same {@link ProviderFareModel} shape (or the
 * service can call it instead of `compute`) without touching callers.
 *
 * Sources: each provider's public "how pricing works" / fare-estimate pages,
 * Miami market, sampled 2026-07. Treat as reference, not gospel.
 */

export interface ProviderFareModel {
  /** Stable machine id, e.g. 'uber'. */
  provider: string;
  /** Human label, e.g. 'Uber'. */
  displayName: string;
  /** The comparable product tier, e.g. 'UberX'. Shown for context. */
  productName: string;
  baseFare: number;
  perMile: number;
  /** Per-kilometre rate, for markets whose rate cards are published per km
   *  (Tashkent, Dubai). Added on top of perMile — a model sets one, the other 0. */
  perKm?: number;
  perMin: number;
  /** Booking / service fee added after the metered portion. */
  bookingFee: number;
  /** Trip minimum — the fare is floored at this. */
  minFare: number;
  /**
   * How strongly this provider's price reacts to demand relative to our own
   * surge multiplier. 1.0 = same as us; >1 = surges harder (Uber/Lyft
   * "primetime"); 0 = flat, ignores surge (Empower drivers set fixed prices).
   * Applied as: effectiveSurge = 1 + (ourSurge - 1) * surgeSensitivity.
   */
  surgeSensitivity: number;
  /** Multiplier on the metered fare (e.g. Rapido's zero-commission discount). Default 1. */
  fareFactor?: number;
  /** Regulatory cap / floor on the effective surge (Maharashtra: 1.5 / 0.75). */
  maxSurge?: number;
  minSurge?: number;
  /** Percentage convenience/platform fee on top of the fare (0.05 = 5%). */
  convenienceFeePct?: number;
  /** Night surcharge window, in the market's local time. endHour exclusive. */
  night?: { multiplier: number; startHour: number; endHour: number; timeZone: string };

  /** True once fitted from real samples (set by CalibrationService). */
  calibrated?: boolean;
  /** Mean abs % error of the last fit — drives the estimate's confidence band. */
  residualPct?: number;
}

/**
 * Standard economy-class comparison set (UberX / Lyft Standard / Empower).
 * Kept parallel to our own `economy` tier so the comparison is like-for-like.
 */
export const USD_COMPETITOR_MODELS: ProviderFareModel[] = [
  {
    provider: 'uber',
    displayName: 'Uber',
    productName: 'UberX',
    baseFare: 2.55,
    perMile: 1.15,
    perMin: 0.24,
    bookingFee: 2.9,
    minFare: 8.5,
    surgeSensitivity: 1.15,
  },
  {
    provider: 'lyft',
    displayName: 'Lyft',
    productName: 'Standard',
    baseFare: 1.9,
    perMile: 1.05,
    perMin: 0.22,
    bookingFee: 3.3,
    minFare: 7.5,
    surgeSensitivity: 1.1,
  },
  {
    provider: 'empower',
    displayName: 'Empower',
    productName: 'Standard',
    // Empower takes no per-ride commission (drivers pay a flat subscription),
    // so street prices trend lower and effectively flat (no surge engine).
    baseFare: 1.5,
    perMile: 0.95,
    perMin: 0.18,
    bookingFee: 0.0,
    minFare: 6.0,
    surgeSensitivity: 0.0,
  },
];

/*
 * ── Final market: Central Asia / Middle East ────────────────────────────────
 * Every number below was sampled 2026-09-26 from the sources named on each
 * model. None of these providers publishes a machine-readable rate card; some
 * publish none at all. Confidence is stated per model and is honest: only the
 * Dubai RTA taxi tariff is a public government tariff. Worked examples against
 * published trip estimates live in competitor-config.spec.ts.
 */

/**
 * Tashkent (UZS). Prices in whole so'm.
 *
 * inDrive is deliberately OMITTED: it is bid-based (the rider proposes a price,
 * drivers accept or counter) and publishes no rate card, so any "inDrive fare"
 * would be our own guess dressed as their price.
 */
export const UZS_COMPETITOR_MODELS: ProviderFareModel[] = [
  {
    // Source: https://taxi.yandex.uz/tashkent/tariff/ (official Yandex Go
    // Tashkent tariff page, entry "Start" — the economy class): minimum
    // "4600 so'm dan ko'p emas", city "2500 so'm/km", 2 min free waiting then
    // up to 650 so'm/min. Sampled 2026-09-26.
    // Cross-check: https://tourfixer.uz/en/blog/yandex-taxi-uzbekistan-guide-2026
    // (city-centre ~10 min ride 18,000–30,000 so'm; airport→Chorsu
    // 35,000–55,000 so'm).
    // Confidence: MEDIUM. Official minimum + per-km. The page publishes no
    // in-trip per-minute rate; with per-km alone the model came out ~20% under
    // the published trip ranges above, so perMin 250 so'm (UNPUBLISHED, set to
    // reach those ranges; below the 650 so'm/min waiting cap) stands in for
    // time-in-traffic and Yandex's unpublished demand pricing.
    provider: 'yandex',
    displayName: 'Yandex Go',
    productName: 'Start',
    baseFare: 4600,
    perMile: 0,
    perKm: 2500,
    perMin: 250,
    bookingFee: 0,
    minFare: 4600,
    surgeSensitivity: 1.1,
  },
  {
    // MyTaxi publishes no rider-side economy rate card we could find. The only
    // published per-km numbers are its courier tariff "Jo'natma" (12,000 so'm
    // including 1 km and 3 min waiting, then 1,300 so'm/km, 400 so'm/min
    // waiting) — Sources: https://kun.uz/20779770 and
    // https://drivers.mytaxi.uz/plans (driver-side plans; "from 24,000 so'm"
    // there is a driver plan price, NOT a rider fare). Sampled 2026-09-26.
    // Modeled as that same structure: 12,000 so'm covering the first km, then
    // 1,300 so'm/km.
    // Confidence: LOW. Proxy structure, not a published Economy card. Lands
    // within ~10% of the Yandex model on 5 km, cheaper on longer trips —
    // consistent with MyTaxi's positioning as the cheaper local app, but tune
    // with calibration samples before relying on it.
    provider: 'mytaxi',
    displayName: 'MyTaxi',
    productName: 'Economy',
    baseFare: 10700,
    perMile: 0,
    perKm: 1300,
    perMin: 0,
    bookingFee: 0,
    minFare: 12000,
    surgeSensitivity: 0.8,
  },
];

/** Dubai (AED). Prices to the fils (2 decimals). Salik tolls are NOT modeled. */
export const AED_COMPETITOR_MODELS: ProviderFareModel[] = [
  {
    // Dubai RTA metered taxi, street hail. Public government tariff.
    // Sources: https://www.propertyfinder.ae/blog/rta-dubai-taxi-fares/ ,
    // https://gulfchauffeur.com/guides/uae-taxi-fare-calculator (flag-fall
    // AED 5.00 day / 5.50 night, AED 12 minimum street hail, ~AED 2.19/km),
    // https://www.khaleejtimes.com/uae/transport/dubai-rta-new-taxi-fare-hike-minimum-charge-peak-hour-rates
    // (Nov 2025: app-booked minimum raised to AED 13). Sampled 2026-09-26.
    // Confidence: HIGH for structure/flag-fall/minimum; MEDIUM for per-km —
    // RTA indexes it to fuel prices and reviews it monthly (sources show
    // 1.97–2.47 across 2025–2026), 2.19 used. Waiting (AED 0.30–0.50/min when
    // stopped) is not modeled while moving → perMin 0. Taxis do not surge.
    provider: 'rta_taxi',
    displayName: 'Dubai Taxi',
    productName: 'Metered (RTA)',
    baseFare: 5,
    perMile: 0,
    perKm: 2.19,
    perMin: 0,
    bookingFee: 0,
    minFare: 12,
    surgeSensitivity: 0,
  },
  {
    // Careem Go (economy). Sources:
    // https://grabonuae.ae/blog/careem-vs-uber-vs-dubai-taxis/ (base AED 5,
    // AED 2.26/km, AED 13 app minimum; BurJuman→Dubai Mall ~15 min: Careem
    // AED 35–43 vs taxi ~AED 25), https://www.propertyfinder.ae/blog/rta-dubai-taxi-fares/
    // (Careem Comfort: start 5.4, 2.72/km). Sampled 2026-09-26.
    // Per-minute (0.50) and booking fee (2.00) are NOT published; they are set
    // so the model reaches the low end of the published BurJuman→Dubai Mall
    // range (per-km alone gives ~AED 25, below every observed Careem price).
    // Confidence: LOW-MEDIUM.
    provider: 'careem',
    displayName: 'Careem',
    productName: 'Go',
    baseFare: 5,
    perMile: 0,
    perKm: 2.26,
    perMin: 0.5,
    bookingFee: 2,
    minFare: 13,
    surgeSensitivity: 1.1,
  },
  {
    // Uber UberX Dubai. Source: https://grabonuae.ae/blog/careem-vs-uber-vs-dubai-taxis/
    // (base AED 5.00 day, AED 2.26/km, AED 0.50/min, booking fee AED 1.20,
    // minimum AED 15; BurJuman→Dubai Mall ~15 min: UberX AED 39–40). Uber
    // does not publish a Dubai rate card on uber.com; this is a third-party
    // compilation. Sampled 2026-09-26.
    // Confidence: LOW-MEDIUM. The model lands ~AED 34 for that trip, ~15%
    // under the reported price — Uber's upfront pricing adds route/demand
    // factors that a rate card cannot capture.
    provider: 'uber',
    displayName: 'Uber',
    productName: 'UberX',
    baseFare: 5,
    perMile: 0,
    perKm: 2.26,
    perMin: 0.5,
    bookingFee: 1.2,
    minFare: 15,
    surgeSensitivity: 1.15,
  },
];

/**
 * Pune (INR) — the live pilot. Research sampled 2026-09-26. What moves an
 * Uber / Ola / Rapido price in Pune beyond the RTA per-km rate:
 *
 *  1. RTA per-km rate (AC app cab): ₹25/km, fixed for Ola/Uber/Rapido from
 *     1 May 2025 (non-AC ₹21/km, not modeled — all three sell AC cars here).
 *     https://www.freepressjournal.in/pune/attention-punekars-check-out-ola-uber-rapido-cab-fares-per-kilometer-for-ac-and-non-ac-in-pune (8 May 2025)
 *     https://www.angelone.in/news/market-updates/ola-uber-rapido-to-charge-govt-approved-fares-in-pune-from-may-1
 *     Confidence HIGH (government tariff; compliance uneven — angelone.in 23 Jul 2025).
 *  2. Minimum fare covers the first 3 km (₹75). The May 2025 Pune notice said
 *     ₹37 for 1.5 km; the state Aggregator Policy (GR 20 May 2025, enforced
 *     Sept 2025) says rides under 3 km pay a minimum covering 3 km, and
 *     punenow.com reports "₹75 for the first 3 km". The later rule is used.
 *     https://www.punenow.com/new-government-approved-cab-fares-in-pune-ola-uber-and-rapido-implement-revised-rates/
 *     https://www.medianama.com/2025/05/223-maharashtra-aggregator-cabs-policy-2025/
 *     Confidence MEDIUM.
 *  3. Surge capped at 1.5x base; low-demand discounts capped at 25% below base.
 *     https://www.freepressjournal.in/mumbai/maharashtra-approves-cab-aggregator-policy-caps-surge-pricing-imposes-fines-for-cancellations
 *     https://thelogicalindian.com/maharashtras-2025-cab-policy-surge-pricing-capped-at-1-5x-%E2%82%B9100-driver-cancellation-fine-and-mandatory-safety-reforms/
 *     Confidence HIGH → `maxSurge: 1.5`, `minSurge: 0.75`. (The central MVAG
 *     2025 guideline allows up to 2x — greenevcabs.com, Jul 2026 — but the
 *     Maharashtra state cap is the binding one here.)
 *  4. Convenience fee capped at 5% per ride (angelone.in, above). Uber and Ola
 *     are modeled AT the cap (an upper bound; neither itemises its fee
 *     publicly) → `convenienceFeePct: 0.05`. Confidence LOW.
 *  5. Rapido: driver-subscription, zero-commission model; reported 10–15%
 *     cheaper rides for riders (motilaloswal.com, Jan 2025:
 *     https://www.motilaloswal.com/learning-centre/2025/1/the-rise-of-rapido-transforming-indias-cab-hailing-market).
 *     Modeled as `fareFactor: 0.9` (10% below the RTA base — inside the 25%
 *     discount cap) and no convenience fee. Confidence LOW-MEDIUM. Ola and
 *     Uber have moved to subscription models too (yourstory.com, Jun 2025),
 *     but no source shows their rider prices falling, so they stay at base.
 *  6. Night: Pune RTA meter tariff adds 25% between 00:00 and 05:00
 *     (metersahi.in/pune; applies to metered autos/taxis, to which the app-cab
 *     fare is pegged). cabspune.in claims app cabs carry no midnight
 *     surcharge — the sources CONFLICT. Modeled as 1.25x 00:00–05:00 IST for
 *     all three, confidence LOW.
 *  7. GST: 5% ride GST is inside the quoted fare → not added. Per-minute /
 *     ride-time: the RTA app-cab tariff has no time component → perMin 0.
 *     Pickup / dead mileage: not charged under the policy (except the 3 km
 *     minimum) → not modeled. Waiting charges apply only while stopped → not
 *     modeled for a moving trip.
 *  Ola vs Uber: no source shows a difference in Pune under the regulated
 *  tariff, so they are modeled IDENTICALLY — that is the honest result.
 *
 * Vehicle classes: Pune RTA publishes no separate app-cab rate for sedan /
 * SUV / luxury classes that we could find. The tier ratios below come from ONE
 * reported same-trip quote (x.com/arsh_goyal, Feb 2025: Uber Go ₹800, Premier
 * ₹1,100, XL ₹1,600 → 1.375x and 2.0x). Confidence LOW — calibrate with samples.
 * Premium: Uber Black was reintroduced in India (ackodrive.com, 2024) but its
 * Pune availability and price are NOT verified; the 2.5x ratio is an
 * UNSOURCED placeholder. Ola Luxe and a Rapido luxury product could not be
 * verified for Pune and are omitted.
 */
const PUNE_RTA_PER_KM = 25;
const PUNE_MIN_FARE = 75; // minimum covers 3 km × ₹25
const PUNE_NIGHT = { multiplier: 1.25, startHour: 0, endHour: 5, timeZone: 'Asia/Kolkata' };

function puneModel(
  provider: 'uber' | 'ola' | 'rapido',
  productName: string,
  classRatio: number,
): ProviderFareModel {
  const perProvider = {
    uber: { displayName: 'Uber', fareFactor: 1, convenienceFeePct: 0.05, surgeSensitivity: 1.0 },
    ola: { displayName: 'Ola', fareFactor: 1, convenienceFeePct: 0.05, surgeSensitivity: 1.0 },
    // surgeSensitivity 0.8 for Rapido is UNSOURCED (carried from the earlier
    // model): it reflects its smaller surge engine; capped at 1.5x regardless.
    rapido: { displayName: 'Rapido', fareFactor: 0.9, convenienceFeePct: 0, surgeSensitivity: 0.8 },
  }[provider];
  return {
    provider,
    displayName: perProvider.displayName,
    productName,
    baseFare: 0,
    perMile: 0,
    perKm: PUNE_RTA_PER_KM * classRatio,
    perMin: 0,
    bookingFee: 0,
    minFare: PUNE_MIN_FARE * classRatio * perProvider.fareFactor,
    surgeSensitivity: perProvider.surgeSensitivity,
    fareFactor: perProvider.fareFactor,
    convenienceFeePct: perProvider.convenienceFeePct,
    maxSurge: 1.5,
    minSurge: 0.75,
    night: PUNE_NIGHT,
  };
}

/** Pune competitor sets per our tier (see the note above for sources). */
export const INR_COMPETITOR_MODELS_BY_TIER: Record<string, ProviderFareModel[]> = {
  economy: [
    puneModel('uber', 'Uber Go', 1),
    puneModel('ola', 'Mini', 1),
    puneModel('rapido', 'Cab Economy', 1),
  ],
  comfort: [
    puneModel('uber', 'Premier', 1.375),
    puneModel('ola', 'Prime Sedan', 1.375),
    puneModel('rapido', 'Cab Premium', 1.375),
  ],
  xl: [
    puneModel('uber', 'Uber XL', 2),
    puneModel('ola', 'Prime SUV', 2),
    puneModel('rapido', 'Cab XL', 2),
  ],
  premium: [puneModel('uber', 'Uber Black', 2.5)],
};

/** Pune economy set (back-compat name). */
export const INR_COMPETITOR_MODELS: ProviderFareModel[] =
  INR_COMPETITOR_MODELS_BY_TIER.economy;

/**
 * Competitor sets keyed by the market currency (ISO 4217). A market with no
 * entry gets no comparison at all — deliberately: fares modeled in another
 * currency would claim savings that are not real.
 */
export const COMPETITOR_MODELS_BY_CURRENCY: Record<string, ProviderFareModel[]> = {
  USD: USD_COMPETITOR_MODELS,
  INR: INR_COMPETITOR_MODELS,
  UZS: UZS_COMPETITOR_MODELS,
  AED: AED_COMPETITOR_MODELS,
};

/**
 * Competitor sets keyed by currency AND our tier. Markets with only an
 * economy-class rate card (USD, UZS, AED) compare economy only; a tier with no
 * entry gets no comparison rather than a mismatched one.
 */
export const COMPETITOR_MODELS_BY_CURRENCY_AND_TIER: Record<
  string,
  Record<string, ProviderFareModel[]>
> = {
  USD: { economy: USD_COMPETITOR_MODELS },
  INR: INR_COMPETITOR_MODELS_BY_TIER,
  UZS: { economy: UZS_COMPETITOR_MODELS },
  AED: { economy: AED_COMPETITOR_MODELS },
};

/** Currencies with a comparison set. */
export const COMPARISON_CURRENCIES = Object.keys(COMPETITOR_MODELS_BY_CURRENCY);

/** The US set — the one the calibration table was seeded from. */
export const COMPETITOR_MODELS = USD_COMPETITOR_MODELS;
