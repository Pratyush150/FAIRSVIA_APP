import { Global, Module } from '@nestjs/common';
import { APP_INTERCEPTOR } from '@nestjs/core';
import { AuditInterceptor } from './audit.interceptor';

/**
 * Wires the audit interceptor globally. It self-selects to admin write routes,
 * so there is nothing to remember to annotate.
 */
@Global()
@Module({
  providers: [{ provide: APP_INTERCEPTOR, useClass: AuditInterceptor }],
})
export class AuditModule {}
