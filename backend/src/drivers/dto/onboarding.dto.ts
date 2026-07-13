import { IsIn, IsOptional, IsString, MaxLength } from 'class-validator';
import { TIER_KEYS } from '../../pricing/fare-config';

export class OnboardingDto {
  @IsString() @MaxLength(60)
  vehicleMake!: string;

  @IsString() @MaxLength(60)
  vehicleModel!: string;

  @IsOptional() @IsString() @MaxLength(30)
  vehicleColor?: string;

  @IsString() @MaxLength(20)
  plateNumber!: string;

  @IsIn(TIER_KEYS)
  vehicleTier!: string;

  @IsOptional() @IsString() @MaxLength(60)
  licenseNo?: string;
}
