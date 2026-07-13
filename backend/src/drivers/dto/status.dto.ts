import { IsIn } from 'class-validator';

export class DriverStatusDto {
  @IsIn(['online', 'offline'])
  status!: 'online' | 'offline';
}
