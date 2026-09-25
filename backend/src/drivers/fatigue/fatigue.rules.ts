/**
 * Driver fatigue limit (docs/plans/driver-app-benchmark.md, item 9). Pure
 * rules + env readers, so they unit-test without Redis.
 *
 * FATIGUE — the Uber rule ("after 12 hours of driving, go offline for 6
 * hours"): online time accumulates across sessions and resets to zero only
 * after one continuous offline break of at least DRIVER_REST_BREAK_MIN
 * (default 360 min). Short breaks do NOT reset it. Once the accumulated time
 * reaches DRIVER_MAX_ONLINE_HOURS (default 12) the driver gets no new offers,
 * is taken offline as soon as the current trip ends, and cannot go online
 * again until the break is done. We count ONLINE time (what we track), which
 * is stricter than Uber's on-trip + en-route "driving time". A warning goes
 * out DRIVER_FATIGUE_WARN_MIN (default 30) before the limit, and a soft
 * "take a short break" reminder every DRIVER_BREAK_REMINDER_HOURS (default 4)
 * of one continuous session.
 */

function num(raw: string | undefined, def: number, min: number, max: number): number {
  const n = Number(raw);
  if (raw === undefined || raw === '' || !Number.isFinite(n)) return def;
  return Math.min(max, Math.max(min, n));
}

export const fatigueConfig = {
  maxOnlineSecs: () => Math.round(num(process.env.DRIVER_MAX_ONLINE_HOURS, 12, 0.01, 24) * 3600),
  restBreakSecs: () => Math.round(num(process.env.DRIVER_REST_BREAK_MIN, 360, 1, 24 * 60) * 60),
  warnBeforeSecs: () => Math.round(num(process.env.DRIVER_FATIGUE_WARN_MIN, 30, 0, 240) * 60),
  reminderEverySecs: () =>
    Math.round(num(process.env.DRIVER_BREAK_REMINDER_HOURS, 4, 0.01, 24) * 3600),
  sweepEveryMs: () => Math.round(num(process.env.DRIVER_FATIGUE_SWEEP_SEC, 30, 1, 600) * 1000),
};

/** Redis keys owned by this feature (kept here, not in the shared key file). */
export const FatigueKeys = {
  // Hash: acc (online seconds of closed sessions since the last reset),
  // lastOff (epoch ms the driver last went offline), warned (0/1),
  // remindSince/remindN (break reminders sent for the open session).
  fatigue: (id: string) => `driver:${id}:fatigue`,
  // Set of drivers with an open online session, for the sweeper.
  fatigueTracked: () => 'drivers:fatigue:tracked',
  sweepLock: () => 'drivers:fatigue:sweeper:lock',
};

export interface FatigueRaw {
  acc: number; // closed-session seconds since the last reset
  lastOff: number | null; // epoch ms
  onlineSince: number | null; // epoch ms, open session
}

export interface FatigueState {
  onlineSeconds: number;
  limitSeconds: number;
  remainingSeconds: number;
  warnAtSeconds: number;
  restBreakSeconds: number;
  online: boolean;
  /** At or over the limit: no offers; must rest before going online. */
  overLimit: boolean;
  /** Offline and still inside the required break. */
  resting: boolean;
  restSecondsLeft: number;
  restUntil: string | null;
}

/** Where the driver stands against the fatigue limit at [now]. */
export function fatigueState(
  raw: FatigueRaw,
  now: number,
  cfg = {
    max: fatigueConfig.maxOnlineSecs(),
    rest: fatigueConfig.restBreakSecs(),
    warn: fatigueConfig.warnBeforeSecs(),
  },
): FatigueState {
  const online = !!raw.onlineSince && raw.onlineSince > 0;
  let acc = Math.max(0, raw.acc || 0);
  // Offline for a full break: the counter has reset (it is zeroed for real
  // when the driver next goes online).
  if (!online && raw.lastOff && now - raw.lastOff >= cfg.rest * 1000) acc = 0;
  const open = online ? Math.max(0, Math.round((now - raw.onlineSince!) / 1000)) : 0;
  const worked = acc + open;
  const overLimit = worked >= cfg.max;
  let restSecondsLeft = 0;
  let restUntil: string | null = null;
  if (overLimit) {
    if (online || !raw.lastOff) {
      restSecondsLeft = cfg.rest; // the break starts when they go offline
    } else {
      const until = raw.lastOff + cfg.rest * 1000;
      restSecondsLeft = Math.max(0, Math.ceil((until - now) / 1000));
      restUntil = new Date(until).toISOString();
    }
  }
  return {
    onlineSeconds: worked,
    limitSeconds: cfg.max,
    remainingSeconds: Math.max(0, cfg.max - worked),
    warnAtSeconds: Math.max(0, cfg.max - cfg.warn),
    restBreakSeconds: cfg.rest,
    online,
    overLimit,
    resting: overLimit && !online && restSecondsLeft > 0,
    restSecondsLeft,
    restUntil,
  };
}
