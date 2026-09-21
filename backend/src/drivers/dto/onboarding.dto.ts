import { Transform } from 'class-transformer';
import {
  IsIn,
  IsNotEmpty,
  IsOptional,
  IsString,
  MaxLength,
} from 'class-validator';

const trim = ({ value }: { value: unknown }) =>
  typeof value === 'string' ? value.trim() : value;
import { TIER_KEYS } from '../../pricing/fare-config';

export class OnboardingDto {
  @Transform(trim) @IsString() @IsNotEmpty() @MaxLength(60)
  vehicleMake!: string;

  @Transform(trim) @IsString() @IsNotEmpty() @MaxLength(60)
  vehicleModel!: string;

  @IsOptional() @IsString() @MaxLength(30)
  vehicleColor?: string;

  @Transform(trim) @IsString() @IsNotEmpty() @MaxLength(20)
  plateNumber!: string;

  @IsIn(TIER_KEYS)
  vehicleTier!: string;

  @IsOptional() @IsString() @MaxLength(60)
  licenseNo?: string;
}
