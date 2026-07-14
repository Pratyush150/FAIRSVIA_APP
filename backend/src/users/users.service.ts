import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';
import { UpdateUserDto } from './dto/update-user.dto';
import { CreatePlaceDto } from './dto/create-place.dto';
import { UpdatePlaceDto } from './dto/update-place.dto';

@Injectable()
export class UsersService {
  constructor(private readonly prisma: PrismaService) {}

  async findById(userId: string) {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user) {
      throw new NotFoundException('User not found.');
    }
    return this.toPublic(user);
  }

  async update(userId: string, dto: UpdateUserDto) {
    const user = await this.prisma.user.update({
      where: { id: userId },
      data: {
        fullName: dto.fullName,
        email: dto.email,
        photoUrl: dto.photoUrl,
      },
    });
    return this.toPublic(user);
  }

  async listPlaces(userId: string) {
    return this.prisma.savedPlace.findMany({
      where: { userId },
      orderBy: { label: 'asc' },
    });
  }

  async addPlace(userId: string, dto: CreatePlaceDto) {
    return this.prisma.savedPlace.create({
      data: {
        userId,
        label: dto.label,
        address: dto.address,
        lat: dto.lat,
        lng: dto.lng,
      },
    });
  }

  async updatePlace(userId: string, id: string, dto: UpdatePlaceDto) {
    await this.ownedPlace(userId, id);
    return this.prisma.savedPlace.update({
      where: { id },
      data: {
        label: dto.label,
        address: dto.address,
        lat: dto.lat,
        lng: dto.lng,
      },
    });
  }

  async removePlace(userId: string, id: string) {
    await this.ownedPlace(userId, id);
    await this.prisma.savedPlace.delete({ where: { id } });
    return { deleted: true };
  }

  /** Ensures the place exists and belongs to the user (404 otherwise). */
  private async ownedPlace(userId: string, id: string) {
    const place = await this.prisma.savedPlace.findUnique({ where: { id } });
    if (!place || place.userId !== userId) {
      throw new NotFoundException('Saved place not found.');
    }
    return place;
  }

  private toPublic(user: {
    id: string;
    phone: string;
    email: string | null;
    fullName: string | null;
    photoUrl: string | null;
    role: string;
    ratingAvg: unknown;
    ratingCount: number;
    isActive: boolean;
    createdAt: Date;
  }) {
    return {
      id: user.id,
      phone: user.phone,
      email: user.email,
      fullName: user.fullName,
      photoUrl: user.photoUrl,
      role: user.role,
      ratingAvg: Number(user.ratingAvg),
      ratingCount: user.ratingCount,
      isActive: user.isActive,
      createdAt: user.createdAt,
    };
  }
}
