import { IsString, Matches, Length } from 'class-validator';

export class VerifyOtpDto {
  @IsString()
  @Matches(/^\+?[1-9]\d{7,14}$/, {
    message: 'phone must be a valid E.164 number',
  })
  phone!: string;

  @IsString()
  @Length(4, 6)
  code!: string;
}
