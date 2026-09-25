import {
  ArrayUnique,
  IsArray,
  IsBoolean,
  IsIn,
  IsISO8601,
  IsInt,
  IsNumber,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
  MinLength,
} from 'class-validator';

const TIERS = ['economy', 'comfort', 'xl', 'premium', 'auto', 'bike'];

export class CreateQuestDto {
  @IsString() @MinLength(3) @MaxLength(120)
  title!: string;

  /** Empty or omitted = every tier counts. */
  @IsOptional() @IsArray() @ArrayUnique() @IsIn(TIERS, { each: true })
  tiers?: string[];

  @IsInt() @Min(1) @Max(500)
  targetTrips!: number;

  @IsISO8601()
  startsAt!: string;

  @IsISO8601()
  endsAt!: string;

  @IsNumber() @Min(1) @Max(1_000_000)
  bonusAmount!: number;

  @IsOptional() @IsBoolean()
  active?: boolean;
}

export class UpdateQuestDto {
  @IsOptional() @IsString() @MinLength(3) @MaxLength(120)
  title?: string;

  @IsOptional() @IsArray() @ArrayUnique() @IsIn(TIERS, { each: true })
  tiers?: string[];

  @IsOptional() @IsInt() @Min(1) @Max(500)
  targetTrips?: number;

  @IsOptional() @IsISO8601()
  startsAt?: string;

  @IsOptional() @IsISO8601()
  endsAt?: string;

  @IsOptional() @IsNumber() @Min(1) @Max(1_000_000)
  bonusAmount?: number;

  @IsOptional() @IsBoolean()
  active?: boolean;
}
