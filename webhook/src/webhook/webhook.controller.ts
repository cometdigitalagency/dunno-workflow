import {
  Controller,
  Get,
  Post,
  Patch,
  Delete,
  Body,
  Param,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { WebhookService } from './webhook.service';
import { EventsService } from '../events/events.service';
import { CreateWebhookDto } from './dto/create-webhook.dto';
import { UpdateWebhookDto } from './dto/update-webhook.dto';
import { Webhook } from '@prisma/client';

@Controller('webhooks')
export class WebhookController {
  constructor(
    private readonly webhookService: WebhookService,
    private readonly eventsService: EventsService,
  ) {}

  @Post()
  create(@Body() dto: CreateWebhookDto): Promise<Webhook> {
    return this.webhookService.create(dto);
  }

  @Get()
  findAll(): Promise<Webhook[]> {
    return this.webhookService.findAll();
  }

  @Get(':id')
  findOne(@Param('id') id: string): Promise<Webhook> {
    return this.webhookService.findOne(id);
  }

  @Patch(':id')
  update(
    @Param('id') id: string,
    @Body() dto: UpdateWebhookDto,
  ): Promise<Webhook> {
    return this.webhookService.update(id, dto);
  }

  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  async remove(@Param('id') id: string): Promise<void> {
    return this.webhookService.remove(id);
  }

  @Patch(':id/enable')
  enable(@Param('id') id: string): Promise<Webhook> {
    return this.webhookService.enable(id);
  }

  @Patch(':id/disable')
  disable(@Param('id') id: string): Promise<Webhook> {
    return this.webhookService.disable(id);
  }

  @Post(':id/test')
  @HttpCode(HttpStatus.ACCEPTED)
  async test(@Param('id') id: string): Promise<{ message: string }> {
    const webhook = await this.webhookService.findOne(id);
    await this.eventsService.emit('webhook.test', {
      webhookId: webhook.id,
      timestamp: new Date().toISOString(),
      message: 'Manual test delivery triggered',
    }, [webhook]);
    return { message: 'Test delivery queued' };
  }
}
