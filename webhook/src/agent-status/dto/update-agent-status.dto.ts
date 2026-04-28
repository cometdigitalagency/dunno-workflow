import {
  IsIn,
  IsInt,
  IsNotEmpty,
  IsNumber,
  IsOptional,
  IsString,
  Max,
  Min,
} from 'class-validator';

export const AGENT_STATUSES = [
  'idle',
  'running',
  'thinking',
  'waitinginput',
  'error',
  'retrying',
  'offline',
] as const;

export type AgentStatusValue = (typeof AGENT_STATUSES)[number];

export class UpdateAgentStatusDto {
  @IsString()
  @IsNotEmpty()
  agent!: string;

  @IsString()
  @IsIn(AGENT_STATUSES)
  status!: AgentStatusValue;

  @IsOptional()
  @IsString()
  detail?: string;

  @IsOptional()
  @IsString()
  task?: string;

  @IsOptional()
  @IsNumber()
  @Min(0)
  @Max(100)
  progress?: number;

  @IsOptional()
  @IsInt()
  @Min(0)
  timestamp?: number;

  @IsOptional()
  @IsString()
  source?: string;
}
