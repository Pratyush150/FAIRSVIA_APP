import {
  Controller,
  Get,
  HttpCode,
  Param,
  ParseUUIDPipe,
  Post,
  Req,
  Res,
  UseGuards,
} from '@nestjs/common';
import type { Request, Response } from 'express';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { AuthUser } from '../auth/strategies/jwt.strategy';
import { ShareService, TOKEN_RE } from './share.service';
import { expiredPageHtml, trackPageHtml, TRACK_PAGE_CSP } from './track-page';

/** Origin of the incoming request as the client saw it. Behind the Cloudflare
 *  tunnel / nginx the Host is the public host and X-Forwarded-Proto says
 *  https. Only used when PUBLIC_BASE_URL is unset; a spoofed Host only
 *  changes the link in the caller's own response. */
export function requestOrigin(req: Request): string {
  const fwdProto = String(req.headers['x-forwarded-proto'] ?? '').split(',')[0].trim();
  const fwdHost = String(req.headers['x-forwarded-host'] ?? '').split(',')[0].trim();
  const proto = fwdProto || req.protocol || 'http';
  const host = fwdHost || req.get('host') || 'localhost';
  return `${proto}://${host}`;
}

/** Rider-only: mint the link for their active trip. */
@Controller('trips/:tripId/share-link')
@UseGuards(JwtAuthGuard)
export class ShareLinkController {
  constructor(private readonly share: ShareService) {}

  @Post()
  @HttpCode(201)
  async create(
    @CurrentUser() user: AuthUser,
    @Param('tripId', ParseUUIDPipe) tripId: string,
    @Req() req: Request,
  ) {
    const { url, expiresInSec } = await this.share.createLink(
      user.userId,
      tripId,
      requestOrigin(req),
    );
    return { url, expiresInSec };
  }
}

/** Public, no login. The page and its JSON feed share the /api/v1/public
 *  prefix, so the one tunnel URL serves both and the page can poll a
 *  same-origin relative path. */
@Controller('public')
export class PublicTrackController {
  constructor(private readonly share: ShareService) {}

  @Get('t/:token')
  async page(@Param('token') token: string, @Req() req: Request, @Res() res: Response) {
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('X-Robots-Tag', 'noindex, nofollow');
    res.setHeader('Content-Security-Policy', TRACK_PAGE_CSP);
    // OSM's tile servers want a Referer; send only our origin, never the
    // token-bearing path.
    res.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
    await this.share.rateLimit(TOKEN_RE.test(token) ? token : 'invalid', req.ip ?? 'unknown');
    const tripId = await this.share.resolve(token);
    if (!tripId) {
      res.status(404).send(expiredPageHtml());
      return;
    }
    res.status(200).send(trackPageHtml(token));
  }

  @Get('track/:token')
  async track(@Param('token') token: string, @Req() req: Request, @Res({ passthrough: true }) res: Response) {
    res.setHeader('Cache-Control', 'no-store');
    await this.share.rateLimit(TOKEN_RE.test(token) ? token : 'invalid', req.ip ?? 'unknown');
    return this.share.track(token);
  }
}
