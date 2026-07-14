import { Injectable, Logger } from '@nestjs/common';
import {
  BackgroundCheckProvider,
  BgcStatus,
  CandidateInput,
} from './background-check.interface';

/**
 * Dev/default background-check provider. No external calls: it mints ids and
 * returns a `pending` report that resolves to `clear` on the next poll, so the
 * onboarding → pending → clear flow is fully exercisable without a Checkr key.
 * A candidate whose email starts with `consider` resolves to `consider` instead,
 * to make the manual-review branch testable.
 */
@Injectable()
export class MockBackgroundProvider implements BackgroundCheckProvider {
  private readonly logger = new Logger('MockBGC');
  // reportId -> the status the next getReport() should return.
  private readonly outcomes = new Map<string, BgcStatus>();
  private seq = 0;

  async createCandidate(input: CandidateInput): Promise<{ candidateId: string }> {
    const candidateId = `mock_cand_${++this.seq}_${input.email
      .split('@')[0]
      .slice(0, 12)}`;
    this.logger.debug(`mock candidate ${candidateId}`);
    return { candidateId };
  }

  async createReport(
    candidateId: string,
  ): Promise<{ reportId: string; status: BgcStatus }> {
    const reportId = `mock_rep_${++this.seq}`;
    // Encode the eventual outcome from the candidate id for deterministic tests.
    const eventual: BgcStatus = candidateId.includes('consider')
      ? 'consider'
      : 'clear';
    this.outcomes.set(reportId, eventual);
    return { reportId, status: 'pending' };
  }

  async getReport(reportId: string): Promise<{ status: BgcStatus }> {
    return { status: this.outcomes.get(reportId) ?? 'pending' };
  }
}
