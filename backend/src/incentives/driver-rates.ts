/** The counts behind a driver's rates, over one window. */
export interface OfferCounts {
  accepted: number;
  declined: number;
  expired: number;
  /** Driver cancellations of accepted trips, EXCLUDING rider no-shows. */
  cancelled: number;
}

export interface DriverRates extends OfferCounts {
  /** accepted / (accepted + declined + expired); null with no offers yet. */
  acceptanceRate: number | null;
  /** cancelled / accepted; null with nothing accepted yet. */
  cancellationRate: number | null;
  /** Offers seen = accepted + declined + expired. */
  offers: number;
}

const round3 = (n: number) => Math.round(n * 1000) / 1000;

/**
 * Pure rate math. A no-show cancel is the rider's fault and is never counted
 * (the caller passes only true driver cancels). Rates are fractions 0..1.
 */
export function computeRates(c: OfferCounts): DriverRates {
  const offers = c.accepted + c.declined + c.expired;
  return {
    ...c,
    offers,
    acceptanceRate: offers > 0 ? round3(c.accepted / offers) : null,
    cancellationRate:
      c.accepted > 0 ? round3(Math.min(1, c.cancelled / c.accepted)) : null,
  };
}

/** Tally raw outcome rows into counts. `cancelled_no_show` is dropped. */
export function tally(outcomes: string[]): OfferCounts {
  const c: OfferCounts = { accepted: 0, declined: 0, expired: 0, cancelled: 0 };
  for (const o of outcomes) {
    if (o === 'accepted') c.accepted++;
    else if (o === 'declined') c.declined++;
    else if (o === 'expired') c.expired++;
    else if (o === 'cancelled') c.cancelled++;
  }
  return c;
}
