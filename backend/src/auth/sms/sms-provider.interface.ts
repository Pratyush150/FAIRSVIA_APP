export const SMS_PROVIDER = 'SMS_PROVIDER';

/**
 * Abstraction over SMS delivery. Swap the mock for Twilio (or any gateway)
 * in a later phase without touching AuthService.
 */
export interface SmsProvider {
  /** Deliver a one-time passcode to the given phone number. */
  sendOtp(phone: string, code: string): Promise<void>;

  /**
   * Deliver a plain transactional message. Used for people who are not app
   * users — notably the passenger of a ride somebody else booked, who needs
   * the start code and the "your driver is here" nudge but may never have
   * installed anything.
   */
  sendMessage(phone: string, message: string): Promise<void>;
}
