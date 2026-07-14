import { BadGatewayException, Logger } from '@nestjs/common';
import {
  BackgroundCheckProvider,
  BgcStatus,
  CandidateInput,
} from './background-check.interface';

/**
 * Real Checkr provider via the REST API (no SDK dependency), matching the
 * hand-rolled `fetch` style of the other providers. Selected when CHECKR_API_KEY
 * is set. `baseUrl` defaults to the live Checkr host but is overridable
 * (CHECKR_API_BASE_URL) so the flow can be validated against a local mock
 * endpoint without real credentials.
 *
 * Checkr auth is HTTP Basic with the API key as the username and an empty
 * password. Candidate → report → poll report is the standard order flow.
 */
export class CheckrBackgroundProvider implements BackgroundCheckProvider {
  private readonly logger = new Logger('Checkr');

  constructor(
    private readonly apiKey: string,
    private readonly packageSlug: string,
    private readonly baseUrl: string,
  ) {
    if (!apiKey) throw new Error('CheckrBackgroundProvider requires CHECKR_API_KEY');
    this.logger.log(`Using Checkr background-check provider (${baseUrl})`);
  }

  async createCandidate(input: CandidateInput): Promise<{ candidateId: string }> {
    const data = await this.post('/candidates', {
      first_name: input.firstName,
      last_name: input.lastName,
      email: input.email,
      ...(input.phone ? { phone: input.phone } : {}),
    });
    return { candidateId: data.id as string };
  }

  async createReport(
    candidateId: string,
  ): Promise<{ reportId: string; status: BgcStatus }> {
    const data = await this.post('/reports', {
      candidate_id: candidateId,
      package: this.packageSlug,
    });
    return {
      reportId: data.id as string,
      status: this.normalize(data.status, data.result),
    };
  }

  async getReport(reportId: string): Promise<{ status: BgcStatus }> {
    const data = await this.get(`/reports/${reportId}`);
    return { status: this.normalize(data.status, data.result) };
  }

  /** Map Checkr's (status, result) pair onto our normalized BgcStatus. */
  private normalize(status?: string, result?: string): BgcStatus {
    if (status === 'suspended') return 'suspended';
    if (status === 'complete') {
      return result === 'clear' ? 'clear' : 'consider';
    }
    return 'pending';
  }

  private authHeader(): string {
    // API key as username, empty password.
    return `Basic ${Buffer.from(`${this.apiKey}:`).toString('base64')}`;
  }

  private async post(
    path: string,
    body: Record<string, string>,
  ): Promise<any> {
    return this.request('POST', path, body);
  }

  private async get(path: string): Promise<any> {
    return this.request('GET', path);
  }

  private async request(
    method: 'GET' | 'POST',
    path: string,
    body?: Record<string, string>,
  ): Promise<any> {
    let res: Response;
    try {
      res = await fetch(`${this.baseUrl}${path}`, {
        method,
        headers: {
          Authorization: this.authHeader(),
          ...(body
            ? { 'Content-Type': 'application/x-www-form-urlencoded' }
            : {}),
        },
        body: body ? new URLSearchParams(body).toString() : undefined,
      });
    } catch (e) {
      throw new BadGatewayException(`Checkr unreachable: ${(e as Error).message}`);
    }
    const data = await res.json().catch(() => ({}));
    if (!res.ok) {
      this.logger.error(`Checkr error (${res.status}): ${JSON.stringify(data.error ?? data)}`);
      throw new BadGatewayException(data.error ?? 'Checkr request failed');
    }
    return data;
  }
}
