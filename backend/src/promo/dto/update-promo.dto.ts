import {
  IsBoolean,
  IsISO8601,
  IsNumber,
  IsOptional,
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
}
