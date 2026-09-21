import { IsOptional, IsString, IsNotEmpty } from 'class-validator';

export class LogoutDto {
  /** The device's refresh token. Omit to sign out of every device. */
  @IsOptional()
  @IsString()
  @IsNotEmpty()
  refreshToken?: string;
}
