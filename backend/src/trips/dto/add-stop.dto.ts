import { IsNumber, IsOptional, Min } from 'class-validator';
import { StopDto } from './stop.dto';

/** Add a stop to a live ride. `quotedFare` is the price the rider confirmed
 *  on the quote; the server refuses (409) if it has since moved. */
export class AddStopDto extends StopDto {
  @IsOptional()
  @IsNumber()
  @Min(0)
  quotedFare?: number;
}
