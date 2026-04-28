import {
  IsString,
  IsUrl,
  IsBoolean,
  IsArray,
  IsEnum,
  IsOptional,
  ArrayUnique,
  ArrayMinSize,
  IsNotEmpty,
  MinLength,
} from 'class-validator';
import { WebhookEvent } from '../../common/webhook-event.enum';

export class CreateWebhookDto {
  @IsString()
  @IsNotEmpty()
  name: string;

  @IsUrl({}, { message: 'targetUrl must be a valid URL' })
  targetUrl: string;

  @IsString()
  @MinLength(16, { message: 'secret must be at least 16 characters' })
  secret: string;

  @IsOptional()
  @IsBoolean()
  enabled?: boolean;

  @IsArray()
  @ArrayMinSize(1)
  @IsEnum(WebhookEvent, { each: true })
  @ArrayUnique()
  events: WebhookEvent[];
}
