import {
  Controller,
  Headers,
  HttpCode,
  HttpStatus,
  Post,
  Req,
} from '@nestjs/common';
import { RawBodyRequest } from '@nestjs/common';
import type { Request } from 'express';
import { PaymentsService } from './payments.service';

/**
 * Stripe webhook receiver. Deliberately NOT behind the JWT guard — Stripe
 * authenticates by signing the payload; the signature is verified in the
 * service over the raw request bytes (main.ts enables rawBody).
 */
@Controller('payments/webhook')
export class WebhookController {
  constructor(private readonly payments: PaymentsService) {}

  @Post()
  @HttpCode(HttpStatus.OK)
  handle(
    @Req() req: RawBodyRequest<Request>,
    @Headers('stripe-signature') signature?: string,
  ) {
    // rawBody is the exact bytes Stripe signed; fall back to a re-serialize only
    // if the platform didn't capture it (it always should here).
    const raw = req.rawBody ?? Buffer.from(JSON.stringify(req.body ?? {}));
    return this.payments.handleWebhook(raw, signature);
  }
}
