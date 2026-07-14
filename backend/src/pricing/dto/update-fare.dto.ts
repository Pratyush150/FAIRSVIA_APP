import { IsNumber, IsOptional, IsString, MaxLength, Min } from 'class-validator';

export class UpdateFareDto {
  @IsOptional() @IsString() @MaxLength(30)
  label?: string;

  @IsOptional() @IsNumber() @Min(0)
  baseFare?: number;

  @IsOptional() @IsNumber() @Min(0)
  perMile?: number;

  @IsOptional() @IsNumber() @Min(0)
  perMin?: number;

  @IsOptional() @IsNumber() @Min(0)
  bookingFee?: number;

  @IsOptional() @IsNumber() @Min(0)
  minFare?: number;

  @IsOptional() @IsNumber() @Min(1)
  capacity?: number;
}
