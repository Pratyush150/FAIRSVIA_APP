import {
  IsBoolean,
  IsIn,
  IsISO8601,
  IsNumber,
  IsOptional,
  IsString,
  Matches,
  Max,
  MaxLength,
  Min,
} from 'class-validator';

export class CreatePromoDto {
  @IsString()
  @MaxLength(24)
  @Matches(/^[A-Za-z0-9]+$/, { message: 'code must be alphanumeric' })
  code!: string;

  @IsIn(['flat', 'percent'])
  kind!: 'flat' | 'percent';

  @IsNumber()
  @Min(0)
  value!: number;

  @IsOptional() @IsNumber() @Min(0)
  maxDiscount?: number;

  @IsOptional() @IsNumber() @Min(0)
  minSubtotal?: number;

  @IsOptional() @IsNumber() @Min(1)
  usageLimit?: number;

  @IsOptional() @IsNumber() @Min(1) @Max(100)
  perUserLimit?: number;

  @IsOptional() @IsBoolean()
  active?: boolean;

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
