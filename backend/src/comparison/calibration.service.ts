import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';
import { COMPETITOR_MODELS, ProviderFareModel } from './competitor-config';

/** Minimum de-surged samples before we trust a fit over the seed defaults. */
const MIN_SAMPLES_TO_FIT = 8;

/** A recorded real competitor fare used to calibrate a rate card. */
export interface FareSampleInput {
  provider: string;
  market?: string;
  distanceM: number;
  durationS: number;
  observedFare: number;
  /** The surge multiplier we estimated at sample time (to de-surge the fare). */
  surgeAtSample?: number;
  hourBucket?: number;
  source?: string;
}

const METERS_PER_MILE = 1609.34;

/**
 * Keeps the competitor rate cards (CompetitorFareModel) calibrated to reality.
 *
 * Seeds from the code defaults, then re-fits each provider's linear coefficients
 * (base, perMile, perMin) from observed FareSample rows via ordinary least
 * squares. bookingFee / minFare / surgeSensitivity stay as configured — the
 * samples calibrate the metered portion, which is what drifts. Everything here
 * is still a MODELED estimate (see competitor-config.ts); calibration only makes
 * the model track published/real fares more tightly per market.
 */
@Injectable()
export class CalibrationService implements OnModuleInit {
  private readonly logger = new Logger('Calibration');

  private cache: Record<string, ProviderFareModel> = seedMap();

  constructor(private readonly prisma: PrismaService) {}

  async onModuleInit() {
    await this.seedIfEmpty();
    await this.refresh();
  }

  /** The current (possibly calibrated) competitor models. */
  models(): ProviderFareModel[] {
    return COMPETITOR_MODELS.map((m) => this.cache[m.provider] ?? m);
  }

  private async seedIfEmpty() {
    try {
      const count = await this.prisma.competitorFareModel.count();
      if (count > 0) return;
      await this.prisma.competitorFareModel.createMany({
        data: COMPETITOR_MODELS.map((m) => ({
          provider: m.provider,
          displayName: m.displayName,
          productName: m.productName,
          baseFare: m.baseFare,
          perMile: m.perMile,
          perMin: m.perMin,
          bookingFee: m.bookingFee,
          minFare: m.minFare,
          surgeSensitivity: m.surgeSensitivity,
        })),
        skipDuplicates: true,
      });
      this.logger.log('Seeded competitor_fare_models from defaults');
    } catch (e) {
      this.logger.warn(`seed competitor models failed: ${String(e)}`);
    }
  }

  /** Reload the in-memory model cache from the DB. */
  async refresh() {
    try {
      const rows = await this.prisma.competitorFareModel.findMany();
      if (rows.length === 0) return;
      const next: Record<string, ProviderFareModel> = {};
      for (const r of rows) {
        next[r.provider] = {
          provider: r.provider,
          displayName: r.displayName,
          productName: r.productName,
          baseFare: r.baseFare,
          perMile: r.perMile,
          perMin: r.perMin,
          bookingFee: r.bookingFee,
          minFare: r.minFare,
          surgeSensitivity: r.surgeSensitivity,
          calibrated: r.calibrated,
          residualPct: r.residualPct,
        };
      }
      this.cache = next;
    } catch (e) {
      this.logger.warn(`competitor model refresh failed: ${String(e)}`);
    }
  }

  /** Record an observed real fare, then re-fit that provider if we have enough. */
  async recordSample(input: FareSampleInput): Promise<{ refit: boolean }> {
    await this.prisma.fareSample.create({
      data: {
        provider: input.provider,
        market: input.market ?? 'miami',
        distanceM: Math.round(input.distanceM),
        durationS: Math.round(input.durationS),
        observedFare: input.observedFare,
        surgeAtSample: input.surgeAtSample ?? 1,
        hourBucket: input.hourBucket ?? 0,
        source: input.source ?? 'manual',
      },
    });
    const refit = await this.refit(input.provider, input.market ?? 'miami');
    return { refit };
  }

  /**
   * Re-fit `provider`'s (base, perMile, perMin) from its de-surged samples.
   * Returns true if a fit was applied. Samples at/below the min-fare floor are
   * dropped (they don't inform the linear part).
   */
  async refit(provider: string, market = 'miami'): Promise<boolean> {
    const model = this.cache[provider] ?? seedMap()[provider];
    if (!model) return false;

    const samples = await this.prisma.fareSample.findMany({
      where: { provider, market },
      orderBy: { createdAt: 'desc' },
      take: 500,
    });

    // De-surge and drop min-fare-floored samples.
    const rows: { mi: number; min: number; metered: number }[] = [];
    for (const s of samples) {
      if (s.observedFare <= model.minFare * 1.02) continue;
      const effSurge = 1 + (s.surgeAtSample - 1) * model.surgeSensitivity;
      if (effSurge <= 0) continue;
      const metered = (s.observedFare - model.bookingFee) / effSurge;
      rows.push({
        mi: s.distanceM / METERS_PER_MILE,
        min: s.durationS / 60,
        metered,
      });
    }
    if (rows.length < MIN_SAMPLES_TO_FIT) return false;

    const fit = fitLinear(rows);
    if (!fit) return false;

    const residualPct = meanAbsPctError(rows, fit);
    const updated: ProviderFareModel = {
      ...model,
      baseFare: round4(fit.c0),
      perMile: round4(fit.c1),
      perMin: round4(fit.c2),
      calibrated: true,
      residualPct: round4(residualPct),
    };
    this.cache[provider] = updated;
    await this.prisma.competitorFareModel.update({
      where: { provider },
      data: {
        baseFare: updated.baseFare,
        perMile: updated.perMile,
        perMin: updated.perMin,
        calibrated: true,
        sampleCount: rows.length,
        residualPct: round4(residualPct),
      },
    });
    this.logger.log(
      `Calibrated ${provider} from ${rows.length} samples ` +
        `(residual ${(residualPct * 100).toFixed(1)}%)`,
    );
    return true;
  }
}

function seedMap(): Record<string, ProviderFareModel> {
  const m: Record<string, ProviderFareModel> = {};
  for (const c of COMPETITOR_MODELS) m[c.provider] = { ...c };
  return m;
}

/**
 * Ordinary least squares for metered ≈ c0 + c1*mi + c2*min via the 3×3 normal
 * equations. Returns null if the system is singular (e.g. degenerate samples).
 */
export function fitLinear(
  rows: { mi: number; min: number; metered: number }[],
): { c0: number; c1: number; c2: number } | null {
  const n = rows.length;
  if (n < 3) return null;
  // Build XtX (symmetric 3x3) and Xty.
  let s0 = n,
    sMi = 0,
    sMin = 0,
    sMiMi = 0,
    sMiMin = 0,
    sMinMin = 0;
  let ty = 0,
    tyMi = 0,
    tyMin = 0;
  for (const r of rows) {
    sMi += r.mi;
    sMin += r.min;
    sMiMi += r.mi * r.mi;
    sMiMin += r.mi * r.min;
    sMinMin += r.min * r.min;
    ty += r.metered;
    tyMi += r.metered * r.mi;
    tyMin += r.metered * r.min;
  }
  const A: number[][] = [
    [s0, sMi, sMin],
    [sMi, sMiMi, sMiMin],
    [sMin, sMiMin, sMinMin],
  ];
  const b = [ty, tyMi, tyMin];
  const sol = solve3x3(A, b);
  if (!sol) return null;
  return { c0: sol[0], c1: sol[1], c2: sol[2] };
}

/** Solve a 3×3 linear system by Cramer's rule; null if near-singular. */
function solve3x3(A: number[][], b: number[]): number[] | null {
  const det = det3(A);
  if (Math.abs(det) < 1e-9) return null;
  const x: number[] = [];
  for (let i = 0; i < 3; i++) {
    const Ai = A.map((row) => row.slice());
    for (let r = 0; r < 3; r++) Ai[r][i] = b[r];
    x.push(det3(Ai) / det);
  }
  return x;
}

function det3(m: number[][]): number {
  return (
    m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) -
    m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0]) +
    m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0])
  );
}

function meanAbsPctError(
  rows: { mi: number; min: number; metered: number }[],
  fit: { c0: number; c1: number; c2: number },
): number {
  let sum = 0;
  let n = 0;
  for (const r of rows) {
    if (r.metered <= 0) continue;
    const pred = fit.c0 + fit.c1 * r.mi + fit.c2 * r.min;
    sum += Math.abs(pred - r.metered) / r.metered;
    n++;
  }
  return n === 0 ? 0 : sum / n;
}

function round4(n: number): number {
  return Math.round(n * 10000) / 10000;
}
