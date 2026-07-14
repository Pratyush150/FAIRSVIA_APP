/** Names of the BullMQ queues and their job types. */
export const QUEUE_DISPATCH = 'dispatch';
export const QUEUE_NOTIFICATIONS = 'notifications';
export const QUEUE_SCHEDULED = 'scheduled';

export const DISPATCH_JOB = 'run-dispatch';
export const NOTIFY_JOB = 'notify';
export const PROMOTE_JOB = 'promote-scheduled';

/** Shared default job options: retry a few times with backoff, auto-clean. */
export const DEFAULT_JOB_OPTS = {
  attempts: 3,
  backoff: { type: 'fixed' as const, delay: 2000 },
  // Keep a bounded history so the monitoring dashboard can show throughput
  // (completed) and recent failures instead of everything vanishing at once.
  removeOnComplete: { age: 3600, count: 500 },
  removeOnFail: { age: 86400, count: 500 },
};
