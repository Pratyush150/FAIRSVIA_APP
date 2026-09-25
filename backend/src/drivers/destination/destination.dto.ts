import { Type } from 'class-transformer';
import { IsBoolean, IsLatitude, IsLongitude, IsOptional, IsString, MaxLength } from 'class-validator';

export class DestinationModeDto {
  @Type(() => Number)
  @IsLatitude()
  lat!: number;

  @Type(() => Number)
  @IsLongitude()
  lng!: number;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  label?: string;

  /** Also remember this point as the driver's saved "Home". */
  @IsOptional()
  @IsBoolean()
  saveAsHome?: boolean;
}
