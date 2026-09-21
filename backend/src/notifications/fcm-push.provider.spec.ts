import { generateKeyPairSync } from 'node:crypto';
import { FcmPushProvider } from './fcm-push.provider';
import { StalePushTokenError, isStalePushToken } from './push-provider.interface';

// A throwaway RSA keypair so the JWT actually signs (no real credentials).
const { privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
const pem = privateKey.export({ type: 'pkcs8', format: 'pem' }) as string;
const account = {
  projectId: 'proj',
  clientEmail: 'svc@proj.iam.gserviceaccount.com',
  privateKey: pem,
};

const realFetch = global.fetch;
afterEach(() => {
  global.fetch = realFetch;
  jest.restoreAllMocks();
});

describe('FcmPushProvider.parse', () => {
  it('extracts the three fields and normalises escaped newlines', () => {
    const json = JSON.stringify({
      project_id: 'p',
      client_email: 'e@x',
      private_key: 'line1\\nline2',
    });
    expect(FcmPushProvider.parse(json)).toEqual({
      projectId: 'p',
      clientEmail: 'e@x',
      privateKey: 'line1\nline2',
    });
  });

  it('returns null on invalid JSON or missing fields', () => {
    expect(FcmPushProvider.parse('not json')).toBeNull();
    expect(FcmPushProvider.parse('{}')).toBeNull();
    expect(FcmPushProvider.parse(JSON.stringify({ project_id: 'p' }))).toBeNull();
  });
});

describe('FcmPushProvider.send', () => {
  it('mints an OAuth token then POSTs to the HTTP v1 endpoint', async () => {
    const fetchMock = jest
      .fn()
      .mockResolvedValueOnce({
        ok: true,
        json: async () => ({ access_token: 'tok', expires_in: 3600 }),
      })
      .mockResolvedValueOnce({ ok: true, text: async () => '' });
    global.fetch = fetchMock as unknown as typeof fetch;

    const provider = new FcmPushProvider(account);
    await provider.send(
      { token: 'device-1', platform: 'android' },
      { title: 'Driver found', body: 'On the way', data: { tripId: 't1' } },
    );

    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(fetchMock.mock.calls[0][0]).toContain('oauth2.googleapis.com/token');

    const [sendUrl, sendOpts] = fetchMock.mock.calls[1];
    expect(sendUrl).toBe(
      'https://fcm.googleapis.com/v1/projects/proj/messages:send',
    );
    expect((sendOpts.headers as Record<string, string>).Authorization).toBe(
      'Bearer tok',
    );
    const body = JSON.parse(sendOpts.body as string);
    expect(body.message.token).toBe('device-1');
    expect(body.message.notification).toEqual({
      title: 'Driver found',
      body: 'On the way',
    });
    expect(body.message.data).toEqual({ tripId: 't1' });
  });

  it('caches the access token across sends (1 oauth + N sends)', async () => {
    const fetchMock = jest
      .fn()
      .mockResolvedValueOnce({
        ok: true,
        json: async () => ({ access_token: 'tok', expires_in: 3600 }),
      })
      .mockResolvedValue({ ok: true, text: async () => '' });
    global.fetch = fetchMock as unknown as typeof fetch;

    const provider = new FcmPushProvider(account);
    await provider.send({ token: 'a', platform: 'android' }, { title: 'x', body: 'y' });
    await provider.send({ token: 'b', platform: 'ios' }, { title: 'x', body: 'y' });

    expect(fetchMock).toHaveBeenCalledTimes(3); // token reused
  });

  it('throws when FCM rejects the message', async () => {
    global.fetch = jest
      .fn()
      .mockResolvedValueOnce({
        ok: true,
        json: async () => ({ access_token: 'tok', expires_in: 3600 }),
      })
      .mockResolvedValueOnce({
        ok: false,
        status: 404,
        text: async () => 'UNREGISTERED',
      }) as unknown as typeof fetch;

    const provider = new FcmPushProvider(account);
    const err = await provider
      .send({ token: 'stale', platform: 'android' }, { title: 'a', body: 'b' })
      .catch((e) => e);
    expect(err.message).toMatch(/FCM send failed \(404\)/);
    // A 404 / UNREGISTERED is a stale token: typed so the sender prunes it.
    expect(err).toBeInstanceOf(StalePushTokenError);
    expect(isStalePushToken(err)).toBe(true);
  });

  it('marks a 400 whose body says UNREGISTERED as stale, but not other errors', async () => {
    const mk = (status: number, body: string) =>
      jest
        .fn()
        .mockResolvedValueOnce({
          ok: true,
          json: async () => ({ access_token: 'tok', expires_in: 3600 }),
        })
        .mockResolvedValueOnce({ ok: false, status, text: async () => body }) as unknown as typeof fetch;

    global.fetch = mk(400, '{"error":{"details":[{"errorCode":"UNREGISTERED"}]}}');
    const stale = await new FcmPushProvider(account)
      .send({ token: 't', platform: 'android' }, { title: 'a', body: 'b' })
      .catch((e) => e);
    expect(isStalePushToken(stale)).toBe(true);

    global.fetch = mk(503, 'UNAVAILABLE');
    const transient = await new FcmPushProvider(account)
      .send({ token: 't', platform: 'android' }, { title: 'a', body: 'b' })
      .catch((e) => e);
    expect(isStalePushToken(transient)).toBe(false);
    expect(transient.message).toMatch(/\(503\)/);
  });
});
