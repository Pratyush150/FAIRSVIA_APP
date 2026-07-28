import { fitLinear } from './calibration.service';

describe('fitLinear (OLS coefficient fit)', () => {
  it('recovers exact coefficients from clean data', () => {
    // metered = 2.0 + 1.10*mi + 0.20*min
    const rows = [
      { mi: 1, min: 5 },
      { mi: 3, min: 12 },
      { mi: 5, min: 20 },
      { mi: 8, min: 30 },
      { mi: 2, min: 9 },
      { mi: 6, min: 25 },
    ].map((r) => ({ ...r, metered: 2.0 + 1.1 * r.mi + 0.2 * r.min }));

    const fit = fitLinear(rows)!;
    expect(fit.c0).toBeCloseTo(2.0, 3);
    expect(fit.c1).toBeCloseTo(1.1, 3);
    expect(fit.c2).toBeCloseTo(0.2, 3);
  });

  it('finds a best-fit line through noisy data (close to truth)', () => {
    const truth = (mi: number, min: number) => 1.5 + 1.2 * mi + 0.25 * min;
    // Deterministic pseudo-noise (no Math.random — must be reproducible).
    const noise = [0.1, -0.15, 0.05, -0.08, 0.12, -0.03, 0.09, -0.11];
    // Distance and duration are DEcorrelated here (same mi, different min for
    // traffic) so the fit can separate per-mile from per-min — as real samples
    // across conditions do.
    const rows = [
      { mi: 2, min: 6 },
      { mi: 2, min: 14 },
      { mi: 5, min: 10 },
      { mi: 5, min: 24 },
      { mi: 8, min: 16 },
      { mi: 8, min: 34 },
      { mi: 3, min: 20 },
      { mi: 7, min: 12 },
    ].map((r, i) => ({ ...r, metered: truth(r.mi, r.min) + noise[i] }));

    const fit = fitLinear(rows)!;
    expect(fit.c0).toBeCloseTo(1.5, 1);
    expect(fit.c1).toBeCloseTo(1.2, 1);
    expect(fit.c2).toBeCloseTo(0.25, 1);
  });

  it('returns null for too few points', () => {
    expect(fitLinear([{ mi: 1, min: 5, metered: 8 }])).toBeNull();
  });

  it('returns null when the system is singular (degenerate inputs)', () => {
    // All identical rows → no variation → singular normal equations.
    const rows = Array.from({ length: 6 }, () => ({ mi: 2, min: 10, metered: 9 }));
    expect(fitLinear(rows)).toBeNull();
  });
});
