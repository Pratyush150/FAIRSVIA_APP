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

  /** Horizontal accuracy radius (m) as reported by the device. Fixes worse
   *  than 100 m are stored but neither metered nor shown to the rider. */
  @IsOptional() @IsNumber() @Min(0) @Max(500)
  accuracy?: number;

  /** Device timestamp of the fix (epoch ms). Echoed to the rider so the map
   *  can age the marker; the server keeps its own clock for staleness. */
  @IsOptional() @IsNumber() @Min(0) @Max(4102444800000)
  ts?: number;
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
