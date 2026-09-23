import { Module } from '@nestjs/common';
import { UsersService } from './users.service';
import { UsersController } from './users.controller';
import { AccountDeletionService } from './account-deletion.service';
import { DriversModule } from '../drivers/drivers.module';
import { LedgerModule } from '../ledger/ledger.module';

@Module({
  imports: [DriversModule, LedgerModule],
  controllers: [UsersController],
  providers: [UsersService, AccountDeletionService],
  exports: [UsersService],
})
export class UsersModule {}
