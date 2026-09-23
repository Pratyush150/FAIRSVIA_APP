import { bullConnectionFromUrl } from './queue.module';

describe('bullConnectionFromUrl', () => {
  it('keeps the password of a protected Redis (production compose URL)', () => {
    expect(bullConnectionFromUrl('redis://:s3cr%40t@redis:6379')).toMatchObject({
      host: 'redis',
      port: 6379,
      password: 's3cr@t',
      db: 0,
    });
  });

  it('keeps a username and a db index', () => {
    expect(bullConnectionFromUrl('redis://ops:pw@cache.internal:6380/2')).toMatchObject({
      host: 'cache.internal',
      port: 6380,
      username: 'ops',
      password: 'pw',
      db: 2,
    });
  });

  it('works for the unauthenticated dev URL', () => {
    expect(bullConnectionFromUrl('redis://redis:6379')).toMatchObject({
      host: 'redis',
      password: undefined,
      db: 0,
    });
  });
});
