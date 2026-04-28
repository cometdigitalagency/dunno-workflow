import { Module } from '@nestjs/common';
import { BullModule } from '@nestjs/bull';
import { EventsService } from './events.service';
import { WEBHOOK_DELIVERY_QUEUE } from '../delivery/delivery.constants';

@Module({
  imports: [
    BullModule.registerQueue({ name: WEBHOOK_DELIVERY_QUEUE }),
  ],
  providers: [EventsService],
  exports: [EventsService],
})
export class EventsModule {}
