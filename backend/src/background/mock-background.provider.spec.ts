import { MockBackgroundProvider } from './mock-background.provider';

describe('MockBackgroundProvider', () => {
  const provider = new MockBackgroundProvider();

  it('orders a pending report that resolves to clear on poll', async () => {
    const { candidateId } = await provider.createCandidate({
      firstName: 'Ada',
      lastName: 'Lovelace',
      email: 'ada@example.com',
    });
    expect(candidateId).toMatch(/^mock_cand_/);

    const { reportId, status } = await provider.createReport(candidateId);
    expect(status).toBe('pending');
    expect(reportId).toMatch(/^mock_rep_/);

    expect((await provider.getReport(reportId)).status).toBe('clear');
  });

  it('resolves to consider when the candidate email flags review', async () => {
    const { candidateId } = await provider.createCandidate({
      firstName: 'Flag',
      lastName: 'Ged',
      email: 'consider-me@example.com',
    });
    const { reportId } = await provider.createReport(candidateId);
    expect((await provider.getReport(reportId)).status).toBe('consider');
  });
});
