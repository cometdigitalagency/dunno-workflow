import {
  IsString,
  IsUrl,
  IsBoolean,
  IsArray,
  IsEnum,
  IsOptional,
  ArrayUnique,
  MinLength,
} from 'class-validator';
import { WebhookEvent } from '../../common/webhook-event.enum';

export class UpdateWebhookDto {
  @IsOptional()
  @IsString()
  name?: string;

  @IsOptional()
  @IsUrl({}, { message: 'targetUrl must be a valid URL' })
  targetUrl?: string;

  @IsOptional()
  @IsString()
  @MinLength(16, { message: 'secret must be at least 16 characters' })
  secret?: string;

  @IsOptional()
  @IsBoolean()
  enabled?: boolean;

  @IsOptional()
  @IsArray()
  @IsEnum(WebhookEvent, { each: true })
  @ArrayUnique()
  events?: WebhookEvent[];
}
