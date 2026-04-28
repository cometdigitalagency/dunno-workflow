import { Test, TestingModule } from '@nestjs/testing';
import { getQueueToken } from '@nestjs/bull';
import { EventsService } from './events.service';
import { PrismaService } from '../prisma/prisma.service';
import { WEBHOOK_DELIVERY_QUEUE } from '../delivery/delivery.constants';
import { WebhookEvent } from '../common/webhook-event.enum';

const mockQueue = {
  add: jest.fn(),
};

const mockPrisma = {
  webhook: {
    findMany: jest.fn(),
  },
};

describe('EventsService', () => {
  let service: EventsService;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        EventsService,
        { provide: PrismaService, useValue: mockPrisma },
        {
          provide: getQueueToken(WEBHOOK_DELIVERY_QUEUE),
          useValue: mockQueue,
        },
      ],
    }).compile();

    service = module.get<EventsService>(EventsService);
    jest.clearAllMocks();
  });

  const enabledWebhook = {
    id: 'webhook-id-1',
    name: 'Enabled Webhook',
    targetUrl: 'https://example.com/webhook1',
    secret: 'secret1234567890',
    enabled: true,
    events: [WebhookEvent.TASK_CREATED],
    createdAt: new Date(),
    updatedAt: new Date(),
  };

  const enabledWebhook2 = {
    id: 'webhook-id-3',
    name: 'Another Enabled Webhook',
    targetUrl: 'https://example.com/webhook3',
    secret: 'anothersecret5678',
    enabled: true,
    events: [WebhookEvent.TASK_CREATED],
    createdAt: new Date(),
    updatedAt: new Date(),
  };

  describe('emit without explicit webhooks', () => {
    it('should query DB for enabled webhooks subscribed to the event', async () => {
      mockPrisma.webhook.findMany.mockResolvedValue([enabledWebhook]);

      await service.emit(WebhookEvent.TASK_CREATED, { taskId: '123' });

      expect(mockPrisma.webhook.findMany).toHaveBeenCalledWith({
        where: {
          enabled: true,
          events: { has: WebhookEvent.TASK_CREATED },
        },
      });
    });

    it('should enqueue one job per enabled subscribed webhook', async () => {
      mockPrisma.webhook.findMany.mockResolvedValue([enabledWebhook]);

      await service.emit(WebhookEvent.TASK_CREATED, { taskId: '123' });

      expect(mockQueue.add).toHaveBeenCalledTimes(1);
      expect(mockQueue.add).toHaveBeenCalledWith(
        expect.objectContaining({
          webhookId: enabledWebhook.id,
          targetUrl: enabledWebhook.targetUrl,
          secret: enabledWebhook.secret,
          event: WebhookEvent.TASK_CREATED,
          payload: { taskId: '123' },
        }),
        expect.objectContaining({
          attempts: 4,
          backoff: { type: 'exponential', delay: 1000 },
          removeOnComplete: true,
        }),
      );
    });

    it('should NOT enqueue any jobs when no webhooks match the event', async () => {
      mockPrisma.webhook.findMany.mockResolvedValue([]);

      await service.emit(WebhookEvent.TASK_CREATED, { taskId: '123' });

      expect(mockQueue.add).not.toHaveBeenCalled();
    });

    it('should enqueue one job per webhook when multiple are subscribed', async () => {
      mockPrisma.webhook.findMany.mockResolvedValue([enabledWebhook, enabledWebhook2]);

      await service.emit(WebhookEvent.TASK_CREATED, { taskId: '123' });

      expect(mockQueue.add).toHaveBeenCalledTimes(2);
    });

    it('should filter by correct event when multiple event types exist', async () => {
      mockPrisma.webhook.findMany.mockResolvedValue([]);

      await service.emit(WebhookEvent.AGENT_ERROR, { error: 'crash' });

      expect(mockPrisma.webhook.findMany).toHaveBeenCalledWith({
        where: {
          enabled: true,
          events: { has: WebhookEvent.AGENT_ERROR },
        },
      });
    });
  });

  describe('emit with explicit webhooks array (test endpoint)', () => {
    it('should skip DB query and use provided webhooks', async () => {
      await service.emit(WebhookEvent.TASK_CREATED, { taskId: '123' }, [
        enabledWebhook,
      ]);

      expect(mockPrisma.webhook.findMany).not.toHaveBeenCalled();
      expect(mockQueue.add).toHaveBeenCalledTimes(1);
    });

    it('should enqueue jobs for all webhooks in the provided array', async () => {
      await service.emit(
        WebhookEvent.TASK_CREATED,
        { taskId: '123' },
        [enabledWebhook, enabledWebhook2],
      );

      expect(mockQueue.add).toHaveBeenCalledTimes(2);
    });

    it('should enqueue zero jobs when provided empty array', async () => {
      await service.emit(WebhookEvent.TASK_CREATED, { taskId: '123' }, []);

      expect(mockQueue.add).not.toHaveBeenCalled();
    });
  });

  describe('disabled webhook behavior', () => {
    it('should NOT queue jobs for disabled webhooks (filtered by DB query)', async () => {
      // DB query includes enabled: true, so disabled webhooks are never returned
      mockPrisma.webhook.findMany.mockResolvedValue([]);

      await service.emit(WebhookEvent.TASK_CREATED, { taskId: '123' });

      expect(mockQueue.add).not.toHaveBeenCalled();
    });
  });
});
