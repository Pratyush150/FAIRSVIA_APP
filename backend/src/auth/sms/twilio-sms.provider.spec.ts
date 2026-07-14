import { createServer, IncomingMessage, Server } from 'http';
import { AddressInfo } from 'net';
import { TwilioSmsProvider } from './twilio-sms.provider';

interface Captured {
  method?: string;
  url?: string;
  auth?: string;
  contentType?: string;
  body?: string;
}

/** Start a throwaway HTTP server that records the request and replies with the
 *  given status/JSON. Returns its base URL + a getter for what it captured. */
async function mockServer(
  status: number,
  json: unknown,
): Promise<{ base: string; server: Server; captured: Captured }> {
  const captured: Captured = {};
  const server = createServer((req: IncomingMessage, res) => {
    captured.method = req.method;
    captured.url = req.url;
    captured.auth = req.headers.authorization;
    captured.contentType = req.headers['content-type'];
    let body = '';
    req.on('data', (c) => (body += c));
    req.on('end', () => {
      captured.body = body;
      res.writeHead(status, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(json));
    });
  });
  await new Promise<void>((r) => server.listen(0, '127.0.0.1', r));
  const { port } = server.address() as AddressInfo;
  return { base: `http://127.0.0.1:${port}`, server, captured };
}

describe('TwilioSmsProvider (real HTTP against a mock endpoint)', () => {
  const SID = 'AC_test_sid';
  const TOKEN = 'test_token';
  const FROM = '+13055550100';

  it('requires credentials', () => {
    expect(() => new TwilioSmsProvider('', TOKEN, FROM, 'http://x')).toThrow();
  });

  it('POSTs a correctly-formed, Basic-authed message to Twilio', async () => {
    const { base, server, captured } = await mockServer(201, {
      sid: 'SM123',
      status: 'queued',
    });
    try {
      const provider = new TwilioSmsProvider(SID, TOKEN, FROM, base);
      await provider.sendOtp('+13055559999', '123456');

      expect(captured.method).toBe('POST');
      expect(captured.url).toBe(`/2010-04-01/Accounts/${SID}/Messages.json`);
      expect(captured.contentType).toContain(
        'application/x-www-form-urlencoded',
      );
      const expectedAuth =
        'Basic ' + Buffer.from(`${SID}:${TOKEN}`).toString('base64');
      expect(captured.auth).toBe(expectedAuth);

      const form = new URLSearchParams(captured.body);
      expect(form.get('To')).toBe('+13055559999');
      expect(form.get('From')).toBe(FROM);
      expect(form.get('Body')).toContain('123456');
    } finally {
      server.close();
    }
  });

  it('raises a gateway error when Twilio rejects the request', async () => {
    const { base, server } = await mockServer(400, {
      code: 21211,
      message: 'Invalid To phone number',
    });
    try {
      const provider = new TwilioSmsProvider(SID, TOKEN, FROM, base);
      await expect(provider.sendOtp('+1', '123456')).rejects.toThrow(
        'Invalid To phone number',
      );
    } finally {
      server.close();
    }
  });
});
