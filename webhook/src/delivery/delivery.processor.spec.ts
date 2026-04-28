import { Test, TestingModule } from '@nestjs/testing';
import * as crypto from 'crypto';
import { DeliveryProcessor } from './delivery.processor';
import { PrismaService } from '../prisma/prisma.service';

// Mock axios before imports so the module is mocked
jest.mock('axios');
import axios from 'axios';

const mockPrisma = {
  webhookDelivery: {
    create: jest.fn(),
  },
};

describe('DeliveryProcessor', () => {
  let processor: DeliveryProcessor;
  const mockedAxios = jest.mocked(axios);

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        DeliveryProcessor,
        { provide: PrismaService, useValue: mockPrisma },
      ],
    }).compile();

    processor = module.get<DeliveryProcessor>(DeliveryProcessor);
    jest.clearAllMocks();
  });

  const baseJobData = {
    webhookId: 'webhook-id',
    targetUrl: 'https://example.com/webhook',
    secret: 'supersecretkey1234',
    event: 'task.created',
    payload: { taskId: '123', name: 'Test Task' },
  };

  function createMockJob(data = baseJobData, attemptsMade = 0) {
    return { id: 'job-id-1', data, attemptsMade };
  }

  function expectedSignature(secret: string, payload: object): string {
    const body = JSON.stringify(payload);
    return crypto.createHmac('sha256', secret).update(body).digest('hex');
  }

  describe('HMAC signature', () => {
    it('should send X-Signature header with hmac-sha256=<hex> format', async () => {
      mockedAxios.post = jest
        .fn()
        .mockResolvedValue({ status: 200, data: 'OK' });
      mockPrisma.webhookDelivery.create.mockResolvedValue({});

      await processor.handleDelivery(createMockJob() as any);

      const sig = expectedSignature(baseJobData.secret, baseJobData.payload);
      expect(mockedAxios.post).toHaveBeenCalledWith(
        baseJobData.targetUrl,
        baseJobData.payload,
        expect.objectContaining({
          headers: expect.objectContaining({
            'X-Signature': `hmac-sha256=${sig}`,
          }),
        }),
      );
    });

    it('should compute a different signature for different payloads', async () => {
      const payload1 = { taskId: '1' };
      const payload2 = { taskId: '2' };
      const sig1 = expectedSignature(baseJobData.secret, payload1);
      const sig2 = expectedSignature(baseJobData.secret, payload2);
      expect(sig1).not.toBe(sig2);
    });

    it('should compute a different signature for different secrets', async () => {
      const secret1 = 'secret1111111111';
      const secret2 = 'secret2222222222';
      const sig1 = expectedSignature(secret1, baseJobData.payload);
      const sig2 = expectedSignature(secret2, baseJobData.payload);
      expect(sig1).not.toBe(sig2);
    });
  });

  describe('HTTP request configuration', () => {
    beforeEach(() => {
      mockedAxios.post = jest
        .fn()
        .mockResolvedValue({ status: 200, data: 'OK' });
      mockPrisma.webhookDelivery.create.mockResolvedValue({});
    });

    it('should set X-Webhook-Event header to the event name', async () => {
      await processor.handleDelivery(createMockJob() as any);

      expect(mockedAxios.post).toHaveBeenCalledWith(
        baseJobData.targetUrl,
        baseJobData.payload,
        expect.objectContaining({
          headers: expect.objectContaining({
            'X-Webhook-Event': baseJobData.event,
          }),
        }),
      );
    });

    it('should use 5000ms timeout', async () => {
      await processor.handleDelivery(createMockJob() as any);

      expect(mockedAxios.post).toHaveBeenCalledWith(
        baseJobData.targetUrl,
        baseJobData.payload,
        expect.objectContaining({ timeout: 5000 }),
      );
    });

    it('should set Content-Type to application/json', async () => {
      await processor.handleDelivery(createMockJob() as any);

      expect(mockedAxios.post).toHaveBeenCalledWith(
        baseJobData.targetUrl,
        baseJobData.payload,
        expect.objectContaining({
          headers: expect.objectContaining({
            'Content-Type': 'application/json',
          }),
        }),
      );
    });
  });

  describe('successful delivery', () => {
    it('should log WebhookDelivery with success=true and correct fields', async () => {
      mockedAxios.post = jest
        .fn()
        .mockResolvedValue({ status: 200, data: 'OK' });
      mockPrisma.webhookDelivery.create.mockResolvedValue({});

      await processor.handleDelivery(createMockJob() as any);

      expect(mockPrisma.webhookDelivery.create).toHaveBeenCalledWith({
        data: expect.objectContaining({
          webhookId: baseJobData.webhookId,
          event: baseJobData.event,
          payload: baseJobData.payload,
          responseStatus: 200,
          success: true,
          retryCount: 0,
        }),
      });
    });

    it('should record latency as a non-negative number', async () => {
      mockedAxios.post = jest
        .fn()
        .mockResolvedValue({ status: 200, data: 'OK' });
      mockPrisma.webhookDelivery.create.mockResolvedValue({});

      await processor.handleDelivery(createMockJob() as any);

      const call = mockPrisma.webhookDelivery.create.mock.calls[0][0];
      expect(call.data.latency).toBeGreaterThanOrEqual(0);
    });

    it('should record responseBody from the response', async () => {
      mockedAxios.post = jest
        .fn()
        .mockResolvedValue({ status: 201, data: { result: 'created' } });
      mockPrisma.webhookDelivery.create.mockResolvedValue({});

      await processor.handleDelivery(createMockJob() as any);

      const call = mockPrisma.webhookDelivery.create.mock.calls[0][0];
      expect(call.data.responseBody).toBe(JSON.stringify({ result: 'created' }));
    });
  });

  describe('failed delivery', () => {
    it('should log WebhookDelivery with success=false when request fails', async () => {
      const error = new Error('Connection refused');
      (error as any).response = { status: 503, data: 'Service Unavailable' };
      mockedAxios.post = jest.fn().mockRejectedValue(error);
      mockPrisma.webhookDelivery.create.mockResolvedValue({});

      await expect(
        processor.handleDelivery(createMockJob() as any),
      ).rejects.toThrow('Connection refused');

      expect(mockPrisma.webhookDelivery.create).toHaveBeenCalledWith({
        data: expect.objectContaining({
          success: false,
          responseStatus: 503,
        }),
      });
    });

    it('should re-throw the error so BullMQ retries the job', async () => {
      const error = new Error('Network error');
      mockedAxios.post = jest.fn().mockRejectedValue(error);
      mockPrisma.webhookDelivery.create.mockResolvedValue({});

      await expect(
        processor.handleDelivery(createMockJob() as any),
      ).rejects.toThrow('Network error');
    });

    it('should record attemptsMade as retryCount in the delivery log', async () => {
      const error = new Error('Network error');
      mockedAxios.post = jest.fn().mockRejectedValue(error);
      mockPrisma.webhookDelivery.create.mockResolvedValue({});

      await expect(
        processor.handleDelivery(createMockJob(baseJobData, 2) as any),
      ).rejects.toThrow();

      expect(mockPrisma.webhookDelivery.create).toHaveBeenCalledWith({
        data: expect.objectContaining({ retryCount: 2 }),
      });
    });

    it('should log delivery with null responseStatus on network/timeout error', async () => {
      const error = new Error('timeout of 5000ms exceeded');
      (error as any).code = 'ECONNABORTED';
      mockedAxios.post = jest.fn().mockRejectedValue(error);
      mockPrisma.webhookDelivery.create.mockResolvedValue({});

      await expect(
        processor.handleDelivery(createMockJob() as any),
      ).rejects.toThrow();

      expect(mockPrisma.webhookDelivery.create).toHaveBeenCalledWith({
        data: expect.objectContaining({
          success: false,
          responseStatus: null,
          responseBody: 'timeout of 5000ms exceeded',
        }),
      });
    });
  });

  describe('delivery log always written (finally block)', () => {
    it('should write exactly one delivery record on success', async () => {
      mockedAxios.post = jest
        .fn()
        .mockResolvedValue({ status: 200, data: 'OK' });
      mockPrisma.webhookDelivery.create.mockResolvedValue({});

      await processor.handleDelivery(createMockJob() as any);

      expect(mockPrisma.webhookDelivery.create).toHaveBeenCalledTimes(1);
    });

    it('should write exactly one delivery record on failure', async () => {
      const error = new Error('Network error');
      mockedAxios.post = jest.fn().mockRejectedValue(error);
      mockPrisma.webhookDelivery.create.mockResolvedValue({});

      await expect(
        processor.handleDelivery(createMockJob() as any),
      ).rejects.toThrow();

      expect(mockPrisma.webhookDelivery.create).toHaveBeenCalledTimes(1);
    });
  });
});
