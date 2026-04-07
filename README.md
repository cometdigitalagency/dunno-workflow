# dunno-workflow

Declarative agent team orchestration for [Claude Code](https://claude.ai/claude-code). Define your team in YAML, launch in iTerm2.

## Install

```bash
brew install cometdigitalagency/dunno/dunno-workflow
```

### Requirements

- macOS with [iTerm2](https://iterm2.com/)
- [Claude Code](https://claude.ai/claude-code) CLI (`claude`)
- [yq](https://github.com/mikefarah/yq) (installed automatically with brew)
- [gh](https://cli.github.com/) (only if using GitHub ticket source)

## Quick Start

```bash
cd your-project
dunno-workflow init           # creates workflow.yaml
vim workflow.yaml             # customize agents, ticket source
dunno-workflow start          # launch team in iTerm2
dunno-workflow start --debug  # with filtered LOGS pane
```

## Commands

| Command | Description |
|---------|-------------|
| `dunno-workflow init` | Create `workflow.yaml` template in current directory |
| `dunno-workflow start` | Launch agent team in iTerm2 |
| `dunno-workflow start --debug` | Launch with LOGS pane (filtered, color-coded) |
| `dunno-workflow start --test` | Test mode with mock/file-based ticket |
| `dunno-workflow start --issue N` | Start team on a specific ticket |
| `dunno-workflow validate` | Validate `workflow.yaml` |
| `dunno-workflow stop` | Stop all running agent sessions |

## How It Works

```
workflow.yaml          You define agents, events, ticket sources
       │
       ▼
dunno-workflow start   Reads YAML, generates prompts & launchers
       │
       ▼
┌──────┬─────────┬──────────┐
│  PM  │ BACKEND │ ARCHITECT│   iTerm2 split panes
│      ├─────────┼──────────┤   Each agent = Claude Code session
│      │   QA    │ FRONTEND │
└──────┴─────────┴──────────┘
```

1. **PM** (interactive) — you talk to it, it creates tickets
2. **Architect** (auto-start) — picks up tickets, plans work, dispatches tasks
3. **Workers** (event-driven) — idle until they receive a TASK message, then work
4. **QA** (event-driven) — dispatched only after implementation is done

## workflow.yaml

### Agents

```yaml
agents:
  my_agent:
    role: "Agent Role"
    description: "What this agent does"
    interactive: true/false     # true = user-facing (PM)
    auto_start: true/false      # true = starts immediately (architect)
    # false (default) = waits for messages (workers)
    owns:
      paths: ["src/**"]         # files this agent may edit
      never_edit: ["frontend/**"]
    workflow: [...]              # numbered steps in the system prompt
    rules: [...]                # bullet points in the system prompt
    init:
      default: "..."            # first message to start the agent
      test: "..."               # test mode variant
```

### Ticket Sources

```yaml
tickets:
  source: github    # or: jira, clickup, file
  github:
    repo: org/repo
    labels: { ready: ready, in_progress: in-progress, done: done }
  file:
    directory: ./tickets
    format: markdown
```

File-based tickets use markdown with YAML frontmatter:

```markdown
---
id: 1
title: My feature
status: ready
---
## Summary
...
```

### Events

Define message types between agents:

```yaml
events:
  task:
    format: "TASK [Issue #{issue}]: {description}"
    direction: architect -> workers
  done:
    format: "Done-{agent}"
    direction: workers -> architect
```

## Adding an Agent

Add a block to `workflow.yaml` under `agents:` and re-run. The layout adjusts automatically.

```yaml
  reviewer:
    role: Code Reviewer
    description: Reviews code changes before commit.
    interactive: false
    auto_start: false          # waits for REVIEW-REQUEST messages
    owns: { paths: [], never_edit: ["**/*"] }
    sends: [review_approved]
    receives: [review_request]
    workflow:
      - "Wait for REVIEW-REQUEST message"
      - "Review the changes"
      - "Send REVIEW-APPROVED or REVIEW-REJECTED"
    rules:
      - "Do NOT write code — only review"
    init:
      default: "Wait for REVIEW-REQUEST messages."
```

## License

MIT
