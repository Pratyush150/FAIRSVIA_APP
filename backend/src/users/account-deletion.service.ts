import { ConflictException, Injectable, Logger } from '@nestjs/common';
import { TripStatus, UserRole } from '@prisma/client';
import { PrismaService } from '../common/prisma/prisma.service';
import { DriversService } from '../drivers/drivers.service';
import { LedgerService } from '../ledger/ledger.service';

const IN_FLIGHT: TripStatus[] = [
  TripStatus.requested,
  TripStatus.matching,
  TripStatus.accepted,
  TripStatus.arrived,
  TripStatus.in_progress,
];

/**
 * Self-service account deletion, required by the App Store (5.1.1(v)) and
 * Google Play for any app with sign-up.
 *
 * Personal data is removed; the user row stays, anonymised, because trips,
 * payments and the driver ledger are records we must keep by law (privacy
 * policy §4). The phone number is released, so the same number can sign up
 * again as a brand-new account.
 */
@Injectable()
export class AccountDeletionService {
  private readonly logger = new Logger(AccountDeletionService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly drivers: DriversService,
    private readonly ledger: LedgerService,
  ) {}

  async deleteAccount(userId: string): Promise<{ deleted: true }> {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user || user.deletedAt) return { deleted: true };

    const inFlight = await this.prisma.trip.count({
      where: {
        status: { in: IN_FLIGHT },
        OR: [{ riderId: userId }, { driverId: userId }],
      },
    });
    if (inFlight > 0) {
      throw new ConflictException(
        'You have a ride in progress. Finish or cancel it, then delete your account.',
      );
    }

    if (user.role === UserRole.driver) {
      // Deleting with money on either side would strand it: earnings the
      // driver can no longer withdraw, or commission they still owe.
      const balance = await this.ledger.balance(userId);
      if (balance > 0) {
        throw new ConflictException(
          `You still have ${balance.toFixed(2)} in earnings. Withdraw them first, then delete your account.`,
        );
      }
      if (balance < 0) {
        throw new ConflictException(
          'Your account has an outstanding balance. Please contact support to settle it before deleting your account.',
        );
      }
      await this.drivers.forceOffline(userId, null, 'account_deleted');
    }

    const now = new Date();
    await this.prisma.$transaction([
      this.prisma.trip.updateMany({
        where: { riderId: userId, status: TripStatus.scheduled },
        data: {
          status: TripStatus.cancelled,
          cancelledBy: 'rider',
          cancelReason: 'Account deleted',
        },
      }),
      this.prisma.refreshToken.deleteMany({ where: { userId } }),
      this.prisma.deviceToken.deleteMany({ where: { userId } }),
      this.prisma.savedPlace.deleteMany({ where: { userId } }),
      this.prisma.paymentMethod.deleteMany({ where: { userId } }),
      this.prisma.notification.deleteMany({ where: { userId } }),
      this.prisma.emergencyContact.deleteMany({ where: { userId } }),
      this.prisma.favoriteDriver.deleteMany({
        where: { OR: [{ riderId: userId }, { driverId: userId }] },
      }),
      this.prisma.driverProfile.updateMany({
        where: { userId },
        data: { licenseNo: null, status: 'offline' },
      }),
      this.prisma.user.update({
        where: { id: userId },
        data: {
          // Unique and ≤ 20 chars; frees the real number for a new sign-up.
          phone: `deleted:${userId.replace(/-/g, '').slice(0, 12)}`,
          email: null,
          fullName: null,
          photoUrl: null,
          isActive: false,
          deletedAt: now,
        },
      }),
    ]);

    this.logger.log(`account ${userId} deleted by its owner`);
    return { deleted: true };
  }
}
