import {
  Injectable,
  NotFoundException,
  BadRequestException,
} from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { CreateWebhookDto } from './dto/create-webhook.dto';
import { UpdateWebhookDto } from './dto/update-webhook.dto';
import { Webhook } from '@prisma/client';

@Injectable()
export class WebhookService {
  constructor(private readonly prisma: PrismaService) {}

  async create(dto: CreateWebhookDto): Promise<Webhook> {
    const events = this.deduplicateEvents(dto.events);
    return this.prisma.webhook.create({
      data: {
        name: dto.name,
        targetUrl: dto.targetUrl,
        secret: dto.secret,
        enabled: dto.enabled ?? true,
        events,
      },
    });
  }

  async findAll(): Promise<Webhook[]> {
    return this.prisma.webhook.findMany({ orderBy: { createdAt: 'desc' } });
  }

  async findOne(id: string): Promise<Webhook> {
    const webhook = await this.prisma.webhook.findUnique({ where: { id } });
    if (!webhook) throw new NotFoundException(`Webhook ${id} not found`);
    return webhook;
  }

  async update(id: string, dto: UpdateWebhookDto): Promise<Webhook> {
    await this.findOne(id);
    const data: Partial<Webhook> = { ...dto };
    if (dto.events) {
      (data as any).events = this.deduplicateEvents(dto.events as string[]);
    }
    return this.prisma.webhook.update({ where: { id }, data });
  }

  async remove(id: string): Promise<void> {
    await this.findOne(id);
    await this.prisma.webhook.delete({ where: { id } });
  }

  async enable(id: string): Promise<Webhook> {
    await this.findOne(id);
    return this.prisma.webhook.update({ where: { id }, data: { enabled: true } });
  }

  async disable(id: string): Promise<Webhook> {
    await this.findOne(id);
    return this.prisma.webhook.update({ where: { id }, data: { enabled: false } });
  }

  private deduplicateEvents(events: string[]): string[] {
    return [...new Set(events)];
  }
}
