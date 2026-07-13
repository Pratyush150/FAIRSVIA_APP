import { IsOptional, IsString, Length, MaxLength } from 'class-validator';

export class AddMethodDto {
  // Stripe PaymentMethod id when using real Stripe; optional for the mock.
  @IsOptional() @IsString() @MaxLength(120)
  externalId?: string;

  @IsOptional() @IsString() @MaxLength(20)
  brand?: string;

  @IsOptional() @IsString() @Length(4, 4)
  last4?: string;
}
