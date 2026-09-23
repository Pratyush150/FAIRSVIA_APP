import { Logger } from '@nestjs/common';
import type { Worker } from 'bullmq';

const logger = new Logger('QueueDrain');

/** How long shutdown waits for in-flight jobs. Must stay under the
 *  orchestrator's stop grace period (Docker: 10 s) or the process is killed
 *  mid-drain anyway. */
export function drainMs(): number {
  const v = Number(process.env.SHUTDOWN_DRAIN_MS);
  return Number.isFinite(v) && v >= 0 ? v : 8000;
}

/**
 * Bounded graceful shutdown for a BullMQ worker. `worker.close()` alone waits
 * for every in-flight job — a dispatch offer loop can run for over a minute —
 * and once it has started, a later `close(true)` is ignored. So: stop taking
 * jobs and wait for the current ones up to `ms`, then close, forcing it if
 * time ran out. A forced job is picked up again by another replica as
 * stalled; every processor here is safe to re-run.
 */
export async function drainAndClose(worker: Worker | undefined, ms = drainMs()): Promise<void> {
  if (!worker) return;
  let timer: NodeJS.Timeout | undefined;
  const finished = await Promise.race([
    worker.pause().then(() => true, () => true),
    new Promise<boolean>((resolve) => {
      timer = setTimeout(() => resolve(false), ms);
    }),
  ]);
  if (timer) clearTimeout(timer);
  if (!finished) {
    logger.warn(
      `${worker.name}: jobs still running after ${ms} ms — closing anyway; ` +
        'they will be retried as stalled',
    );
  }
  await worker.close(!finished);
}
