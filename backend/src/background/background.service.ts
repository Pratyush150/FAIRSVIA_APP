import {
  BadRequestException,
  Inject,
  Injectable,
  Logger,
} from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';
import {
  BACKGROUND_CHECK_PROVIDER,
  BackgroundCheckProvider,
  BgcStatus,
} from './background-check.interface';

export interface BgcView {
  status: BgcStatus;
  candidateId: string | null;
  reportId: string | null;
  /** True once a `clear` result has verified the driver's documents. */
  docsVerified: boolean;
}

@Injectable()
export class BackgroundService {
  private readonly logger = new Logger('Background');

  constructor(
    private readonly prisma: PrismaService,
    @Inject(BACKGROUND_CHECK_PROVIDER)
    private readonly provider: BackgroundCheckProvider,
  ) {}

  /** Order a background check for the driver, persisting the vendor ids. */
  async initiate(userId: string, emailOverride?: string): Promise<BgcView> {
    const [user, profile] = await Promise.all([
      this.prisma.user.findUnique({ where: { id: userId } }),
      this.prisma.driverProfile.findUnique({ where: { userId } }),
    ]);
    if (!profile) {
      throw new BadRequestException('Complete driver onboarding first');
    }
    if (profile.bgcStatus === 'pending') {
      throw new BadRequestException('A background check is already in progress');
    }

    const { firstName, lastName } = splitName(user?.fullName);
    const email = emailOverride || user?.email || derivedEmail(user?.phone, userId);

    const { candidateId } = await this.provider.createCandidate({
      firstName,
      lastName,
      email,
      phone: user?.phone,
    });
    const { reportId, status } = await this.provider.createReport(candidateId);

    const updated = await this.prisma.driverProfile.update({
      where: { userId },
      data: {
        bgcCandidateId: candidateId,
        bgcReportId: reportId,
        bgcStatus: status,
      },
    });
    this.logger.log(`background check ordered for ${userId} (report ${reportId})`);
    return this.view(updated);
  }

  /** Poll the vendor for the latest result and reconcile local state. A `clear`
   *  result verifies the driver's documents so they can go online. */
  async refresh(userId: string): Promise<BgcView> {
    const profile = await this.prisma.driverProfile.findUnique({
      where: { userId },
    });
    if (!profile) {
      throw new BadRequestException('Complete driver onboarding first');
    }
    if (!profile.bgcReportId) {
      return this.view(profile);
    }
    const { status } = await this.provider.getReport(profile.bgcReportId);
    const updated = await this.prisma.driverProfile.update({
      where: { userId },
      data: {
        bgcStatus: status,
        // A clear check is what makes a non-auto-verified driver eligible.
        ...(status === 'clear' ? { docsVerified: true } : {}),
      },
    });
    return this.view(updated);
  }

  async status(userId: string): Promise<BgcView> {
    const profile = await this.prisma.driverProfile.findUnique({
      where: { userId },
    });
    if (!profile) {
      throw new BadRequestException('Complete driver onboarding first');
    }
    return this.view(profile);
  }

  private view(p: {
    bgcStatus: string;
    bgcCandidateId: string | null;
    bgcReportId: string | null;
    docsVerified: boolean;
  }): BgcView {
    return {
      status: p.bgcStatus as BgcStatus,
      candidateId: p.bgcCandidateId,
      reportId: p.bgcReportId,
      docsVerified: p.docsVerified,
    };
  }
}

function splitName(full?: string | null): { firstName: string; lastName: string } {
  const parts = (full ?? '').trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return { firstName: 'Driver', lastName: 'Applicant' };
  if (parts.length === 1) return { firstName: parts[0], lastName: 'Applicant' };
  return { firstName: parts[0], lastName: parts.slice(1).join(' ') };
}

/** A deterministic placeholder email when the driver has none on file. */
function derivedEmail(phone: string | undefined, userId: string): string {
  const digits = (phone ?? userId).replace(/\D/g, '') || userId.slice(0, 8);
  return `driver.${digits}@drivers.ubernav.example`;
}
