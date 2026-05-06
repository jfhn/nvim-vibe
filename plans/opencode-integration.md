# Backend-Agnostic Dispatcher Plan

## Goal
nvim-vibe as orchestration tool with a general-purpose HTTP dispatcher. Any backend (OpenCode, Hermes, direct LLM API, etc.) can be plugged in.

## Architecture

```
┌─────────────┐     ┌────────────┐
│  nvim-vibe  │─────│   Server   │  (dispatcher)
│ (orchestr.) │     │   (HTTP)   │
└─────────────┘     └──────┬─────┘
                           │
       ┌───────────┬───────┴───────┬───────────┐
       ▼           ▼               ▼           ▼
 ┌──────────┐ ┌─────────┐     ┌─────────┐ ┌─────────┐
 │ OpenCode │ │ Hermes  │     │ LLM API │ │ Custom  │
 │ backend  │ │ backend │     │ backend │ │ backend │
 └──────────┘ └─────────┘     └─────────┘ └─────────┘
```

## Backend Interface

Each backend implements:

```lua
-- backend.lua
{
  name = "opencode",           -- unique identifier
  spawn = function(config)      -- spawn worker process, return handle
  send = function(handle, msg) -- send JSON message
  recv = function(handle)      -- receive JSON message (blocking)
  kill = function(handle)    -- terminate worker
}
```

## Configuration

```lua
-- In nvim-vibe config
backends = {
  opencode = {
    command = "opencode",
    args = {"--task"},
  },
  hermes = {
    command = "hermes-agent",
    env = { API_KEY = os.getenv("HERMES_KEY") },
  },
  openai = {
    url = "https://api.openai.com/v1/chat/completions",
    headers = { Authorization = "Bearer " .. os.getenv("OPENAI_KEY") },
  }
}

default_backend = "opencode"
```

## Protocol

### Task Payload (backend-agnostic)

```json
{
  "id": "uuid",
  "backend": "opencode",          -- which backend to use
  "prompt": "Fix the bug...",
  "model": "minimax-m2.5-free", -- backend-specific
  "tools": ["read", "glob"],
  "working_dir": "/project"
}
```

## Communication

- **Server**: nvim-vibe runs HTTP server
- **Backends**: Spawned as subprocesses or HTTP clients
- **Messages**: JSON over HTTP
- **Parallel**: Multiple workers from any backend

## Approval Events

| Event | Action |
|-------|--------|
| File edit (path matches filter) | Block → prompt in nvim-vibe |
| Shell command | Block → prompt in nvim-vibe |
| Tool execution | Block → prompt in nvim-vibe |

## Sidebar Integration

- Show tasks blocked/pending/running
- Status per task: `pending` | `waiting_approval` | `running` | `done` | `blocked`
- Actions: Approve / Reject / Cancel

## Protocol

### HTTP Endpoints (nvim-vibe server)

```
POST /task              - Submit new task
GET  /task/:id          - Get task status
POST /task/:id/approve  - Approve pending action
POST /task/:id/reject   - Reject pending action
GET  /tasks             - List all tasks
WS   /events            - Real-time updates
```

### Task Payload

```json
{
  "id": "uuid",
  "prompt": "Fix the bug in auth middleware",
  "model": "opencode/minimax-m2.5-free",
  "tools": ["read", "glob", "grep", "apply", "bash"],
  "working_dir": "/project",
  "blocks": {
    "file_patterns": ["src/**/*.lua"],
    "shell_patterns": ["git*", "npm*"]
  }
}
```

### Approval Request

```json
{
  "type": "approval",
  "task_id": "uuid",
  "action": {
    "type": "file_edit",
    "path": "src/auth.lua",
    "diff": "..."
  }
}
```

## UX Flow

1. User opens tasks sidebar → sees project tasks
2. User selects task → clicks "Solve" button
3. **Phase 1: Plan** → Planning agent reads task, outputs feedback/elaboration
4. User reviews plan → Approve or Reject
5. **Phase 2: Execute** → Execution agent runs tasks (Sequence/Parallel/Agent per ideas.md)
6. Execution can split tasks → new subtasks created
7. User can approve/reject at checkpoints

## Task Kinds (per ideas.md)

| Kind | Behavior |
|------|----------|
| `Agent` | Single OpenCode agent executes directly |
| `Sequence` | Master reviewer, index tracks progress, task n needs 0..n-1 done |
| `Parallel` | Master reviewer, subtasks run concurrently |

## Implementation Phases

### Phase 1: Plan Agent
1. HTTP server in nvim-vibe
2. Spawn planning OpenCode with task content
3. Display plan in approval UI
4. User approves → proceed to execute

### Phase 2: Execute Agent
1. Execute agent parses task kind (Sequence/Parallel/Agent)
2. Spawns child OpenCode agents as workers
3. Coordinates via master reviewer
4. Reports status to nvim-vibe sidebar

### Phase 3: Parallel
1. Multiple workers (any backend) per task
2. Result aggregation
3. Cross-backend task distribution

## Open Questions

1. **Approval UI**: Floating window or sidebar inline?
2. **Pattern config**: Per-task or global?
3. **Task persistence**: Save state across restarts?
4. **Initial backend**: OpenCode or LLM API direct?
5. **Planning prompt**: Custom instructions or default?
