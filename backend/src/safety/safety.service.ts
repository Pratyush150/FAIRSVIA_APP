import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Inject,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../common/prisma/prisma.service';
import { MetricsService } from '../common/metrics/metrics.service';
import {
  SMS_PROVIDER,
  SmsProvider,
} from '../auth/sms/sms-provider.interface';
import { BRAND_NAME } from '../common/brand';

interface SosInput {
  lat?: number;
  lng?: number;
}

export const MAX_EMERGENCY_CONTACTS = 3;
/** A second press within this window returns the same incident and does not
 *  text the contacts again — panic double-taps must not spam them. */
export const SOS_REPEAT_WINDOW_MS = 2 * 60 * 1000;

type IncidentStatus = 'open' | 'acknowledged' | 'resolved';

/**
 * SOS during a trip. A press:
 *  - opens a SafetyIncident that ops must acknowledge and resolve (admin
 *    console Safety tab), plus an audit trip_event;
 *  - texts every emergency contact the user saved, with the car, the plate,
 *    the other party's name and a map link to where they are;
 *  - increments `sos_alerts_total`, which the SosRaised alert pages on.
 * It never tells the other party on the trip.
 */
@Injectable()
export class SafetyService {
  private readonly logger = new Logger('Safety');

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
    private readonly metrics: MetricsService,
    @Inject(SMS_PROVIDER) private readonly sms: SmsProvider,
  ) {}

  emergencyNumbers(): { label: string; number: string }[] {
    return this.config.get('emergencyNumbers') ?? [];
  }

  // --- Emergency contacts -------------------------------------------------

  listContacts(userId: string) {
    return this.prisma.emergencyContact.findMany({
      where: { userId },
      orderBy: { createdAt: 'asc' },
      select: { id: true, name: true, phone: true },
    });
  }

  async addContact(userId: string, name: string, phone: string) {
    const count = await this.prisma.emergencyContact.count({ where: { userId } });
    if (count >= MAX_EMERGENCY_CONTACTS) {
      throw new BadRequestException(
        `You can save up to ${MAX_EMERGENCY_CONTACTS} emergency contacts. Remove one to add another.`,
      );
    }
    const me = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { phone: true },
    });
    if (me?.phone === phone) {
      throw new BadRequestException(
        "That's your own number. Add someone who can help you.",
      );
    }
    try {
      return await this.prisma.emergencyContact.create({
        data: { userId, name: name.trim(), phone },
        select: { id: true, name: true, phone: true },
      });
    } catch (e) {
      if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === 'P2002') {
        throw new ConflictException('That number is already one of your emergency contacts.');
      }
      throw e;
    }
  }

  async removeContact(userId: string, id: string) {
    const res = await this.prisma.emergencyContact.deleteMany({ where: { id, userId } });
    if (res.count === 0) throw new NotFoundException('Contact not found');
    return { removed: true };
  }

  // --- SOS -----------------------------------------------------------------

  async raiseSos(userId: string, tripId: string, input: SosInput) {
    const trip = await this.prisma.trip.findUnique({
      where: { id: tripId },
      include: {
        rider: { select: { fullName: true } },
        driver: {
          select: {
            fullName: true,
            driverProfile: {
              select: {
                vehicleMake: true,
                vehicleModel: true,
                vehicleColor: true,
                plateNumber: true,
              },
            },
          },
        },
      },
    });
    if (!trip) throw new NotFoundException('Trip not found');
    const role =
      userId === trip.riderId ? 'rider' : userId === trip.driverId ? 'driver' : null;
    if (!role) throw new ForbiddenException('Not a participant of this trip');

    const recent = await this.prisma.safetyIncident.findFirst({
      where: {
        tripId,
        raisedById: userId,
        status: { not: 'resolved' },
        createdAt: { gt: new Date(Date.now() - SOS_REPEAT_WINDOW_MS) },
      },
      orderBy: { createdAt: 'desc' },
    });
    if (recent) {
      if (input.lat != null && input.lng != null) {
        await this.prisma.safetyIncident.update({
          where: { id: recent.id },
          data: { lat: input.lat, lng: input.lng },
        });
      }
      return this.result(recent.id, recent.contactsNotified, recent.contactsTotal, true);
    }

    const contacts = await this.listContacts(userId);
    const incident = await this.prisma.safetyIncident.create({
      data: {
        tripId,
        raisedById: userId,
        raisedByRole: role,
        lat: input.lat ?? null,
        lng: input.lng ?? null,
        contactsTotal: contacts.length,
      },
    });
    await this.prisma.tripEvent.create({
      data: {
        tripId,
        fromStatus: trip.status,
        toStatus: trip.status, // SOS doesn't change trip state; audit only.
        actor: role,
        meta: {
          event: 'sos',
          incidentId: incident.id,
          lat: input.lat ?? null,
          lng: input.lng ?? null,
          at: incident.createdAt.toISOString(),
        },
      },
    });
    this.metrics.sosRaised(role);
    this.logger.warn(
      `SOS ${incident.id} raised by ${role} ${userId} on trip ${tripId} ` +
        `@ ${input.lat ?? '?'},${input.lng ?? '?'} (status ${trip.status})`,
    );

    const message = this.contactMessage(role, trip, input);
    const sent = await Promise.all(
      contacts.map((c) =>
        this.sms.sendMessage(c.phone, message).then(
          () => true,
          (e: unknown) => {
            this.logger.error(
              `SOS ${incident.id}: SMS to contact ${c.id} failed: ${e instanceof Error ? e.message : e}`,
            );
            return false;
          },
        ),
      ),
    );
    const notified = sent.filter(Boolean).length;
    if (notified > 0) {
      await this.prisma.safetyIncident.update({
        where: { id: incident.id },
        data: { contactsNotified: notified },
      });
    }
    return this.result(incident.id, notified, contacts.length, false);
  }

  private result(incidentId: string, notified: number, total: number, repeat: boolean) {
    return {
      ok: true,
      incidentId,
      contactsNotified: notified,
      contactsTotal: total,
      repeat,
      emergencyNumbers: this.emergencyNumbers(),
    };
  }

  private contactMessage(
    role: 'rider' | 'driver',
    trip: {
      rider: { fullName: string | null } | null;
      driver: {
        fullName: string | null;
        driverProfile: {
          vehicleMake: string | null;
          vehicleModel: string | null;
          vehicleColor: string | null;
          plateNumber: string | null;
        } | null;
      } | null;
      pickupAddr: string | null;
      dropoffAddr: string | null;
    },
    input: SosInput,
  ): string {
    const me = (role === 'rider' ? trip.rider?.fullName : trip.driver?.fullName) || 'Your contact';
    const lines = [`${BRAND_NAME} SOS: ${me} pressed the emergency button during a ride.`];
    if (input.lat != null && input.lng != null) {
      lines.push(`Location: https://maps.google.com/?q=${input.lat.toFixed(5)},${input.lng.toFixed(5)}`);
    }
    const v = trip.driver?.driverProfile;
    if (v) {
      const car = [v.vehicleColor, v.vehicleMake, v.vehicleModel].filter(Boolean).join(' ');
      if (car || v.plateNumber) {
        lines.push(`Car: ${car}${v.plateNumber ? `, plate ${v.plateNumber}` : ''}`.trim());
      }
    }
    const other = role === 'rider' ? trip.driver?.fullName : trip.rider?.fullName;
    if (other) lines.push(`${role === 'rider' ? 'Driver' : 'Rider'}: ${other}`);
    if (trip.dropoffAddr) lines.push(`Going to: ${trip.dropoffAddr}`);
    const numbers = this.emergencyNumbers();
    if (numbers.length > 0) {
      lines.push(`If you can't reach them, call ${numbers.map((n) => `${n.label.toLowerCase()} ${n.number}`).join(' or ')}.`);
    }
    return lines.join('\n');
  }

  // --- Admin ---------------------------------------------------------------

  /** Incidents for the admin Safety tab: unresolved first, newest first. */
  async listIncidents(limit = 50) {
    const rows = await this.prisma.safetyIncident.findMany({
      orderBy: [{ createdAt: 'desc' }],
      take: Math.min(Math.max(limit, 1), 200),
      include: {
        trip: {
          select: {
            status: true,
            pickupAddr: true,
            dropoffAddr: true,
            rider: { select: { id: true, fullName: true, phone: true } },
            driver: {
              select: {
                id: true,
                fullName: true,
                phone: true,
                driverProfile: { select: { plateNumber: true } },
              },
            },
          },
        },
      },
    });
    const rank = (s: string) => (s === 'open' ? 0 : s === 'acknowledged' ? 1 : 2);
    return rows
      .sort((a, b) => rank(a.status) - rank(b.status))
      .map((r) => ({
        id: r.id,
        tripId: r.tripId,
        status: r.status,
        raisedByRole: r.raisedByRole,
        lat: r.lat,
        lng: r.lng,
        contactsNotified: r.contactsNotified,
        contactsTotal: r.contactsTotal,
        createdAt: r.createdAt,
        acknowledgedAt: r.acknowledgedAt,
        resolvedAt: r.resolvedAt,
        note: r.note,
        trip: {
          status: r.trip.status,
          pickup: r.trip.pickupAddr,
          dropoff: r.trip.dropoffAddr,
          rider: r.trip.rider,
          driver: r.trip.driver && {
            id: r.trip.driver.id,
            fullName: r.trip.driver.fullName,
            phone: r.trip.driver.phone,
            plate: r.trip.driver.driverProfile?.plateNumber ?? null,
          },
        },
      }));
  }

  async updateIncident(
    adminId: string,
    id: string,
    status: Exclude<IncidentStatus, 'open'>,
    note?: string,
  ) {
    const incident = await this.prisma.safetyIncident.findUnique({ where: { id } });
    if (!incident) throw new NotFoundException('Incident not found');
    if (incident.status === 'resolved') {
      throw new BadRequestException('This incident is already resolved.');
    }
    const now = new Date();
    return this.prisma.safetyIncident.update({
      where: { id },
      data: {
        status,
        note: note ?? incident.note,
        // Resolving an unacknowledged incident acknowledges it too.
        acknowledgedById: incident.acknowledgedById ?? adminId,
        acknowledgedAt: incident.acknowledgedAt ?? now,
        resolvedAt: status === 'resolved' ? now : null,
      },
    });
  }
}
