import { Controller, Get, Req, Res } from '@nestjs/common';
import { Request, Response } from 'express';
import { cameViaPublicEdge } from '../public-edge';
import { MetricsService } from './metrics.service';

/**
 * Prometheus scrape endpoint. Excluded from the global /api/v1 prefix so it
 * lives at the conventional `/metrics`. Left unauthenticated for the scraper
 * (it runs on the internal network); put it behind the reverse proxy in prod.
 */
@Controller('metrics')
export class MetricsController {
  constructor(private readonly metrics: MetricsService) {}

  @Get()
  async scrape(@Req() req: Request, @Res() res: Response): Promise<void> {
    // Business numbers are not for the internet: through the public edge
    // this does not exist. Prometheus scrapes on the internal network.
    if (cameViaPublicEdge(req)) {
      res.status(404).send();
      return;
    }
    res.setHeader('Content-Type', this.metrics.registry.contentType);
    res.send(await this.metrics.scrape());
  }
}
