/** Pure quest helpers, shared by the service and its tests. */

export interface QuestWindow {
  startsAt: Date;
  endsAt: Date;
  targetTrips: number;
}

/**
 * Does a trip completed at `at` count toward the quest? The window is
 * half-open, [startsAt, endsAt): a trip finished at exactly 11:00 does not
 * count toward a 7–11 quest, one at 10:59:59 does.
 */
export function inWindow(q: Pick<QuestWindow, 'startsAt' | 'endsAt'>, at: Date): boolean {
  return at.getTime() >= q.startsAt.getTime() && at.getTime() < q.endsAt.getTime();
}

/** Progress shown to the driver, capped at the target. */
export function questProgress(q: QuestWindow, completedInWindow: number) {
  const progress = Math.min(completedInWindow, q.targetTrips);
  return { progress, target: q.targetTrips, completed: completedInWindow >= q.targetTrips };
}
