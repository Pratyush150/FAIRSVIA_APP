import {
  Injectable,
  Inject,
  Logger,
  BadRequestException,
  UnauthorizedException,
  HttpException,
  HttpStatus,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { UserRole } from '@prisma/client';
import { createHash, randomInt, randomUUID } from 'node:crypto';
import { PrismaService } from '../common/prisma/prisma.service';
import { RedisService } from '../common/redis/redis.service';
import { SMS_PROVIDER, SmsProvider } from './sms/sms-provider.interface';

export interface AuthTokens {
  accessToken: string;
  refreshToken: string;
}

export interface AuthResult extends AuthTokens {
  user: PublicUser;
}

export interface PublicUser {
  id: string;
  phone: string;
  email: string | null;
  fullName: string | null;
  photoUrl: string | null;
  role: string;
  ratingAvg: number;
  ratingCount: number;
}

@Injectable()
export class AuthService {
  private readonly logger = new Logger(AuthService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
    @Inject(SMS_PROVIDER) private readonly sms: SmsProvider,
  ) {}

  private sha256(input: string): string {
    return createHash('sha256').update(input).digest('hex');
  }

  private otpKey(phone: string): string {
    return `otp:${phone}`;
  }

  private otpAttemptsKey(phone: string): string {
    return `otp:attempts:${phone}`;
  }

  private otpRateKey(phone: string): string {
    return `otp:rate:${phone}`;
  }

  /** Step 1: generate + "send" an OTP. Rate-limited per phone. */
  async requestOtp(phone: string): Promise<{ requestId: string; devCode?: string }> {
    const otpCfg = this.config.get<{ ttlSeconds: number; length: number }>('otp')!;

    // Rate limit: at most 5 requests per OTP TTL window per phone.
    const attempts = await this.redis.incrWithTtl(this.otpRateKey(phone), otpCfg.ttlSeconds);
    if (attempts > 5) {
      throw new HttpException(
        'Too many OTP requests. Try again later.',
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }

    const code = this.generateNumericCode(otpCfg.length);
    await this.redis.setEx(this.otpKey(phone), this.sha256(code), otpCfg.ttlSeconds);
    await this.redis.del(this.otpAttemptsKey(phone));

    await this.sms.sendOtp(phone, code);

    const requestId = randomUUID();
    const isDev = this.config.get<string>('nodeEnv') !== 'production';
    // In dev we echo the code back so you can test without reading logs.
    return isDev ? { requestId, devCode: code } : { requestId };
  }

  private generateNumericCode(length: number): string {
    let code = '';
    for (let i = 0; i < length; i++) {
      code += randomInt(0, 10).toString();
    }
    return code;
  }

  /** Step 2: verify the OTP; create the user on first login; issue tokens. */
  async verifyOtp(phone: string, code: string): Promise<AuthResult> {
    const otpCfg = this.config.get<{ maxAttempts: number }>('otp')!;
    const storedHash = await this.redis.get(this.otpKey(phone));
    if (!storedHash) {
      throw new BadRequestException('OTP expired or not requested. Request a new code.');
    }

    const attempts = await this.redis.incrWithTtl(this.otpAttemptsKey(phone), 300);
    if (attempts > otpCfg.maxAttempts) {
      await this.redis.del(this.otpKey(phone));
      throw new HttpException(
        'Too many incorrect attempts. Request a new code.',
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }

    if (this.sha256(code) !== storedHash) {
      throw new BadRequestException('Incorrect code.');
    }

    // Success: burn the OTP.
    await this.redis.del(this.otpKey(phone));
    await this.redis.del(this.otpAttemptsKey(phone));

    // Bootstrap: phones listed in ADMIN_PHONES get (and keep) the admin role.
    const adminPhones = this.config.get<string[]>('adminPhones') ?? [];
    const isAdmin = adminPhones.includes(phone);
    const user = await this.prisma.user.upsert({
      where: { phone },
      create: { phone, role: isAdmin ? UserRole.admin : undefined },
      update: isAdmin ? { role: UserRole.admin } : {},
    });

    const tokens = await this.issueTokens(user.id, user.role);
    return { ...tokens, user: this.toPublicUser(user) };
  }

  /** Rotate a refresh token: verify, revoke old, issue a new pair. */
  async refresh(refreshToken: string): Promise<AuthTokens> {
    const jwtCfg = this.config.get<{ refreshSecret: string }>('jwt')!;
    let payload: { sub: string; jti: string };
    try {
      payload = await this.jwt.verifyAsync(refreshToken, { secret: jwtCfg.refreshSecret });
    } catch {
      throw new UnauthorizedException('Invalid refresh token.');
    }

    const tokenHash = this.sha256(refreshToken);
    const record = await this.prisma.refreshToken.findFirst({
      where: { tokenHash, userId: payload.sub },
    });
    if (!record || record.revoked || record.expiresAt < new Date()) {
      throw new UnauthorizedException('Refresh token expired or revoked.');
    }

    // Rotation: revoke the used token before issuing a new one.
    await this.prisma.refreshToken.update({
      where: { id: record.id },
      data: { revoked: true },
    });

    const user = await this.prisma.user.findUniqueOrThrow({ where: { id: payload.sub } });
    return this.issueTokens(user.id, user.role);
  }

  /** Sign an access JWT and a rotating refresh JWT (hash persisted for revocation). */
  private async issueTokens(userId: string, role: string): Promise<AuthTokens> {
    const jwtCfg = this.config.get<{
      accessSecret: string;
      refreshSecret: string;
      accessTtl: string;
      refreshTtlDays: number;
    }>('jwt')!;

    const jti = randomUUID();
    // expiresIn accepts a vercel/ms string ('15m', '30d') or seconds; cast the
    // config strings to satisfy @nestjs/jwt's narrow StringValue typing.
    const accessToken = await this.jwt.signAsync(
      { sub: userId, role },
      { secret: jwtCfg.accessSecret, expiresIn: jwtCfg.accessTtl as unknown as number },
    );
    const refreshToken = await this.jwt.signAsync(
      { sub: userId, jti },
      {
        secret: jwtCfg.refreshSecret,
        expiresIn: `${jwtCfg.refreshTtlDays}d` as unknown as number,
      },
    );

    const expiresAt = new Date(Date.now() + jwtCfg.refreshTtlDays * 24 * 60 * 60 * 1000);
    await this.prisma.refreshToken.create({
      data: { userId, tokenHash: this.sha256(refreshToken), expiresAt },
    });

    return { accessToken, refreshToken };
  }

  private toPublicUser(user: {
    id: string;
    phone: string;
    email: string | null;
    fullName: string | null;
    photoUrl: string | null;
    role: string;
    ratingAvg: unknown;
    ratingCount: number;
  }): PublicUser {
    return {
      id: user.id,
      phone: user.phone,
      email: user.email,
      fullName: user.fullName,
      photoUrl: user.photoUrl,
      role: user.role,
      ratingAvg: Number(user.ratingAvg),
      ratingCount: user.ratingCount,
    };
  }
}
