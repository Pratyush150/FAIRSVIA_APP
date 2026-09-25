import { businessDayKey, startOfBusinessDay } from '../common/time/business-day';

/**
 * Online time is credited per business day (the market's calendar, not the
 * server's UTC one): a session that runs past local midnight is split so each
 * day gets only the part that fell on it. Returned as `YYYY-MM-DD` → seconds.
 *
 * Bounded to the last [maxDays] days of the session — a session start that is
 * absurdly old (a key left over from a crash) must not credit a month.
 */
export function splitByBusinessDay(
  from: Date,
  to: Date,
  tz: string,
  maxDays = 8,
): Record<string, number> {
  const out: Record<string, number> = {};
  if (!(to.getTime() > from.getTime())) return out;
  const floor = to.getTime() - maxDays * 86400_000;
  let cursor = Math.max(from.getTime(), floor);
  const end = to.getTime();
  // One iteration per calendar day touched; the guard is belt-and-braces.
  for (let i = 0; i <= maxDays + 1 && cursor < end; i++) {
    const dayStart = startOfBusinessDay(new Date(cursor), tz).getTime();
    // The next local midnight: 36 h after this one always lands inside the
    // next day (even across a 23 h / 25 h DST day), then snap to its start.
    const next = startOfBusinessDay(new Date(dayStart + 36 * 3600_000), tz).getTime();
    const segEnd = Math.min(next, end);
    const key = businessDayKey(new Date(cursor), tz);
    out[key] = (out[key] ?? 0) + Math.round((segEnd - cursor) / 1000);
    cursor = segEnd;
  }
  return out;
}
