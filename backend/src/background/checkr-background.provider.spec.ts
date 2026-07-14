import { createServer, IncomingMessage, Server } from 'http';
import { AddressInfo } from 'net';
import { CheckrBackgroundProvider } from './checkr-background.provider';

interface Hit {
  method?: string;
  url?: string;
  auth?: string;
  body?: string;
}

/** Mock Checkr: candidate → report (pending) → report becomes complete/clear. */
async function mockCheckr(reportResult = 'clear'): Promise<{
  base: string;
  server: Server;
  hits: Hit[];
}> {
  const hits: Hit[] = [];
  const server = createServer((req: IncomingMessage, res) => {
    let body = '';
    req.on('data', (c) => (body += c));
    req.on('end', () => {
      hits.push({
        method: req.method,
        url: req.url,
        auth: req.headers.authorization,
        body,
      });
      const send = (status: number, obj: unknown) => {
        res.writeHead(status, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(obj));
      };
      if (req.method === 'POST' && req.url === '/candidates') {
        return send(201, { id: 'cand_1' });
      }
      if (req.method === 'POST' && req.url === '/reports') {
        return send(201, { id: 'rep_1', status: 'pending' });
      }
      if (req.method === 'GET' && req.url === '/reports/rep_1') {
        return send(200, { id: 'rep_1', status: 'complete', result: reportResult });
      }
      send(404, { error: 'not found' });
    });
  });
  await new Promise<void>((r) => server.listen(0, '127.0.0.1', r));
  const { port } = server.address() as AddressInfo;
  return { base: `http://127.0.0.1:${port}`, server, hits };
}

describe('CheckrBackgroundProvider (real HTTP against a mock endpoint)', () => {
  const KEY = 'test_api_key';
  const PKG = 'driver_standard';

  it('requires an API key', () => {
    expect(() => new CheckrBackgroundProvider('', PKG, 'http://x')).toThrow();
  });

  it('runs candidate → report → poll with Basic auth and maps status', async () => {
    const { base, server, hits } = await mockCheckr('clear');
    try {
      const provider = new CheckrBackgroundProvider(KEY, PKG, base);

      const cand = await provider.createCandidate({
        firstName: 'Ada',
        lastName: 'Lovelace',
        email: 'ada@example.com',
        phone: '+13055559999',
      });
      expect(cand.candidateId).toBe('cand_1');

      const rep = await provider.createReport('cand_1');
      expect(rep).toEqual({ reportId: 'rep_1', status: 'pending' });

      const polled = await provider.getReport('rep_1');
      expect(polled.status).toBe('clear');

      // Basic auth = base64(apiKey + ':')
      const expectedAuth = 'Basic ' + Buffer.from(`${KEY}:`).toString('base64');
      expect(hits.every((h) => h.auth === expectedAuth)).toBe(true);
      // candidate body carries the applicant fields; report body the package.
      expect(new URLSearchParams(hits[0].body).get('first_name')).toBe('Ada');
      expect(new URLSearchParams(hits[1].body).get('package')).toBe(PKG);
    } finally {
      server.close();
    }
  });

  it('maps a non-clear complete report to "consider"', async () => {
    const { base, server } = await mockCheckr('consider');
    try {
      const provider = new CheckrBackgroundProvider(KEY, PKG, base);
      const polled = await provider.getReport('rep_1');
      expect(polled.status).toBe('consider');
    } finally {
      server.close();
    }
  });
});
