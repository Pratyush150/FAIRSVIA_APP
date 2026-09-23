import {
  IsBoolean,
  IsDateString,
  IsIn,
  IsInt,
  IsNotEmpty,
  IsOptional,
  IsString,
  MaxLength,
} from 'class-validator';

export const CTA_TYPES = ['none', 'promo_code', 'url'] as const;
export type CtaType = (typeof CTA_TYPES)[number];

export class CreateRideCardDto {
  @IsString() @IsNotEmpty() @MaxLength(80)
  title!: string;

  @IsString() @IsNotEmpty() @MaxLength(240)
  body!: string;

  @IsIn(CTA_TYPES)
  ctaType!: CtaType;

  @IsOptional() @IsString() @MaxLength(40)
  ctaLabel?: string;

  /** The promo code, or the https:// link. */
  @IsOptional() @IsString() @MaxLength(500)
  ctaValue?: string;

  @IsOptional() @IsBoolean()
  active?: boolean;

  @IsOptional() @IsDateString()
  startsAt?: string;

  @IsOptional() @IsDateString()
  endsAt?: string;

  @IsOptional() @IsInt()
  sortOrder?: number;
}

/** Every field optional: only what is sent changes. */
export class UpdateRideCardDto {
  @IsOptional() @IsString() @IsNotEmpty() @MaxLength(80)
  title?: string;

  @IsOptional() @IsString() @IsNotEmpty() @MaxLength(240)
  body?: string;

  @IsOptional() @IsIn(CTA_TYPES)
  ctaType?: CtaType;

  @IsOptional() @IsString() @MaxLength(40)
  ctaLabel?: string;

  @IsOptional() @IsString() @MaxLength(500)
  ctaValue?: string;

  @IsOptional() @IsBoolean()
  active?: boolean;

  @IsOptional() @IsDateString()
  startsAt?: string;

  @IsOptional() @IsDateString()
  endsAt?: string;

  @IsOptional() @IsInt()
  sortOrder?: number;
}
