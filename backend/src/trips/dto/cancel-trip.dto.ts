import { IsOptional, IsString, MaxLength } from 'class-validator';

export class CancelTripDto {
  @IsOptional()
  @IsString()
  @MaxLength(280)
  reason?: string;
}
