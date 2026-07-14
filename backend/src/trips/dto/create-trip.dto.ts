import {
  ArrayMaxSize,
  IsArray,
  IsIn,
  IsISO8601,
  IsNumber,
  IsOptional,
  IsString,
  Max,
  Min,
  ValidateNested,
} from 'class-validator';
import { Type } from 'class-transformer';
import { TIER_KEYS } from '../../pricing/fare-config';
import { MAX_STOPS, StopDto } from './stop.dto';

export class CreateTripDto {
  @IsNumber() @Min(-90) @Max(90)
  pickupLat!: number;

  @IsNumber() @Min(-180) @Max(180)
  pickupLng!: number;

  @IsNumber() @Min(-90) @Max(90)
  dropoffLat!: number;

  @IsNumber() @Min(-180) @Max(180)
  dropoffLng!: number;

  @IsIn(TIER_KEYS)
  tier!: string;

  @IsOptional() @IsString()
  pickupAddr?: string;

  @IsOptional() @IsString()
  dropoffAddr?: string;

  // Accepted now but unused until Phase 3 (payments).
  @IsOptional() @IsString()
  paymentMethodId?: string;

  // Optional promo code; applied at creation if valid for this rider/fare.
  @IsOptional() @IsString()
  promoCode?: string;

  // How the rider pays: 'card' (default, auth-hold + capture) or 'cash'
  // (collected in person on completion).
  @IsOptional() @IsIn(['card', 'cash'])
  paymentMode?: 'card' | 'cash';

  // ISO-8601 time to schedule the ride for. When set (and far enough ahead),
  // the trip is created as `scheduled` and promoted to a live request then.
  @IsOptional() @IsISO8601()
  scheduledAt?: string;

  // Optional ordered intermediate stops (pickup → stops… → dropoff).
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(MAX_STOPS)
  @ValidateNested({ each: true })
  @Type(() => StopDto)
  stops?: StopDto[];
}
