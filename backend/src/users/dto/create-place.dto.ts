import { IsNumber, IsOptional, IsString, Max, MaxLength, Min } from 'class-validator';

export class CreatePlaceDto {
  @IsString()
  @MaxLength(40)
  label!: string; // e.g. 'home', 'work', or a custom name

  @IsOptional()
  @IsString()
  address?: string;

  @IsNumber() @Min(-90) @Max(90)
  lat!: number;

  @IsNumber() @Min(-180) @Max(180)
  lng!: number;
}
