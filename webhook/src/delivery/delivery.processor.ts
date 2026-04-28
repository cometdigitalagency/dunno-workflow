import { Process, Processor, OnQueueFailed } from '@nestjs/bull';
import { Logger } from '@nestjs/common';
import { Job } from 'bull';
import axios from 'axios';
import * as crypto from 'crypto';
import { PrismaService } from '../prisma/prisma.service';
import { WEBHOOK_DELIVERY_QUEUE } from './delivery.constants';
import { DeliveryJobData } from '../events/events.service';

@Processor(WEBHOOK_DELIVERY_QUEUE)
export class DeliveryProcessor {
  private readonly logger = new Logger(DeliveryProcessor.name);

  constructor(private readonly prisma: PrismaService) {}

  @Process()
  async handleDelivery(job: Job<DeliveryJobData>): Promise<void> {
    const { webhookId, targetUrl, secret, event, payload } = job.data;
    const body = JSON.stringify(payload);
    const signature = this.buildSignature(secret, body);
    const startedAt = Date.now();

    let responseStatus: number | null = null;
    let responseBody: string | null = null;
    let success = false;

    try {
      const response = await axios.post(targetUrl, payload, {
        timeout: 5000,
        headers: {
          'Content-Type': 'application/json',
          'X-Webhook-Event': event,
          'X-Signature': `hmac-sha256=${signature}`,
        },
      });

      responseStatus = response.status;
      responseBody = typeof response.data === 'string'
        ? response.data
        : JSON.stringify(response.data);
      success = true;

      this.logger.log(
        `Delivered webhook ${webhookId} [event: ${event}] → ${responseStatus}`,
      );
    } catch (err: any) {
      responseStatus = err?.response?.status ?? null;
      responseBody = err?.response?.data
        ? typeof err.response.data === 'string'
          ? err.response.data
          : JSON.stringify(err.response.data)
        : err?.message ?? 'Unknown error';
      success = false;

      this.logger.warn(
        `Delivery failed for webhook ${webhookId} [attempt ${job.attemptsMade + 1}]: ${err.message}`,
      );

      // Re-throw so BullMQ retries the job
      throw err;
    } finally {
      const latency = Date.now() - startedAt;

      await this.prisma.webhookDelivery.create({
        data: {
          webhookId,
          event,
          payload: payload as any,
          responseStatus,
          responseBody,
          latency,
          retryCount: job.attemptsMade,
          success,
        },
      });
    }
  }

  @OnQueueFailed()
  onFailed(job: Job<DeliveryJobData>, err: Error): void {
    const { webhookId, event } = job.data;
    this.logger.error(
      `Job ${job.id} failed permanently for webhook ${webhookId} [event: ${event}]: ${err.message}`,
    );
  }

  private buildSignature(secret: string, body: string): string {
    return crypto.createHmac('sha256', secret).update(body).digest('hex');
  }
}
