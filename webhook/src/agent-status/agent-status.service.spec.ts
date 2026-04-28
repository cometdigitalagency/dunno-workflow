import { AgentStatusService } from './agent-status.service';
import { EventsService } from '../events/events.service';

describe('AgentStatusService', () => {
  let service: AgentStatusService;

  const mockEventsService = {
    emit: jest.fn(),
  } as unknown as EventsService;

  beforeEach(() => {
    jest.clearAllMocks();
    service = new AgentStatusService(mockEventsService);
  });

  it('stores and returns a status update', async () => {
    const result = await service.update({
      agent: 'backend',
      status: 'running',
      detail: 'Task #231',
      progress: 68,
    });

    expect(result).toMatchObject({
      agent: 'backend',
      status: 'running',
      detail: 'Task #231',
      progress: 68,
      source: 'dunno-workflow',
    });

    expect(service.getAll()).toEqual([
      expect.objectContaining({
        agent: 'backend',
        status: 'running',
      }),
    ]);
  });

  it('emits agent.status_changed webhook events', async () => {
    await service.update({
      agent: 'qa',
      status: 'waitinginput',
      detail: 'Need approval',
    });

    expect(mockEventsService.emit).toHaveBeenCalledWith(
      'agent.status_changed',
      expect.objectContaining({
        agent: 'qa',
        status: 'waitinginput',
        detail: 'Need approval',
      }),
    );
  });

  it('replaces previous state for the same agent', async () => {
    await service.update({
      agent: 'backend',
      status: 'running',
      detail: 'Task #231',
    });
    await service.update({
      agent: 'backend',
      status: 'idle',
      detail: 'waiting',
    });

    expect(service.getAll()).toEqual([
      expect.objectContaining({
        agent: 'backend',
        status: 'idle',
        detail: 'waiting',
      }),
    ]);
  });
});
