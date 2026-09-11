import { DriversService } from './drivers.service';

/**
 * Onboarding re-verification: a verified driver who changes plate/licence must
 * drop back to pending unless DRIVER_AUTO_VERIFY (dev-only) is on.
 */
describe('DriversService.onboarding', () => {
  const dto = {
    vehicleMake: 'Toyota',
    vehicleModel: 'Prius',
    vehicleColor: 'white',
    plateNumber: 'ABC123',
    vehicleTier: 'economy',
    licenseNo: 'LIC-1',
  };

  function make(
    existing: { docsVerified: boolean; plateNumber: string | null; licenseNo: string | null } | null,
    autoVerify: boolean,
  ) {
    const prisma = {
      driverProfile: {
        findUnique: jest.fn().mockResolvedValue(existing),
        upsert: jest.fn(async ({ update }: { update: object }) => ({ ...update })),
      },
      user: { update: jest.fn().mockResolvedValue({}) },
    };
    const config = { get: jest.fn(() => autoVerify) };
    const svc = new DriversService(prisma as never, {} as never, config as never);
    return { svc, prisma };
  }

  const updateArg = (prisma: { driverProfile: { upsert: jest.Mock } }) =>
    prisma.driverProfile.upsert.mock.calls[0][0].update as Record<string, unknown>;
  const createArg = (prisma: { driverProfile: { upsert: jest.Mock } }) =>
    prisma.driverProfile.upsert.mock.calls[0][0].create as Record<string, unknown>;

  it('first onboarding is pending when auto-verify is off, approved when on', async () => {
    const off = make(null, false);
    await off.svc.onboarding('d1', dto);
    expect(createArg(off.prisma).docsVerified).toBe(false);

    const on = make(null, true);
    await on.svc.onboarding('d1', dto);
    expect(createArg(on.prisma).docsVerified).toBe(true);
  });

  it('a verified driver changing the plate is reset to unverified', async () => {
    const { svc, prisma } = make(
      { docsVerified: true, plateNumber: 'OLD999', licenseNo: 'LIC-1' },
      false,
    );
    await svc.onboarding('d1', dto);
    expect(updateArg(prisma).docsVerified).toBe(false);
  });

  it('a verified driver changing the licence is reset to unverified', async () => {
    const { svc, prisma } = make(
      { docsVerified: true, plateNumber: 'ABC123', licenseNo: 'LIC-0' },
      false,
    );
    await svc.onboarding('d1', dto);
    expect(updateArg(prisma).docsVerified).toBe(false);
  });

  it('re-submitting with the same identity fields keeps the verification', async () => {
    const { svc, prisma } = make(
      { docsVerified: true, plateNumber: 'ABC123', licenseNo: 'LIC-1' },
      false,
    );
    await svc.onboarding('d1', { ...dto, vehicleColor: 'black', vehicleModel: 'Camry' });
    expect(updateArg(prisma)).not.toHaveProperty('docsVerified');
  });

  it('an unverified driver changing the plate stays as-is (nothing to reset)', async () => {
    const { svc, prisma } = make(
      { docsVerified: false, plateNumber: 'OLD999', licenseNo: null },
      false,
    );
    await svc.onboarding('d1', dto);
    expect(updateArg(prisma)).not.toHaveProperty('docsVerified');
  });

  it('DRIVER_AUTO_VERIFY keeps a verified driver verified across a plate change', async () => {
    const { svc, prisma } = make(
      { docsVerified: true, plateNumber: 'OLD999', licenseNo: 'LIC-1' },
      true,
    );
    await svc.onboarding('d1', dto);
    expect(updateArg(prisma)).not.toHaveProperty('docsVerified');
  });
});
