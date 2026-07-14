import { IsBoolean } from 'class-validator';

export class VerifyDriverDto {
  @IsBoolean()
  docsVerified!: boolean;
}
