import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';
import { CreateTicketDto } from './dto/create-ticket.dto';
import { PostMessageDto } from './dto/post-message.dto';
import { UpdateTicketDto } from './dto/update-ticket.dto';

const VALID_STATUSES = ['open', 'active', 'resolved', 'closed'];

@Injectable()
export class SupportService {
  constructor(private readonly prisma: PrismaService) {}

  /** Create a ticket with its opening message. */
  async create(userId: string, dto: CreateTicketDto) {
    const ticket = await this.prisma.supportTicket.create({
      data: {
        userId,
        subject: dto.subject,
        category: dto.category ?? 'other',
        tripId: dto.tripId ?? null,
        messages: {
          create: { authorId: userId, authorRole: 'user', body: dto.message },
        },
      },
      include: { messages: true },
    });
    return this.serialize(ticket);
  }

  /** The signed-in user's tickets, newest first. */
  async listMine(userId: string) {
    const tickets = await this.prisma.supportTicket.findMany({
      where: { userId },
      orderBy: { updatedAt: 'desc' },
    });
    return tickets.map((t) => this.serialize(t));
  }

  /** A single ticket with its full thread (owner or admin). */
  async get(userId: string, ticketId: string, isAdmin: boolean) {
    const ticket = await this.prisma.supportTicket.findUnique({
      where: { id: ticketId },
      include: { messages: { orderBy: { createdAt: 'asc' } } },
    });
    if (!ticket) throw new NotFoundException('Ticket not found');
    if (!isAdmin && ticket.userId !== userId) {
      throw new ForbiddenException('Not your ticket');
    }
    return this.serialize(ticket, true);
  }

  /** Append a message to a ticket (owner or admin). Reopens a resolved ticket. */
  async postMessage(
    userId: string,
    ticketId: string,
    dto: PostMessageDto,
    isAdmin: boolean,
  ) {
    const ticket = await this.prisma.supportTicket.findUnique({
      where: { id: ticketId },
    });
    if (!ticket) throw new NotFoundException('Ticket not found');
    if (!isAdmin && ticket.userId !== userId) {
      throw new ForbiddenException('Not your ticket');
    }
    if (ticket.status === 'closed') {
      throw new BadRequestException('This ticket is closed');
    }
    await this.prisma.supportMessage.create({
      data: {
        ticketId,
        authorId: userId,
        authorRole: isAdmin ? 'admin' : 'user',
        body: dto.body,
      },
    });
    // An admin reply moves it to active; a user reply reopens a resolved ticket.
    const nextStatus = isAdmin
      ? 'active'
      : ticket.status === 'resolved'
        ? 'active'
        : ticket.status;
    await this.prisma.supportTicket.update({
      where: { id: ticketId },
      data: { status: nextStatus },
    });
    return this.get(userId, ticketId, isAdmin);
  }

  // --- Admin ---

  async listAll(status?: string) {
    const tickets = await this.prisma.supportTicket.findMany({
      where: status ? { status } : {},
      orderBy: { updatedAt: 'desc' },
      take: 200,
    });
    return tickets.map((t) => this.serialize(t));
  }

  async updateStatus(ticketId: string, dto: UpdateTicketDto) {
    if (!VALID_STATUSES.includes(dto.status)) {
      throw new BadRequestException('Invalid status');
    }
    const ticket = await this.prisma.supportTicket
      .update({ where: { id: ticketId }, data: { status: dto.status } })
      .catch(() => null);
    if (!ticket) throw new NotFoundException('Ticket not found');
    return this.serialize(ticket);
  }

  private serialize(
    t: {
      id: string;
      userId: string;
      subject: string;
      category: string;
      status: string;
      tripId: string | null;
      createdAt: Date;
      updatedAt: Date;
      messages?: {
        id: string;
        authorId: string;
        authorRole: string;
        body: string;
        createdAt: Date;
      }[];
    },
    withMessages = false,
  ) {
    return {
      id: t.id,
      userId: t.userId,
      subject: t.subject,
      category: t.category,
      status: t.status,
      tripId: t.tripId,
      createdAt: t.createdAt,
      updatedAt: t.updatedAt,
      ...(withMessages && t.messages
        ? {
            messages: t.messages.map((m) => ({
              id: m.id,
              authorRole: m.authorRole,
              body: m.body,
              createdAt: m.createdAt,
            })),
          }
        : {}),
    };
  }
}
