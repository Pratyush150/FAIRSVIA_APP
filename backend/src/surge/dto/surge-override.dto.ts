import { IsNumber, Max, Min } from 'class-validator';

export class SurgeOverrideDto {
  // 1 clears the override; up to the cap forces a global surge floor.
  @IsNumber() @Min(1) @Max(3)
  multiplier!: number;
}
