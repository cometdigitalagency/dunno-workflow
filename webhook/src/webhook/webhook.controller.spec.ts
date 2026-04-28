/**
 * Integration tests for WebhookController.
 * Uses supertest against a NestJS TestingModule with mocked PrismaService and BullMQ queue.
 * No real database or Redis is required.
 */
import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication, ValidationPipe, NotFoundException } from '@nestjs/common';
import * as request from 'supertest';
import { getQueueToken } from '@nestjs/bull';
import { WebhookController } from './webhook.controller';
import { WebhookService } from './webhook.service';
import { EventsService } from '../events/events.service';
import { PrismaService } from '../prisma/prisma.service';
import { WEBHOOK_DELIVERY_QUEUE } from '../delivery/delivery.constants';
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

const mockQueue = {
  add: jest.fn(),
};

describe('WebhookController (integration)', () => {
  let app: INestApplication;

  const baseWebhook = {
    id: 'webhook-uuid-1234',
    name: 'My Webhook',
    targetUrl: 'https://example.com/hook',
    secret: 'supersecretkey1234',
    enabled: true,
    events: [WebhookEvent.TASK_CREATED],
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
  };

  beforeAll(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      controllers: [WebhookController],
      providers: [
        WebhookService,
        EventsService,
        { provide: PrismaService, useValue: mockPrisma },
        { provide: getQueueToken(WEBHOOK_DELIVERY_QUEUE), useValue: mockQueue },
      ],
    }).compile();

    app = moduleFixture.createNestApplication();
    app.useGlobalPipes(
      new ValidationPipe({
        whitelist: true,
        forbidNonWhitelisted: true,
        transform: true,
      }),
    );
    await app.init();
  });

  afterAll(async () => {
    await app.close();
  });

  beforeEach(() => {
    jest.clearAllMocks();
  });

  const validCreateDto = {
    name: 'My Webhook',
    targetUrl: 'https://example.com/hook',
    secret: 'supersecretkey1234',
    events: [WebhookEvent.TASK_CREATED],
  };

  // ── POST /webhooks ──────────────────────────────────────────────────────────

  describe('POST /webhooks', () => {
    it('should create a webhook and return 201', async () => {
      mockPrisma.webhook.create.mockResolvedValue(baseWebhook);

      const res = await request(app.getHttpServer())
        .post('/webhooks')
        .send(validCreateDto)
        .expect(201);

      expect(res.body).toMatchObject({
        id: baseWebhook.id,
        name: baseWebhook.name,
        targetUrl: baseWebhook.targetUrl,
        enabled: true,
      });
    });

    it('should return 400 when targetUrl is not a valid URL', async () => {
      await request(app.getHttpServer())
        .post('/webhooks')
        .send({ ...validCreateDto, targetUrl: 'not-a-url' })
        .expect(400);
    });

    it('should return 400 when events contains an unknown event type', async () => {
      await request(app.getHttpServer())
        .post('/webhooks')
        .send({ ...validCreateDto, events: ['unknown.event'] })
        .expect(400);
    });

    it('should return 400 when secret is shorter than 16 characters', async () => {
      await request(app.getHttpServer())
        .post('/webhooks')
        .send({ ...validCreateDto, secret: 'short' })
        .expect(400);
    });

    it('should return 400 when name is missing', async () => {
      const { name: _omit, ...withoutName } = validCreateDto;
      await request(app.getHttpServer())
        .post('/webhooks')
        .send(withoutName)
        .expect(400);
    });

    it('should return 400 when events array is empty', async () => {
      await request(app.getHttpServer())
        .post('/webhooks')
        .send({ ...validCreateDto, events: [] })
        .expect(400);
    });

    it('should accept multiple valid events', async () => {
      const multiEventWebhook = {
        ...baseWebhook,
        events: [WebhookEvent.TASK_CREATED, WebhookEvent.TASK_COMPLETED],
      };
      mockPrisma.webhook.create.mockResolvedValue(multiEventWebhook);

      const res = await request(app.getHttpServer())
        .post('/webhooks')
        .send({
          ...validCreateDto,
          events: [WebhookEvent.TASK_CREATED, WebhookEvent.TASK_COMPLETED],
        })
        .expect(201);

      expect(res.body.events).toHaveLength(2);
    });
  });

  // ── GET /webhooks ───────────────────────────────────────────────────────────

  describe('GET /webhooks', () => {
    it('should return 200 with an array of webhooks', async () => {
      mockPrisma.webhook.findMany.mockResolvedValue([baseWebhook]);

      const res = await request(app.getHttpServer())
        .get('/webhooks')
        .expect(200);

      expect(Array.isArray(res.body)).toBe(true);
      expect(res.body).toHaveLength(1);
      expect(res.body[0].id).toBe(baseWebhook.id);
    });

    it('should return 200 with empty array when no webhooks exist', async () => {
      mockPrisma.webhook.findMany.mockResolvedValue([]);

      const res = await request(app.getHttpServer())
        .get('/webhooks')
        .expect(200);

      expect(res.body).toEqual([]);
    });
  });

  // ── GET /webhooks/:id ───────────────────────────────────────────────────────

  describe('GET /webhooks/:id', () => {
    it('should return 200 with the webhook when found', async () => {
      mockPrisma.webhook.findUnique.mockResolvedValue(baseWebhook);

      const res = await request(app.getHttpServer())
        .get(`/webhooks/${baseWebhook.id}`)
        .expect(200);

      expect(res.body.id).toBe(baseWebhook.id);
    });

    it('should return 404 when webhook is not found', async () => {
      mockPrisma.webhook.findUnique.mockResolvedValue(null);

      await request(app.getHttpServer())
        .get('/webhooks/non-existent-id')
        .expect(404);
    });
  });

  // ── PATCH /webhooks/:id ─────────────────────────────────────────────────────

  describe('PATCH /webhooks/:id', () => {
    it('should return 200 with the updated webhook', async () => {
      mockPrisma.webhook.findUnique.mockResolvedValue(baseWebhook);
      const updated = { ...baseWebhook, name: 'Updated Name' };
      mockPrisma.webhook.update.mockResolvedValue(updated);

      const res = await request(app.getHttpServer())
        .patch(`/webhooks/${baseWebhook.id}`)
        .send({ name: 'Updated Name' })
        .expect(200);

      expect(res.body.name).toBe('Updated Name');
    });

    it('should return 404 when patching non-existent webhook', async () => {
      mockPrisma.webhook.findUnique.mockResolvedValue(null);

      await request(app.getHttpServer())
        .patch('/webhooks/non-existent-id')
        .send({ name: 'Updated Name' })
        .expect(404);
    });

    it('should return 400 when updating targetUrl to an invalid URL', async () => {
      await request(app.getHttpServer())
        .patch(`/webhooks/${baseWebhook.id}`)
        .send({ targetUrl: 'not-a-valid-url' })
        .expect(400);
    });
  });

  // ── DELETE /webhooks/:id ────────────────────────────────────────────────────

  describe('DELETE /webhooks/:id', () => {
    it('should return 204 on successful delete', async () => {
      mockPrisma.webhook.findUnique.mockResolvedValue(baseWebhook);
      mockPrisma.webhook.delete.mockResolvedValue(baseWebhook);

      await request(app.getHttpServer())
        .delete(`/webhooks/${baseWebhook.id}`)
        .expect(204);
    });

    it('should return 404 when deleting non-existent webhook', async () => {
      mockPrisma.webhook.findUnique.mockResolvedValue(null);

      await request(app.getHttpServer())
        .delete('/webhooks/non-existent-id')
        .expect(404);
    });
  });

  // ── PATCH /webhooks/:id/enable ──────────────────────────────────────────────

  describe('PATCH /webhooks/:id/enable', () => {
    it('should return 200 with enabled=true', async () => {
      mockPrisma.webhook.findUnique.mockResolvedValue({
        ...baseWebhook,
        enabled: false,
      });
      mockPrisma.webhook.update.mockResolvedValue({ ...baseWebhook, enabled: true });

      const res = await request(app.getHttpServer())
        .patch(`/webhooks/${baseWebhook.id}/enable`)
        .expect(200);

      expect(res.body.enabled).toBe(true);
    });

    it('should return 404 for non-existent webhook', async () => {
      mockPrisma.webhook.findUnique.mockResolvedValue(null);

      await request(app.getHttpServer())
        .patch('/webhooks/non-existent-id/enable')
        .expect(404);
    });
  });

  // ── PATCH /webhooks/:id/disable ─────────────────────────────────────────────

  describe('PATCH /webhooks/:id/disable', () => {
    it('should return 200 with enabled=false', async () => {
      mockPrisma.webhook.findUnique.mockResolvedValue(baseWebhook);
      mockPrisma.webhook.update.mockResolvedValue({ ...baseWebhook, enabled: false });

      const res = await request(app.getHttpServer())
        .patch(`/webhooks/${baseWebhook.id}/disable`)
        .expect(200);

      expect(res.body.enabled).toBe(false);
    });

    it('should return 404 for non-existent webhook', async () => {
      mockPrisma.webhook.findUnique.mockResolvedValue(null);

      await request(app.getHttpServer())
        .patch('/webhooks/non-existent-id/disable')
        .expect(404);
    });
  });

  // ── POST /webhooks/:id/test ─────────────────────────────────────────────────

  describe('POST /webhooks/:id/test', () => {
    it('should return 202 with a queued message', async () => {
      mockPrisma.webhook.findUnique.mockResolvedValue(baseWebhook);
      mockQueue.add.mockResolvedValue({ id: 'job-1' });

      const res = await request(app.getHttpServer())
        .post(`/webhooks/${baseWebhook.id}/test`)
        .expect(202);

      expect(res.body).toEqual({ message: 'Test delivery queued' });
    });

    it('should enqueue a job when test endpoint is called', async () => {
      mockPrisma.webhook.findUnique.mockResolvedValue(baseWebhook);
      mockQueue.add.mockResolvedValue({ id: 'job-1' });

      await request(app.getHttpServer())
        .post(`/webhooks/${baseWebhook.id}/test`)
        .expect(202);

      expect(mockQueue.add).toHaveBeenCalledTimes(1);
      expect(mockQueue.add).toHaveBeenCalledWith(
        expect.objectContaining({
          webhookId: baseWebhook.id,
          targetUrl: baseWebhook.targetUrl,
          secret: baseWebhook.secret,
          event: 'webhook.test',
        }),
        expect.any(Object),
      );
    });

    it('should return 404 when testing non-existent webhook', async () => {
      mockPrisma.webhook.findUnique.mockResolvedValue(null);

      await request(app.getHttpServer())
        .post('/webhooks/non-existent-id/test')
        .expect(404);
    });
  });

  // ── Disabled webhook does not receive events ────────────────────────────────

  describe('disabled webhook skips event delivery', () => {
    it('should not enqueue a job when EventsService.emit finds no enabled matching webhooks', async () => {
      // DB returns empty (disabled webhooks are filtered by enabled: true)
      mockPrisma.webhook.findMany.mockResolvedValue([]);

      const eventsService = app.get(EventsService);
      await eventsService.emit(WebhookEvent.TASK_CREATED, { taskId: '999' });

      expect(mockQueue.add).not.toHaveBeenCalled();
    });

    it('should only enqueue for enabled webhooks returned from DB', async () => {
      const anotherEnabled = {
        ...baseWebhook,
        id: 'enabled-webhook-id',
        enabled: true,
      };
      // DB returns only enabled webhooks (disabled ones excluded at query level)
      mockPrisma.webhook.findMany.mockResolvedValue([anotherEnabled]);

      const eventsService = app.get(EventsService);
      await eventsService.emit(WebhookEvent.TASK_CREATED, { taskId: '999' });

      expect(mockQueue.add).toHaveBeenCalledTimes(1);
      expect(mockQueue.add).toHaveBeenCalledWith(
        expect.objectContaining({ webhookId: 'enabled-webhook-id' }),
        expect.any(Object),
      );
    });
  });
});
