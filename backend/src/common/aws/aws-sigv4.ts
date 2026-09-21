import { createHash, createHmac } from 'node:crypto';

/** AWS region + IAM credentials shared by the SNS and SES providers. */
export interface AwsCreds {
  region: string;
  accessKeyId: string;
  secretAccessKey: string;
}

export interface SignedRequest {
  url: string;
  headers: Record<string, string>;
  body: string;
}

function hmac(key: Buffer | string, data: string): Buffer {
  return createHmac('sha256', key).update(data, 'utf8').digest();
}
function sha256Hex(data: string): string {
  return createHash('sha256').update(data, 'utf8').digest('hex');
}
/** AWS amz date `YYYYMMDDTHHMMSSZ` and the `YYYYMMDD` date stamp. */
function amzDate(d: Date): { amz: string; stamp: string } {
  const amz = d.toISOString().replace(/[:-]|\.\d{3}/g, '');
  return { amz, stamp: amz.slice(0, 8) };
}

/**
 * Sign an AWS request with Signature V4 and return the URL, headers and body
 * ready to hand to `fetch()`. No AWS SDK dependency — mirrors the hand-rolled
 * crypto style already used by the FCM provider. `service` is e.g. 'sns' or
 * 'ses'; the host is derived from it ('ses' → email.{region}.amazonaws.com).
 *
 * The `Host` header is intentionally NOT returned — Node's fetch sets it from
 * the URL to the identical value we signed over, so the signature still matches.
 */
export function signAwsRequest(opts: {
  creds: AwsCreds;
  service: string;
  method: string;
  path: string;
  body: string;
  contentType: string;
  now?: Date;
}): SignedRequest {
  const { creds, service, method, path, body, contentType } = opts;
  const host = `${service === 'ses' ? 'email' : service}.${creds.region}.amazonaws.com`;
  const { amz, stamp } = amzDate(opts.now ?? new Date());
  const payloadHash = sha256Hex(body);

  const canonicalHeaders =
    `content-type:${contentType}\n` + `host:${host}\n` + `x-amz-date:${amz}\n`;
  const signedHeaders = 'content-type;host;x-amz-date';
  const canonicalRequest = [
    method,
    path,
    '', // canonical query string (none — everything is in the body)
    canonicalHeaders,
    signedHeaders,
    payloadHash,
  ].join('\n');

  const scope = `${stamp}/${creds.region}/${service}/aws4_request`;
  const stringToSign = [
    'AWS4-HMAC-SHA256',
    amz,
    scope,
    sha256Hex(canonicalRequest),
  ].join('\n');

  const kDate = hmac('AWS4' + creds.secretAccessKey, stamp);
  const kRegion = hmac(kDate, creds.region);
  const kService = hmac(kRegion, service);
  const kSigning = hmac(kService, 'aws4_request');
  const signature = createHmac('sha256', kSigning)
    .update(stringToSign, 'utf8')
    .digest('hex');

  const authorization =
    `AWS4-HMAC-SHA256 Credential=${creds.accessKeyId}/${scope}, ` +
    `SignedHeaders=${signedHeaders}, Signature=${signature}`;

  return {
    url: `https://${host}${path}`,
    headers: {
      'Content-Type': contentType,
      'X-Amz-Date': amz,
      Authorization: authorization,
    },
    body,
  };
}
