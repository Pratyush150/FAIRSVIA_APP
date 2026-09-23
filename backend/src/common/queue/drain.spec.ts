import { drainAndClose } from './drain';

function fakeWorker(activeJobsMs: number) {
  return {
    name: 'dispatch',
    pause: jest.fn(() => new Promise<void>((r) => setTimeout(r, activeJobsMs))),
    close: jest.fn(async () => undefined),
  };
}

describe('drainAndClose', () => {
  it('closes gracefully when in-flight jobs finish in time', async () => {
    const w = fakeWorker(10);
    await drainAndClose(w as never, 200);
    expect(w.close).toHaveBeenCalledWith(false);
  });

  it('forces the close once the drain limit passes, without waiting for the job', async () => {
    const w = fakeWorker(60_000);
    const started = Date.now();
    await drainAndClose(w as never, 50);
    expect(Date.now() - started).toBeLessThan(1000);
    expect(w.close).toHaveBeenCalledWith(true);
  });

  it('is a no-op without a worker', async () => {
    await expect(drainAndClose(undefined, 10)).resolves.toBeUndefined();
  });
});
