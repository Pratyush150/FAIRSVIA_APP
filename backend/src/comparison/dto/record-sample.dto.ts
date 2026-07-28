import { IsIn, IsNumber, IsOptional, IsString, Max, Min } from 'class-validator';

/** Provider ids we hold competitor models for. */
export const COMPETITOR_PROVIDERS = ['uber', 'lyft', 'empower'];

/**
 * An observed real competitor fare, submitted to calibrate that provider's rate
 * card. Gathered manually / from a small consented panel — never by scraping.
 */
export class RecordSampleDto {
  @IsString()
  @IsIn(COMPETITOR_PROVIDERS)
  provider!: string;

  @IsOptional()
  @IsString()
  market?: string;

  @IsNumber()
  @Min(1)
  distanceM!: number;

  @IsNumber()
  @Min(1)
  durationS!: number;

  @IsNumber()
  @Min(0)
  observedFare!: number;

  /** The surge we estimated at sample time (to de-surge the fare). Default 1. */
  @IsOptional()
  @IsNumber()
  @Min(1)
  @Max(6)
  surgeAtSample?: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  @Max(23)
  hourBucket?: number;

  @IsOptional()
  @IsString()
  source?: string;
}
