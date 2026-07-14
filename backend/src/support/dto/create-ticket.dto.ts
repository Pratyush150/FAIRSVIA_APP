import {
  IsIn,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
  MinLength,
} from 'class-validator';

export class CreateTicketDto {
  @IsString() @MinLength(3) @MaxLength(140)
  subject!: string;

  @IsString() @MinLength(1) @MaxLength(2000)
  message!: string;

  @IsOptional()
  @IsIn(['payment', 'safety', 'lost_item', 'driver', 'app', 'other'])
  category?: string;

  @IsOptional() @IsUUID()
  tripId?: string;
}
