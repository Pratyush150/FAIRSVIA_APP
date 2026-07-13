import { IsString, Matches } from 'class-validator';

export class RequestOtpDto {
  // E.164-ish: optional +, 8-15 digits.
  @IsString()
  @Matches(/^\+?[1-9]\d{7,14}$/, {
    message: 'phone must be a valid E.164 number (e.g. +919876543210)',
  })
  phone!: string;
}
