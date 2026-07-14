import { IsNumber, IsString, MaxLength, Min } from 'class-validator';

export class QuotePromoDto {
  @IsString()
  @MaxLength(24)
  code!: string;

  /** The fare subtotal (before discount) the code should be priced against. */
  @IsNumber()
  @Min(0)
  subtotal!: number;
}
