import { IsEmail, IsOptional } from 'class-validator';

export class InitiateBgcDto {
  /** Optional email for the check; falls back to the account email on file. */
  @IsOptional() @IsEmail()
  email?: string;
}
