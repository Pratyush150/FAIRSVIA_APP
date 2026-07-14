import { IsNumber, IsOptional, IsString, Max, MaxLength, Min } from 'class-validator';

export class UpdatePlaceDto {
  @IsOptional()
  @IsString()
  @MaxLength(40)
  label?: string;

  @IsOptional()
  @IsString()
  @MaxLength(200)
  address?: string;

  @IsOptional()
  @IsNumber() @Min(-90) @Max(90)
  lat?: number;

  @IsOptional()
  @IsNumber() @Min(-180) @Max(180)
  lng?: number;
}
