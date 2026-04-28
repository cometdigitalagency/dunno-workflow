import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  MessageEvent,
  Post,
  Sse,
} from '@nestjs/common';
import { map, Observable } from 'rxjs';
import { AgentStatusService } from './agent-status.service';
import { UpdateAgentStatusDto } from './dto/update-agent-status.dto';

@Controller('agent-status')
export class AgentStatusController {
  constructor(private readonly agentStatusService: AgentStatusService) {}

  @Get()
  findAll() {
    return this.agentStatusService.getAll();
  }

  @Post()
  @HttpCode(HttpStatus.ACCEPTED)
  async update(@Body() dto: UpdateAgentStatusDto) {
    const status = await this.agentStatusService.update(dto);
    return { message: 'Agent status accepted', status };
  }

  @Sse('stream')
  stream(): Observable<MessageEvent> {
    return this.agentStatusService
      .getStream()
      .pipe(map((data) => ({ data, type: 'agent.status_changed' })));
  }
}
