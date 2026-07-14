import { IsNumber, IsOptional, IsString, MaxLength, Min } from 'class-validator';

export class RefundDto {
  /** Amount to refund; omit for a full refund of the remaining balance. */
  @IsOptional() @IsNumber() @Min(0.01)
  amount?: number;

  @IsOptional() @IsString() @MaxLength(200)
  reason?: string;
}
