import { DemandMapService, toCells } from './demand-map.service';

describe('toCells', () => {
  it('maps grid rows to cell centres with intensity relative to the busiest', () => {
    const cells = toCells([
      { y: 1852, x: 7386, n: 8 },
      { y: 1853, x: 7385, n: 2 },
    ]);
    expect(cells).toEqual([
      { lat: 18.52, lng: 73.86, count: 8, intensity: 1 },
      { lat: 18.53, lng: 73.85, count: 2, intensity: 0.25 },
    ]);
  });

  it('is empty for no rows', () => {
    expect(toCells([])).toEqual([]);
  });
});

describe('DemandMapService.around', () => {
  function make(cached: string | null) {
    const client = {
      get: jest.fn().mockResolvedValue(cached),
      set: jest.fn().mockResolvedValue('OK'),
    };
    const prisma = {
      $queryRaw: jest.fn().mockResolvedValue([{ y: 1852, x: 7386, n: 3 }]),
    };
    return { svc: new DemandMapService(prisma as never, { client } as never), client, prisma };
  }

  it('queries once and caches the area result', async () => {
    const { svc, client, prisma } = make(null);
    const res = await svc.around(18.52, 73.86);
    expect(res.cells).toEqual([{ lat: 18.52, lng: 73.86, count: 3, intensity: 1 }]);
    expect(prisma.$queryRaw).toHaveBeenCalledTimes(1);
    expect(client.set).toHaveBeenCalledWith(
      expect.stringMatching(/^demand:map:/),
      JSON.stringify(res),
      'EX',
      60,
    );
  });

  it('serves a cached area without touching Postgres', async () => {
    const cached = { windowMinutes: 60, cells: [] };
    const { svc, prisma } = make(JSON.stringify(cached));
    await expect(svc.around(18.52, 73.86)).resolves.toEqual(cached);
    expect(prisma.$queryRaw).not.toHaveBeenCalled();
  });

  it('still answers when Redis is down', async () => {
    const { svc, client } = make(null);
    client.get.mockRejectedValue(new Error('down'));
    client.set.mockRejectedValue(new Error('down'));
    await expect(svc.around(18.52, 73.86)).resolves.toMatchObject({ cells: [{ count: 3 }] });
  });
});
