import { Injectable, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';
import { PrismaService } from '../../common/prisma/prisma.service';
import { ActivityService } from '../../common/activity/activity.service';

export interface JwtPayload {
  sub: string;
  role: string;
}

export interface AuthUser {
  userId: string;
  role: string;
}

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor(
    config: ConfigService,
    private readonly prisma: PrismaService,
    private readonly activity: ActivityService,
  ) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey: config.get<{ accessSecret: string }>('jwt')!.accessSecret,
    });
  }

  // Load the user on every request so a demoted, deactivated, or deleted user
  // loses access immediately — the role is read FRESH from the DB, never trusted
  // from the (up-to-15-minute-stale) token claim. The return value is attached to
  // request.user. NB: this is a DB read per authenticated request; add a short
  // cache if it becomes a hot path.
  async validate(payload: JwtPayload): Promise<AuthUser> {
    const user = await this.prisma.user.findUnique({
      where: { id: payload.sub },
      select: { id: true, role: true, isActive: true },
    });
    if (!user || !user.isActive) {
      throw new UnauthorizedException();
    }
    this.activity.touch(user.id);
    return { userId: user.id, role: user.role };
  }
}
