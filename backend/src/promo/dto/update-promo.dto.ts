import {
  IsBoolean,
  IsISO8601,
  IsNumber,
  IsOptional,
  IsString,
  MaxLength,
  Min,
} from 'class-validator';

export class UpdatePromoDto {
  @IsOptional() @IsBoolean()
  active?: boolean;

  @IsOptional() @IsNumber() @Min(1)
  usageLimit?: number;

  @IsOptional() @IsNumber() @Min(1)
  perUserLimit?: number;

  @IsOptional() @IsISO8601()
  expiresAt?: string;

  /** Show on the rider's Offers page. */
  @IsOptional() @IsBoolean()
  listed?: boolean;

  @IsOptional() @IsString() @MaxLength(60)
  title?: string;

  @IsOptional() @IsString() @MaxLength(200)
  description?: string;
}
