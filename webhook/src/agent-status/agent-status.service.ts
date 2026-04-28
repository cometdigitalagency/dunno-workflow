import { Injectable } from '@nestjs/common';
import { Subject } from 'rxjs';
import { EventsService } from '../events/events.service';
import { WebhookEvent } from '../common/webhook-event.enum';
import {
  AgentStatusValue,
  UpdateAgentStatusDto,
} from './dto/update-agent-status.dto';

export interface AgentStatusSnapshot {
  agent: string;
  status: AgentStatusValue;
  detail: string | null;
  task: string | null;
  progress: number | null;
  timestamp: number;
  source: string;
  updatedAt: string;
}

@Injectable()
export class AgentStatusService {
  private readonly statuses = new Map<string, AgentStatusSnapshot>();
  private readonly streamSubject = new Subject<AgentStatusSnapshot>();

  constructor(private readonly eventsService: EventsService) {}

  getAll(): AgentStatusSnapshot[] {
    return Array.from(this.statuses.values()).sort((a, b) =>
      a.agent.localeCompare(b.agent),
    );
  }

  getStream() {
    return this.streamSubject.asObservable();
  }

  async update(dto: UpdateAgentStatusDto): Promise<AgentStatusSnapshot> {
    const snapshot: AgentStatusSnapshot = {
      agent: dto.agent,
      status: dto.status,
      detail: dto.detail ?? null,
      task: dto.task ?? null,
      progress: typeof dto.progress === 'number' ? dto.progress : null,
      timestamp: dto.timestamp ?? Math.floor(Date.now() / 1000),
      source: dto.source ?? 'dunno-workflow',
      updatedAt: new Date().toISOString(),
    };

    this.statuses.set(snapshot.agent, snapshot);
    this.streamSubject.next(snapshot);
    await this.eventsService.emit(WebhookEvent.AGENT_STATUS_CHANGED, snapshot);
    return snapshot;
  }
}
