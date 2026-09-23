import { Prisma } from '@prisma/client';

/**
 * True when a serializable transaction lost a race. Prisma reports it two
 * ways: P2034 from its own queries, and P2010 carrying Postgres SQLSTATE 40001
 * when the conflict happens inside a $queryRaw/$executeRaw. Checking only
 * P2034 lets the raw-SQL form escape as an unexpected 500.
 */
export function isSerializationFailure(e: unknown): boolean {
  if (!(e instanceof Prisma.PrismaClientKnownRequestError)) return false;
  if (e.code === 'P2034') return true;
  return e.code === 'P2010' && (e.meta as { code?: string } | undefined)?.code === '40001';
}
