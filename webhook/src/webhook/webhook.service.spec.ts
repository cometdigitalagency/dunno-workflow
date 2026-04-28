import { Test, TestingModule } from '@nestjs/testing';
import { NotFoundException } from '@nestjs/common';
import { WebhookService } from './webhook.service';
import { PrismaService } from '../prisma/prisma.service';
import { WebhookEvent } from '../common/webhook-event.enum';

const mockPrisma = {
  webhook: {
    create: jest.fn(),
    findMany: jest.fn(),
    findUnique: jest.fn(),
    update: jest.fn(),
    delete: jest.fn(),
  },
};

describe('WebhookService', () => {
  let service: WebhookService;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        WebhookService,
        { provide: PrismaService, useValue: mockPrisma },
      ],
    }).compile();

    service = module.get<WebhookService>(WebhookService);
    jest.clearAllMocks();
  });

  const baseWebhook = {
    id: 'webhook-id',
    name: 'Test Webhook',
    targetUrl: 'https://example.com/webhook',
    secret: 'supersecretkey1234',
    enabled: true,
    events: [WebhookEvent.TASK_CREATED],
    createdAt: new Date(),
    updatedAt: new Date(),
  };

  describe('create', () => {
    it('should create a webhook and return it', async () => {
      mockPrisma.webhook.create.mockResolvedValue(baseWebhook);
      const dto = {
        name: 'Test Webhook',
        targetUrl: 'https://example.com/webhook',
        secret: 'supersecretkey1234',
        events: [WebhookEvent.TASK_CREATED],
      };

      const result = await service.create(dto);

      expect(mockPrisma.webhook.create).toHaveBeenCalledWith({
        data: {
          name: dto.name,
          targetUrl: dto.targetUrl,
          secret: dto.secret,
          enabled: true,
          events: [WebhookEvent.TASK_CREATED],
        },
      });
      expect(result).toEqual(baseWebhook);
    });

    it('should deduplicate events on create', async () => {
      mockPrisma.webhook.create.mockResolvedValue(baseWebhook);
      const dto = {
        name: 'Test Webhook',
        targetUrl: 'https://example.com/webhook',
        secret: 'supersecretkey1234',
        events: [WebhookEvent.TASK_CREATED, WebhookEvent.TASK_CREATED],
      };

      await service.create(dto);

      expect(mockPrisma.webhook.create).toHaveBeenCalledWith({
        data: expect.objectContaining({
          events: [WebhookEvent.TASK_CREATED],
        }),
      });
    });

    it('should default enabled to true when not specified', async () => {
      mockPrisma.webhook.create.mockResolvedValue(baseWebhook);
      const dto = {
        name: 'Test Webhook',
        targetUrl: 'https://example.com/webhook',
        secret: 'supersecretkey1234',
        events: [WebhookEvent.TASK_CREATED],
      };

      await service.create(dto);

      expect(mockPrisma.webhook.create).toHaveBeenCalledWith({
        data: expect.objectContaining({ enabled: true }),
      });
    });

    it('should support multiple distinct events', async () => {
      const multiEventWebhook = {
        ...baseWebhook,
        events: [WebhookEvent.TASK_CREATED, WebhookEvent.TASK_COMPLETED],
      };
      mockPrisma.webhook.create.mockResolvedValue(multiEventWebhook);
      const dto = {
        name: 'Test Webhook',
        targetUrl: 'https://example.com/webhook',
        secret: 'supersecretkey1234',
        events: [WebhookEvent.TASK_CREATED, WebhookEvent.TASK_COMPLETED],
      };

      const result = await service.create(dto);

      expect(result.events).toHaveLength(2);
    });
  });

  describe('findAll', () => {
    it('should return all webhooks ordered by createdAt desc', async () => {
      const webhooks = [baseWebhook];
      mockPrisma.webhook.findMany.mockResolvedValue(webhooks);

      const result = await service.findAll();

      expect(mockPrisma.webhook.findMany).toHaveBeenCalledWith({
        orderBy: { createdAt: 'desc' },
      });
      expect(result).toEqual(webhooks);
    });

    it('should return empty array when no webhooks exist', async () => {
      mockPrisma.webhook.findMany.mockResolvedValue([]);
      const result = await service.findAll();
      expect(result).toEqual([]);
    });
  });

  describe('findOne', () => {
    it('should return a webhook when found', async () => {
      mockPrisma.webhook.findUnique.mockResolvedValue(baseWebhook);
      const result = await service.findOne('webhook-id');
      expect(result).toEqual(baseWebhook);
      expect(mockPrisma.webhook.findUnique).toHaveBeenCalledWith({
        where: { id: 'webhook-id' },
      });
    });

    it('should throw NotFoundException when webhook not found', async () => {
      mockPrisma.webhook.findUnique.mockResolvedValue(null);
      await expect(service.findOne('non-existent-id')).rejects.toThrow(
        NotFoundException,
      );
    });
  });

  describe('update', () => {
    it('should update and return the updated webhook', async () => {
      mockPrisma.webhook.findUnique.mockResolvedValue(baseWebhook);
      const updated = { ...baseWebhook, name: 'Updated Name' };
      mockPrisma.webhook.update.mockResolvedValue(updated);

      const result = await service.update('webhook-id', { name: 'Updated Name' });

      expect(result.name).toBe('Updated Name');
      expect(mockPrisma.webhook.update).toHaveBeenCalledWith({
        where: { id: 'webhook-id' },
        data: expect.objectContaining({ name: 'Updated Name' }),
      });
    });

    it('should deduplicate events on update', async () => {
      mockPrisma.webhook.findUnique.mockResolvedValue(baseWebhook);
      mockPrisma.webhook.update.mockResolvedValue(baseWebhook);

      await service.update('webhook-id', {
        events: [WebhookEvent.TASK_CREATED, WebhookEvent.TASK_CREATED] as any,
      });

      expect(mockPrisma.webhook.update).toHaveBeenCalledWith({
        where: { id: 'webhook-id' },
        data: expect.objectContaining({
          events: [WebhookEvent.TASK_CREATED],
        }),
      });
    });

    it('should throw NotFoundException when updating non-existent webhook', async () => {
      mockPrisma.webhook.findUnique.mockResolvedValue(null);
      await expect(
        service.update('non-existent-id', { name: 'New Name' }),
      ).rejects.toThrow(NotFoundException);
    });
  });

  describe('remove', () => {
    it('should delete the webhook', async () => {
      mockPrisma.webhook.findUnique.mockResolvedValue(baseWebhook);
      mockPrisma.webhook.delete.mockResolvedValue(baseWebhook);

      await service.remove('webhook-id');

      expect(mockPrisma.webhook.delete).toHaveBeenCalledWith({
        where: { id: 'webhook-id' },
      });
    });

    it('should throw NotFoundException when deleting non-existent webhook', async () => {
      mockPrisma.webhook.findUnique.mockResolvedValue(null);
      await expect(service.remove('non-existent-id')).rejects.toThrow(
        NotFoundException,
      );
    });
  });

  describe('enable', () => {
    it('should set enabled=true and return updated webhook', async () => {
      mockPrisma.webhook.findUnique.mockResolvedValue({
        ...baseWebhook,
        enabled: false,
      });
      mockPrisma.webhook.update.mockResolvedValue({ ...baseWebhook, enabled: true });

      const result = await service.enable('webhook-id');

      expect(mockPrisma.webhook.update).toHaveBeenCalledWith({
        where: { id: 'webhook-id' },
        data: { enabled: true },
      });
      expect(result.enabled).toBe(true);
    });

    it('should throw NotFoundException when enabling non-existent webhook', async () => {
      mockPrisma.webhook.findUnique.mockResolvedValue(null);
      await expect(service.enable('non-existent-id')).rejects.toThrow(
        NotFoundException,
      );
    });
  });

  describe('disable', () => {
    it('should set enabled=false and return updated webhook', async () => {
      mockPrisma.webhook.findUnique.mockResolvedValue(baseWebhook);
      mockPrisma.webhook.update.mockResolvedValue({ ...baseWebhook, enabled: false });

      const result = await service.disable('webhook-id');

      expect(mockPrisma.webhook.update).toHaveBeenCalledWith({
        where: { id: 'webhook-id' },
        data: { enabled: false },
      });
      expect(result.enabled).toBe(false);
    });

    it('should throw NotFoundException when disabling non-existent webhook', async () => {
      mockPrisma.webhook.findUnique.mockResolvedValue(null);
      await expect(service.disable('non-existent-id')).rejects.toThrow(
        NotFoundException,
      );
    });
  });
});
