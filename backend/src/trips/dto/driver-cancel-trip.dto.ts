import { IsString, MaxLength, MinLength } from 'class-validator';

/** Driver-side cancel: a reason is mandatory (it is shown to the rider). */
export class DriverCancelTripDto {
  @IsString()
  @MinLength(1)
  @MaxLength(280)
  reason!: string;
}
