import type { Request } from 'express';

/**
 * Did this request come in through the public edge (the Cloudflare tunnel or
 * CDN) rather than the internal network? Cloudflare stamps every request it
 * forwards with CF-Connecting-IP; a client on the internet cannot remove it,
 * so it marks public traffic reliably. (A client on the internal network
 * could add it — that only ever makes it treated MORE strictly.)
 */
export function cameViaPublicEdge(req: Pick<Request, 'headers'>): boolean {
  return typeof req.headers['cf-connecting-ip'] === 'string';
}
