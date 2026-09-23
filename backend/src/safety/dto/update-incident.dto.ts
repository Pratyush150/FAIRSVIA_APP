import { IsIn, IsOptional, IsString, MaxLength } from 'class-validator';

export class UpdateIncidentDto {
  @IsIn(['acknowledged', 'resolved'])
  status!: 'acknowledged' | 'resolved';

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  note?: string;
}
