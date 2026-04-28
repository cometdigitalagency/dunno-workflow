import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { BullModule } from '@nestjs/bull';
import { PrismaModule } from './prisma/prisma.module';
import { WebhookModule } from './webhook/webhook.module';
import { EventsModule } from './events/events.module';
import { DeliveryModule } from './delivery/delivery.module';
import { AgentStatusModule } from './agent-status/agent-status.module';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      envFilePath: '.env',
    }),
    BullModule.forRootAsync({
      imports: [ConfigModule],
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        url: config.get<string>('REDIS_URL', 'redis://localhost:6379'),
      }),
    }),
    PrismaModule,
    WebhookModule,
    EventsModule,
    DeliveryModule,
    AgentStatusModule,
  ],
})
export class AppModule {}
