import { IsString, Length } from 'class-validator';

export class StartTripDto {
  @IsString()
  @Length(4, 4)
  otp!: string;
}
