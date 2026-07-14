import { Global, Module } from '@nestjs/common';
import { PromoService } from './promo.service';
import { PromoController } from './promo.controller';
import { PromoAdminController } from './promo-admin.controller';

@Global()
@Module({
  controllers: [PromoController, PromoAdminController],
  providers: [PromoService],
  exports: [PromoService],
})
export class PromoModule {}
