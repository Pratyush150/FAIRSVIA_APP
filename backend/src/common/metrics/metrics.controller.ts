import { Controller, Get, Res } from '@nestjs/common';
import { Response } from 'express';
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
  async scrape(@Res() res: Response): Promise<void> {
    res.setHeader('Content-Type', this.metrics.registry.contentType);
    res.send(await this.metrics.scrape());
  }
}
