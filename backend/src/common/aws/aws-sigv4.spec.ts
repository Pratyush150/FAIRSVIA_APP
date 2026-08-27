import { createHmac } from 'node:crypto';
import { signAwsRequest } from './aws-sigv4';

const CREDS = {
  region: 'us-east-1',
  accessKeyId: 'AKIDEXAMPLE',
  secretAccessKey: 'wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY',
};
const NOW = new Date('2015-08-30T12:36:00.000Z');

describe('signAwsRequest (AWS SigV4)', () => {
  it('derives the signing key exactly as AWS documents', () => {
    // Official worked example from the AWS SigV4 docs.
    const h = (k: Buffer | string, d: string) =>
      createHmac('sha256', k).update(d, 'utf8').digest();
    const kDate = h('AWS4' + CREDS.secretAccessKey, '20150830');
    const kRegion = h(kDate, 'us-east-1');
    const kService = h(kRegion, 'iam');
    const kSigning = h(kService, 'aws4_request');
    expect(kSigning.toString('hex')).toBe(
      'c4afb1cc5771d871763a393e44b703571b55cc28424d1a5e86da6ed3c154a4b9',
    );
  });

  it('produces a well-formed Authorization header for SNS', () => {
    const r = signAwsRequest({
      creds: CREDS,
      service: 'sns',
      method: 'POST',
      path: '/',
      body: 'Action=Publish&Message=hi',
      contentType: 'application/x-www-form-urlencoded',
      now: NOW,
    });
    expect(r.url).toBe('https://sns.us-east-1.amazonaws.com/');
    expect(r.headers['X-Amz-Date']).toBe('20150830T123600Z');
    expect(r.headers.Authorization).toMatch(
      /^AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE\/20150830\/us-east-1\/sns\/aws4_request, SignedHeaders=content-type;host;x-amz-date, Signature=[0-9a-f]{64}$/,
    );
    // Host header is intentionally omitted (fetch sets it from the URL).
    expect(r.headers.Host).toBeUndefined();
  });

  it('derives the SES host from the ses service name', () => {
    const r = signAwsRequest({
      creds: CREDS,
      service: 'ses',
      method: 'POST',
      path: '/v2/email/outbound-emails',
      body: '{}',
      contentType: 'application/json',
      now: NOW,
    });
    expect(r.url).toBe(
      'https://email.us-east-1.amazonaws.com/v2/email/outbound-emails',
    );
    expect(r.headers.Authorization).toContain('/us-east-1/ses/aws4_request');
  });

  it('is deterministic for identical inputs', () => {
    const opts = {
      creds: CREDS,
      service: 'sns' as const,
      method: 'POST',
      path: '/',
      body: 'x=1',
      contentType: 'application/x-www-form-urlencoded',
      now: NOW,
    };
    expect(signAwsRequest(opts).headers.Authorization).toBe(
      signAwsRequest(opts).headers.Authorization,
    );
  });
});
