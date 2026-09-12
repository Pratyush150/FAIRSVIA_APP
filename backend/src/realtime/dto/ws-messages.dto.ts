import {
  IsIn,
  IsNumber,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
} from 'class-validator';

/** `driver:location` payload — bounded to valid geographic ranges. */
export class LocationPingDto {
  @IsNumber() @Min(-90) @Max(90)
  lat!: number;

  @IsNumber() @Min(-180) @Max(180)
  lng!: number;

  // No Min/Max here: geolocator reports -1 (or NaN) for heading/speed when
  // unavailable (a stationary driver), and rejecting the whole ping over that
  // would silently drop the driver from the dispatch pool. Accept any number and
  // clamp to valid ranges in LocationService.ingest instead.
  @IsOptional() @IsNumber()
  heading?: number;

  @IsOptional() @IsNumber()
  speed?: number;
}

/** `driver:status` payload. */
export class DriverStatusDto {
  @IsIn(['online', 'offline'])
  status!: 'online' | 'offline';
}

/** `trip:accept` / `trip:decline` / `trip:sync` payload. */
export class TripIdDto {
  @IsString() @MaxLength(64)
  tripId!: string;
}

/** `trip:message` payload. */
export class TripMessageDto {
  @IsString() @MaxLength(64)
  tripId!: string;

  @IsString() @MaxLength(500)
  text!: string;
}
