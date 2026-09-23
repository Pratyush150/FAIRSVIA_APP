import { IsNotEmpty, IsPhoneNumber, IsString, MaxLength } from 'class-validator';
import { Transform } from 'class-transformer';

export class CreateEmergencyContactDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(80)
  @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value))
  name!: string;

  /** International format (+998…), so an SMS can actually be delivered. */
  @IsPhoneNumber(undefined, {
    message: 'Enter the number in international format, e.g. +998 90 123 45 67',
  })
  @Transform(({ value }) =>
    typeof value === 'string' ? value.replace(/[\s()-]/g, '') : value,
  )
  phone!: string;
}
