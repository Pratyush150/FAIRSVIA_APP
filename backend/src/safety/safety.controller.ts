import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { UserRole } from '@prisma/client';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { AuthUser } from '../auth/strategies/jwt.strategy';
import { SafetyService } from './safety.service';
import { SosDto } from './dto/sos.dto';
import { CreateEmergencyContactDto } from './dto/emergency-contact.dto';
import { UpdateIncidentDto } from './dto/update-incident.dto';

@Controller()
@UseGuards(JwtAuthGuard)
export class SafetyController {
  constructor(private readonly safety: SafetyService) {}

  @Post('trips/:tripId/sos')
  sos(
    @CurrentUser() user: AuthUser,
    @Param('tripId', ParseUUIDPipe) tripId: string,
    @Body() dto: SosDto,
  ) {
    return this.safety.raiseSos(user.userId, tripId, dto);
  }

  /** Local emergency numbers for the SOS sheet (per launch country). */
  @Get('safety/config')
  safetyConfig() {
    return { emergencyNumbers: this.safety.emergencyNumbers() };
  }

  @Get('users/me/emergency-contacts')
  listContacts(@CurrentUser() user: AuthUser) {
    return this.safety.listContacts(user.userId);
  }

  @Post('users/me/emergency-contacts')
  addContact(@CurrentUser() user: AuthUser, @Body() dto: CreateEmergencyContactDto) {
    return this.safety.addContact(user.userId, dto.name, dto.phone);
  }

  @Delete('users/me/emergency-contacts/:id')
  removeContact(
    @CurrentUser() user: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    return this.safety.removeContact(user.userId, id);
  }

  @Get('admin/safety')
  @UseGuards(RolesGuard)
  @Roles(UserRole.admin)
  incidents(@Query('limit') limit?: string) {
    return this.safety.listIncidents(limit ? parseInt(limit, 10) || 50 : 50);
  }

  @Patch('admin/safety/:id')
  @UseGuards(RolesGuard)
  @Roles(UserRole.admin)
  updateIncident(
    @CurrentUser() user: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateIncidentDto,
  ) {
    return this.safety.updateIncident(user.userId, id, dto.status, dto.note);
  }
}
