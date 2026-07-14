export const BACKGROUND_CHECK_PROVIDER = 'BACKGROUND_CHECK_PROVIDER';

/**
 * Normalized background-check status used across the app, independent of any
 * one vendor's vocabulary:
 *  - none      — no check has been started
 *  - pending   — submitted, awaiting the vendor's result
 *  - clear     — passed (eligible to drive)
 *  - consider  — flagged for manual review (an admin decides)
 *  - suspended — the vendor paused the report (e.g. needs candidate action)
 */
export type BgcStatus = 'none' | 'pending' | 'clear' | 'consider' | 'suspended';

export interface CandidateInput {
  firstName: string;
  lastName: string;
  email: string;
  phone?: string;
}

/**
 * Abstraction over a driver background-check vendor (Checkr in production).
 * The concrete provider makes real HTTP calls; a mock stands in when no API key
 * is configured. Legally required for US TNC operation (FL Stat. §627.748).
 */
export interface BackgroundCheckProvider {
  /** Register the driver as a candidate; returns the vendor candidate id. */
  createCandidate(input: CandidateInput): Promise<{ candidateId: string }>;
  /** Order a report for a candidate; returns the report id + initial status. */
  createReport(
    candidateId: string,
  ): Promise<{ reportId: string; status: BgcStatus }>;
  /** Fetch the current status of a previously-ordered report. */
  getReport(reportId: string): Promise<{ status: BgcStatus }>;
}
