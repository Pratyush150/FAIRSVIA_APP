import { IsBoolean, IsOptional, IsString, MaxLength, MinLength, ValidateIf } from 'class-validator';

/**
 * Body of POST /trips/:id/complete. Empty for a normal drop-off. `endEarly`
 * is the driver's explicit "end the trip here" (away from the drop-off); it
 * needs a reason, and the rider is charged the metered fare (floored at the
 * tier minimum) — never the full up-front estimate.
 */
export class CompleteTripDto {
  @IsOptional()
  @IsBoolean()
  endEarly?: boolean;

  @ValidateIf((o: CompleteTripDto) => o.endEarly === true)
  @IsString()
  @MinLength(1)
  @MaxLength(280)
  reason?: string;
}

/** Body of POST /trips/:id/end-early (rider or driver). */
export class EndTripEarlyDto {
  @IsOptional()
  @IsString()
  @MaxLength(280)
  reason?: string;
}
