/**
 * Calendar days in the business time zone, not the server's. The server runs
 * in UTC; Tashkent is UTC+5, so "today" by server midnight would start at
 * 05:00 local time and put the late-evening rush on the wrong day.
 */

/** Offset of [tz] from UTC at [at], in minutes (e.g. +300 for Tashkent). */
function offsetMinutes(at: Date, tz: string): number {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: tz,
    hourCycle: 'h23',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  }).formatToParts(at);
  const get = (t: string) => Number(parts.find((p) => p.type === t)!.value);
  const asUtc = Date.UTC(get('year'), get('month') - 1, get('day'), get('hour'), get('minute'), get('second'));
  return Math.round((asUtc - Math.floor(at.getTime() / 1000) * 1000) / 60000);
}

/** `YYYY-MM-DD` of [at] in [tz]. */
export function businessDayKey(at: Date, tz: string): string {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: tz,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(at);
}

/** The instant local midnight began, in [tz], for the day containing [at]. */
export function startOfBusinessDay(at: Date, tz: string): Date {
  const [y, m, d] = businessDayKey(at, tz).split('-').map(Number);
  const guess = Date.UTC(y, m - 1, d);
  // Midnight local = midnight UTC minus the offset in force at that moment.
  // Re-read the offset at the candidate itself so a DST change during the day
  // (not in Tashkent, but in other markets) lands on the right instant.
  const first = guess - offsetMinutes(new Date(guess), tz) * 60000;
  return new Date(guess - offsetMinutes(new Date(first), tz) * 60000);
}
