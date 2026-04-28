# Webhook Service

A NestJS service that receives webhook registrations and reliably delivers events to subscriber endpoints using a PostgreSQL-backed queue (BullMQ + Redis).

## Prerequisites

- Node.js 20+
- Docker + Docker Compose

## Local Setup

1. **Install dependencies**
   ```bash
   npm install
   ```

2. **Copy environment file**
   ```bash
   cp .env.example .env
   ```
   Default values in `.env.example` match the Docker Compose services — no edits needed for local development.

3. **Start backing services**
   ```bash
   docker compose up -d
   ```

4. **Generate Prisma client**
   ```bash
   npm run prisma:generate
   ```

5. **Run database migrations**
   ```bash
   npm run prisma:migrate
   ```

6. **Start the app**
   ```bash
   npm run start:dev
   ```

## Environment Variables

| Variable       | Description                              | Default                                          |
|----------------|------------------------------------------|--------------------------------------------------|
| `DATABASE_URL` | PostgreSQL connection string             | `postgresql://user:password@localhost:5432/webhooks` |
| `REDIS_URL`    | Redis connection URL used by BullMQ      | `redis://localhost:6379`                         |
| `PORT`         | HTTP port the NestJS app listens on      | `3000`                                           |

## Available Scripts

```bash
npm run test          # unit tests
npm run test:e2e      # end-to-end tests
npm run test:cov      # test coverage report
npm run build         # compile to dist/
npm run lint          # ESLint
```

## Verify It Works

Once the app is running, confirm it responds:

```bash
curl -i http://localhost:3000
```

You should receive an HTTP response (404 or similar) — any response confirms the server is up.

## Agent Status Monitoring

The service also accepts live agent status updates from `dunno-workflow`.

- `POST /agent-status` accepts the current state of an agent
- `GET /agent-status` returns the latest known state for all agents
- `GET /agent-status/stream` provides an SSE stream of status changes

Example status update:

```bash
curl -X POST http://localhost:3000/agent-status \
  -H 'Content-Type: application/json' \
  -d '{
    "agent":"backend",
    "status":"running",
    "detail":"Task #231",
    "progress":68
  }'
```

To enable status publishing from `dunno-workflow`, set this in `workflow.yaml`:

```yaml
monitoring:
  webhook_url: http://localhost:3000
```
