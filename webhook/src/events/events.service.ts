import { Injectable, Logger } from '@nestjs/common';
import { InjectQueue } from '@nestjs/bull';
import { Queue } from 'bull';
import { PrismaService } from '../prisma/prisma.service';
import { WEBHOOK_DELIVERY_QUEUE } from '../delivery/delivery.constants';
import { Webhook } from '@prisma/client';

export interface DeliveryJobData {
  webhookId: string;
  targetUrl: string;
  secret: string;
  event: string;
  payload: object;
}

@Injectable()
export class EventsService {
  private readonly logger = new Logger(EventsService.name);

  constructor(
    private readonly prisma: PrismaService,
    @InjectQueue(WEBHOOK_DELIVERY_QUEUE) private readonly deliveryQueue: Queue,
  ) {}

  async emit(event: string, payload: object, webhooks?: Webhook[]): Promise<void> {
    const targets =
      webhooks ??
      (await this.prisma.webhook.findMany({
        where: {
          enabled: true,
          events: { has: event },
        },
      }));

    if (targets.length === 0) {
      this.logger.debug(`No webhooks subscribed to event: ${event}`);
      return;
    }

    for (const webhook of targets) {
      const jobData: DeliveryJobData = {
        webhookId: webhook.id,
        targetUrl: webhook.targetUrl,
        secret: webhook.secret,
        event,
        payload,
      };

      await this.deliveryQueue.add(jobData, {
        attempts: 4,
        backoff: {
          type: 'exponential',
          delay: 1000,
        },
        removeOnComplete: true,
        removeOnFail: false,
      });

      this.logger.log(`Queued delivery for webhook ${webhook.id} (event: ${event})`);
    }
  }
}
