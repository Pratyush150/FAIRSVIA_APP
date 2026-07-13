import { IsNumber, IsPositive, Max } from 'class-validator';

export class TipDto {
  @IsNumber()
  @IsPositive()
  @Max(100000)
  amount!: number;
}
