export enum WebhookEvent {
  AGENT_ERROR = 'agent.error',
  AGENT_STATUS_CHANGED = 'agent.status_changed',
  MENTION_CREATED = 'mention.created',
  ASSIGNMENT_CREATED = 'assignment.created',
  TASK_CREATED = 'task.created',
  TASK_COMPLETED = 'task.completed',
}

export const ALL_WEBHOOK_EVENTS = Object.values(WebhookEvent);
