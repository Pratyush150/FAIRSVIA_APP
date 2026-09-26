import {
  ArrayMaxSize,
  IsArray,
  IsIn,
  IsNumber,
  IsOptional,
  Max,
  Min,
  ValidateNested,
} from 'class-validator';
import { Type } from 'class-transformer';
import { MAX_STOPS, StopDto } from '../../trips/dto/stop.dto';
import { TIER_KEYS } from '../../pricing/fare-config';
import { COMPARISON_CURRENCIES } from '../competitor-config';

/**
 * Request for a price comparison. Same pickup/dropoff (+ optional stops) as an
 * estimate, plus an optional tier to compare on (defaults to economy — the
 * like-for-like class against UberX / Lyft Standard / Empower).
 */
export class CompareDto {
  @IsNumber()
  @Min(-90)
  @Max(90)
  pickupLat!: number;

  @IsNumber()
  @Min(-180)
  @Max(180)
  pickupLng!: number;

  @IsNumber()
  @Min(-90)
  @Max(90)
  dropoffLat!: number;

  @IsNumber()
  @Min(-180)
  @Max(180)
  dropoffLng!: number;

  @IsOptional()
  @IsArray()
  @ArrayMaxSize(MAX_STOPS)
  @ValidateNested({ each: true })
  @Type(() => StopDto)
  stops?: StopDto[];

  @IsOptional()
  @IsIn(TIER_KEYS)
  tier?: string;

  /**
   * Verification only: compare in another supported market's currency (USD,
   * UZS, AED) without switching the live market. Our own fare then comes from
   * that currency's seed fare config. Omitted = the market currency.
   */
  @IsOptional()
  @IsIn(COMPARISON_CURRENCIES)
  currency?: string;
}
