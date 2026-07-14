import { BadRequestException, ForbiddenException, NotFoundException } from '@nestjs/common';
import { SupportService } from './support.service';

const OWNER = 'user-1';
const ADMIN = 'admin-1';

function makeTicket(over: Partial<Record<string, unknown>> = {}) {
  return {
    id: 't1',
    userId: OWNER,
    subject: 'Charged twice',
    category: 'payment',
    status: 'open',
    tripId: null,
    createdAt: new Date(),
    updatedAt: new Date(),
    messages: [
      {
        id: 'm1',
        authorId: OWNER,
        authorRole: 'user',
        body: 'hello',
        createdAt: new Date(),
      },
    ],
    ...over,
  };
}

describe('SupportService', () => {
  let prisma: {
    supportTicket: {
      create: jest.Mock;
      findMany: jest.Mock;
      findUnique: jest.Mock;
      update: jest.Mock;
    };
    supportMessage: { create: jest.Mock };
  };
  let service: SupportService;

  beforeEach(() => {
    prisma = {
      supportTicket: {
        create: jest.fn(),
        findMany: jest.fn(),
        findUnique: jest.fn(),
        update: jest.fn(),
      },
      supportMessage: { create: jest.fn() },
    };
    service = new SupportService(prisma as never);
  });

  it('creates a ticket with an opening message', async () => {
    prisma.supportTicket.create.mockResolvedValue(makeTicket());
    const res = await service.create(OWNER, {
      subject: 'Charged twice',
      message: 'billed two times',
      category: 'payment',
    });
    expect(prisma.supportTicket.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          userId: OWNER,
          messages: {
            create: { authorId: OWNER, authorRole: 'user', body: 'billed two times' },
          },
        }),
      }),
    );
    expect(res.id).toBe('t1');
  });

  it('blocks a non-owner, non-admin from reading a ticket', async () => {
    prisma.supportTicket.findUnique.mockResolvedValue(makeTicket());
    await expect(service.get('intruder', 't1', false)).rejects.toBeInstanceOf(
      ForbiddenException,
    );
  });

  it('lets an admin read any ticket', async () => {
    prisma.supportTicket.findUnique.mockResolvedValue(makeTicket());
    const res = await service.get(ADMIN, 't1', true);
    expect(res.messages).toHaveLength(1);
  });

  it('admin reply moves an open ticket to active', async () => {
    prisma.supportTicket.findUnique.mockResolvedValue(makeTicket({ status: 'open' }));
    prisma.supportMessage.create.mockResolvedValue({});
    prisma.supportTicket.update.mockResolvedValue({});
    await service.postMessage(ADMIN, 't1', { body: 'looking into it' }, true);
    expect(prisma.supportTicket.update).toHaveBeenCalledWith(
      expect.objectContaining({ data: { status: 'active' } }),
    );
  });

  it('user reply reopens a resolved ticket', async () => {
    prisma.supportTicket.findUnique.mockResolvedValue(makeTicket({ status: 'resolved' }));
    prisma.supportMessage.create.mockResolvedValue({});
    prisma.supportTicket.update.mockResolvedValue({});
    await service.postMessage(OWNER, 't1', { body: 'still broken' }, false);
    expect(prisma.supportTicket.update).toHaveBeenCalledWith(
      expect.objectContaining({ data: { status: 'active' } }),
    );
  });

  it('rejects posting to a closed ticket', async () => {
    prisma.supportTicket.findUnique.mockResolvedValue(makeTicket({ status: 'closed' }));
    await expect(
      service.postMessage(OWNER, 't1', { body: 'hi' }, false),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects an invalid status update', async () => {
    await expect(
      service.updateStatus('t1', { status: 'bogus' }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('surfaces a not-found ticket on status update', async () => {
    prisma.supportTicket.update.mockRejectedValue(new Error('no row'));
    await expect(
      service.updateStatus('missing', { status: 'closed' }),
    ).rejects.toBeInstanceOf(NotFoundException);
  });
});
