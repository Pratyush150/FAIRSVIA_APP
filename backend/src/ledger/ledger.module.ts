import { Global, Module } from '@nestjs/common';
import { LedgerService } from './ledger.service';
import { LedgerController } from './ledger.controller';

@Global()
@Module({
  controllers: [LedgerController],
  providers: [LedgerService],
  exports: [LedgerService],
})
export class LedgerModule {}
