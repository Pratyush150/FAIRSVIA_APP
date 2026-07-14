import { IsIn } from 'class-validator';

export class UpdateTicketDto {
  @IsIn(['open', 'active', 'resolved', 'closed'])
  status!: string;
}
