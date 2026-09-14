import { NotFoundException } from '@nestjs/common';
import { FavoritesService } from './favorites.service';

describe('FavoritesService.add', () => {
  function make(target: unknown) {
    const prisma = {
      user: { findUnique: jest.fn().mockResolvedValue(target) },
      favoriteDriver: { upsert: jest.fn().mockResolvedValue({}) },
    };
    return { svc: new FavoritesService(prisma as never), prisma };
  }

  it('404s when the target user does not exist (no dangling favourite row)', async () => {
    const { svc, prisma } = make(null);
    await expect(svc.add('rider-1', '00000000-0000-0000-0000-000000000000')).rejects.toBeInstanceOf(
      NotFoundException,
    );
    expect(prisma.favoriteDriver.upsert).not.toHaveBeenCalled();
  });

  it('404s when the target exists but is not a driver', async () => {
    const { svc } = make({ id: 'u2', driverProfile: null });
    await expect(svc.add('rider-1', 'u2')).rejects.toBeInstanceOf(NotFoundException);
  });

  it('upserts for a real driver', async () => {
    const { svc, prisma } = make({ id: 'd1', driverProfile: { userId: 'd1' } });
    await expect(svc.add('rider-1', 'd1')).resolves.toEqual({ favorited: true, driverId: 'd1' });
    expect(prisma.favoriteDriver.upsert).toHaveBeenCalledTimes(1);
  });
});
