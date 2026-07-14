import { IsNumber, IsOptional, IsString, Max, MaxLength, Min } from 'class-validator';

/** An intermediate stop between pickup and dropoff. */
export class StopDto {
  @IsNumber() @Min(-90) @Max(90)
  lat!: number;

  @IsNumber() @Min(-180) @Max(180)
  lng!: number;

  @IsOptional() @IsString() @MaxLength(200)
  addr?: string;
}

/** Cap the number of intermediate stops per trip. */
export const MAX_STOPS = 3;
