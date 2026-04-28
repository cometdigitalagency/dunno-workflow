import { Module } from '@nestjs/common';
import { BullModule } from '@nestjs/bull';
import { DeliveryProcessor } from './delivery.processor';
import { WEBHOOK_DELIVERY_QUEUE } from './delivery.constants';

@Module({
  imports: [
    BullModule.registerQueue({ name: WEBHOOK_DELIVERY_QUEUE }),
  ],
  providers: [DeliveryProcessor],
})
export class DeliveryModule {}
