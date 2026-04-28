import { Module } from '@nestjs/common';
import { EventsModule } from '../events/events.module';
import { AgentStatusController } from './agent-status.controller';
import { AgentStatusService } from './agent-status.service';

@Module({
  imports: [EventsModule],
  controllers: [AgentStatusController],
  providers: [AgentStatusService],
  exports: [AgentStatusService],
})
export class AgentStatusModule {}
