import {
  IsNotEmpty,
  IsNumber,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
} from 'class-validator';

export class CreatePlaceDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(40)
  label!: string; // e.g. 'home', 'work', or a custom name

  @IsOptional()
  @IsString()
  @MaxLength(200)
  address?: string;

  @IsNumber() @Min(-90) @Max(90)
  lat!: number;

  @IsNumber() @Min(-180) @Max(180)
  lng!: number;
}
