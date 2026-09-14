import { IsString, Matches } from 'class-validator';

export class RequestOtpDto {
  // Strict E.164: leading + and 8-15 digits. Without the country code a
  // local number would be stored as-is and never match on the next login.
  @IsString()
  @Matches(/^\+[1-9]\d{7,14}$/, {
    message: 'phone must be a valid E.164 number (e.g. +13055550137)',
  })
  phone!: string;
}
