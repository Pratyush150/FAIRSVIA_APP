import { IsBoolean, IsOptional, IsString, MaxLength, MinLength } from 'class-validator';

/** Driver-side cancel: a reason is mandatory (it is shown to the rider). */
export class DriverCancelTripDto {
  @IsString()
  @MinLength(1)
  @MaxLength(280)
  reason!: string;

  /** The rider didn't show: allowed only after the no-show wait from arrival,
   *  and charges the rider the cancellation fee (the driver's compensation). */
  @IsOptional()
  @IsBoolean()
  noShow?: boolean;
}
