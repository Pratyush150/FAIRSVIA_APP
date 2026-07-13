export const SMS_PROVIDER = 'SMS_PROVIDER';

/**
 * Abstraction over SMS delivery. Swap the mock for Twilio (or any gateway)
 * in a later phase without touching AuthService.
 */
export interface SmsProvider {
  /** Deliver a one-time passcode to the given phone number. */
  sendOtp(phone: string, code: string): Promise<void>;
}
