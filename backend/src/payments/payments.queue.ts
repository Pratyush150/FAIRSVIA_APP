import { DEFAULT_JOB_OPTS } from '../common/queue/queue.constants';

/** BullMQ queue for durable payment settlement work (see PaymentsProcessor). */
export const QUEUE_PAYMENTS = 'payments';
export const CAPTURE_JOB = 'capture-trip';

export interface CaptureJobData {
  tripId: string;
}

/**
 * Capture retries: a card decline at completion is rarely transient, but a
 * gateway timeout / 5xx is — so retry with exponential backoff over ~10 min
 * before giving up (the last failure flips the trip to `payment_failed`).
 * captureForTrip is idempotent (captured/collected short-circuit), so a retry
 * after a half-applied attempt is safe.
 */
export const CAPTURE_JOB_OPTS = {
  ...DEFAULT_JOB_OPTS,
  attempts: 6,
  backoff: { type: 'exponential' as const, delay: 10_000 },
};
