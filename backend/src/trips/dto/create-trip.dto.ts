import {
  IsIn,
  IsNumber,
  IsOptional,
  IsString,
  Max,
  Min,
} from 'class-validator';
import { TIER_KEYS } from '../../pricing/fare-config';

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
}
