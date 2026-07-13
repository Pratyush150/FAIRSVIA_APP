/** Names of the BullMQ queues and their job types. */
export const QUEUE_DISPATCH = 'dispatch';
export const QUEUE_NOTIFICATIONS = 'notifications';

export const DISPATCH_JOB = 'run-dispatch';
export const NOTIFY_JOB = 'notify';

/** Shared default job options: retry a few times with backoff, auto-clean. */
export const DEFAULT_JOB_OPTS = {
  attempts: 3,
  backoff: { type: 'fixed' as const, delay: 2000 },
  removeOnComplete: true,
  removeOnFail: 100,
};
