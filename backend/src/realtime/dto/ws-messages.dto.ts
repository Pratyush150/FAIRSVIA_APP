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

  @IsOptional() @IsNumber() @Min(0) @Max(360)
  heading?: number;

  @IsOptional() @IsNumber() @Min(0) @Max(400)
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
