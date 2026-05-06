# nvim-vibe v2 Plan

## Goal

Turn `nvim-vibe` from a project/worktree switcher into a task-oriented orchestration UI for multiple projects.

Core idea:

- `nvim-vibe` owns project context, task tree, runtime state, notifications, and overview UX
- external runtimes like OpenCode act as execution backends
- task semantics stay backend-agnostic

## Product Direction

`nvim-vibe` should answer these questions quickly:

- What projects do I have?
- Which worktree am I in?
- What tasks exist for this project?
- Which tasks are active right now?
- Which agent is blocked and why?
- Which plan needs my approval?
- Which subtask failed or needs review?

The plugin is primarily an overview and orchestration tool, not just an execution wrapper.

## Scope

This plan keeps v1 capabilities and extends them with:

- hierarchical task storage
- runtime task algebra
- planning-first execution
- notifications for blocked/attention-needed states
- backend integration for agent runtimes like OpenCode

## Existing v1 Foundation

- Project config stored in `~/.local/nvim-vibe/projects.lua`
- Project/worktree switching
- Buffer cleanup on switch
- Worktree management
- Telescope integration
- Sidebar project/worktree view
- Auto-detection of current project from cwd
- Hooks on project switch

These stay and become the base layer for task orchestration.

## Task Model

The canonical task model is a small algebra:

```ts
type Task = Agent | Sequence | Parallel;

type Agent = {
  kind: "agent";
  model: Model;
  role: Role;
  prompt: string;
  tools: Tool[];
};

type Sequence = {
  kind: "sequence";
  master: Agent;
  index: number;
  tasks: Task[];
  onError: "fail_fast" | "collect";
};

type Parallel = {
  kind: "parallel";
  master: Agent;
  tasks: Task[];
  onError: "fail_fast" | "collect";
};
```

### Semantics

- `Agent` is a leaf work unit executed by one backend session
- `Sequence` executes children in order using explicit `index`
- `Parallel` executes children concurrently
- `master` belongs to the composite node and is not a child node
- master is a real LLM agent session responsible for planning, review, mutation, and summary

## Canonical Ownership Model

`nvim-vibe` owns:

- canonical task tree
- stable node identities
- derived node status
- block reasons
- runtime event log
- summary snapshot per node
- notifications and attention UI

Execution backends own:

- actual model invocation
- tool usage inside their own session model
- reporting task-relevant events back to `nvim-vibe`

Backends do not own the canonical task semantics.

## Runtime State Model

Use a layered model inspired by the task algebra formalization.

### Structure Layer

Persistent task tree with stable node ids.

- node kind
- parent/child relations
- child ordering
- sequence index
- master config
- agent config
- error policy

### Runtime Layer

Primary runtime state per node:

- `Planned`
- `Active`
- `Reviewing(outcome)`
- `Done(outcome)`
- `Failed(error)`
- `Cancelled`

### Derived Status Layer

Sidebar and notifications should consume derived status only:

- `planned`
- `ready`
- `running`
- `waiting_review`
- `blocked`
- `completed`
- `failed`
- `cancelled`

### Block Reasons

Blocked state should carry one primary reason:

- `sequence_predecessor`
- `review`
- `question`
- `permission`
- `dependency`
- `external`
- `resource`
- `policy`

## Review Model

Review is explicit.

- child results are not implicitly accepted when a composite controls them
- leaf errors should enter `Reviewing(err)` rather than hard-failing immediately
- the master decides whether to:
  - accept
  - retry
  - replace
  - bubble failure upward

### Retry Rule

Early policy:

- retry keeps same child identity
- default retry budget is `1`
- if the child fails again, the master must replace it or bubble failure upward
- attempts are recorded in the event log, not by creating retry child nodes

## Storage Layout

Store tasks under the existing root:

`~/.local/nvim-vibe/tasks/<project>/<task>/`

Each root task directory becomes the root of a task subtree.

Example:

```text
~/.local/nvim-vibe/tasks/<project>/<task>/
  node.md
  events.jsonl
  children/
    01-plan/
      node.md
    02-execute/
      node.md
      children/
        01-subtask-a/
          node.md
        02-subtask-b/
          node.md
```

### Why Tree-Shaped Directories

- mirrors the algebra naturally
- easy to inspect in Neovim
- good fit for summaries and manual catch-up
- keeps subtree context local
- composite ownership is visually obvious

### Why Markdown Nodes

Use Markdown from the start.

Pros:

- human-readable
- natural place for task summary
- natural place for planner output and operator notes
- good fit for overview/catch-up workflow
- easy to inspect and edit in Neovim

Cons if used alone:

- high-churn runtime history is awkward in Markdown
- append-only audit logs become noisy
- derived status should not be reconstructed from prose only

Therefore:

- `node.md` stores current node snapshot + summary
- `events.jsonl` stores append-only runtime history

## Node Document Format

Each node should have a `node.md` with frontmatter for machine state and a body for human-readable summary.

### Suggested v1 Frontmatter Schema

Early v1 fields:

```yaml
id: task_123
kind: sequence | parallel | agent
title: string
status: planned | ready | running | waiting_review | blocked | completed | failed | cancelled
runtime_state: Planned | Active | Reviewing | Done | Failed | Cancelled
block_reason:
parent_id: task_122 | null
position: 0
index: 1                # sequence only
on_error: fail_fast     # sequence/parallel only
master:                 # sequence/parallel only
  backend: opencode
  agent: plan
agent:                  # leaf only
  backend: opencode
  role: coder
source_task: /abs/path/to/source.md
attempt_count: 0
summary_updated_at: 2026-05-06T12:00:00Z
updated_at: 2026-05-06T12:00:00Z
```

Notes:

- `status` is cached derived state for fast sidebar rendering
- `runtime_state` is the primary operational state
- `block_reason` should be explicit when `status = blocked`
- `attempt_count` supports same-identity retries
- `master` is present only on composite nodes
- `agent` is present only on leaf nodes

Example:

```md
---
id: task_123
kind: sequence
title: Implement OpenCode integration
status: waiting_review
parent_id:
position: 0
index: 1
on_error: fail_fast
master:
  backend: opencode
  agent: plan
summary_updated_at: 2026-05-06T12:00:00Z
---

# Summary

Planner proposed two phases:
1. Build event bridge
2. Add runtime tree to sidebar

## Blocked

Waiting for plan approval.
```

### Rule Of Thumb

- frontmatter = latest machine snapshot
- body = latest summary and high-signal notes
- `events.jsonl` = full append-only history

## Event Log

Each root task should have an append-only `events.jsonl` log.

### Suggested v1 Event Envelope

Each line should be one JSON object.

```json
{
  "id": "evt_123",
  "time": "2026-05-06T12:00:00Z",
  "task_id": "task_123",
  "type": "plan_proposed",
  "actor": {
    "kind": "session",
    "id": "sess_123",
    "role": "master"
  },
  "payload": {}
}
```

Recommended common envelope fields:

- `id`
- `time`
- `task_id`
- `type`
- `actor`
- `payload`

Optional fields when relevant:

- `parent_task_id`
- `session_id`
- `backend`
- `attempt`
- `caused_by`

Likely event types:

- `node_created`
- `node_status_changed`
- `session_attached`
- `plan_proposed`
- `plan_approved`
- `plan_rejected`
- `question_asked`
- `question_answered`
- `permission_asked`
- `permission_replied`
- `review_accept`
- `review_retry`
- `review_replace`
- `mutation_insert`
- `mutation_remove`
- `mutation_replace`
- `mutation_set_index`
- `summary_updated`
- `node_completed`
- `node_failed`

The event log is the audit trail. The node file is the current readable snapshot.

### Suggested v1 Priority Events

Start with these first:

- `node_created`
- `node_status_changed`
- `session_attached`
- `plan_proposed`
- `plan_approved`
- `plan_rejected`
- `question_asked`
- `question_answered`
- `permission_asked`
- `permission_replied`
- `review_accept`
- `review_retry`
- `review_replace`
- `summary_updated`
- `node_completed`
- `node_failed`

Mutation-specific events can follow immediately after the basic loop works.

## Runtime Sessions

Task nodes and execution sessions are separate.

### Task Tree

Contains only:

- `Agent`
- `Sequence`
- `Parallel`

### Runtime Sessions

Backends create sessions linked to nodes:

- one worker session for an active leaf `Agent`
- one master session for an active composite when it is planning/reviewing/mutating

This means masters are semantically first-class, but not represented as child nodes.

## Planner-First Workflow

The first step of orchestration is always planning.

### UX Flow

1. User opens project tasks
2. User selects a root task
3. User presses `Solve`
4. `nvim-vibe` creates runtime root for that task
5. Planning master session starts
6. Planner reads the task and proposes a plan/task tree
7. `nvim-vibe` shows the proposal and marks the task `waiting_review`
8. User approves or rejects
9. On approval, the tree is materialized and execution begins

### Why Planner First

- produces a better operator UX
- creates a reviewable subtree before execution starts
- provides a natural checkpoint for the human
- keeps task mutation explicit rather than hidden in logs

## Scheduling Model

`nvim-vibe` should schedule nodes based on derived readiness.

### Sequence

- `index` is the next child position to run
- children before `index` are accepted and complete
- child after `index` may not run yet
- `index` is persisted state, not inferred by counting completed children

### Parallel

- children may run independently
- multiple children may be active at once
- master owns result fan-in and review

### Mutation

Allowed early mutations:

- insert child
- remove child
- replace child
- set sequence index
- change master

Mutations must be explicit, auditable, and reflected in the event log.

## OpenCode Integration

OpenCode is the first execution backend.

### Role Of OpenCode

- run planner/master sessions
- run worker leaf sessions
- report important runtime events back to `nvim-vibe`

OpenCode should not be the source of truth for the task tree.

### Integration Strategy

Use OpenCode as a session backend, not as the orchestration engine.

- avoid OpenCode subagent tree as canonical structure
- let `nvim-vibe` spawn separate top-level sessions for algebra nodes
- map backend events into `nvim-vibe` task events

### Reporting Channels

Use two channels:

1. Plugin event forwarding
2. Custom semantic tools

These should be implemented together, but custom semantic tools matter more than plugin hooks for v1 correctness.

#### Plugin Event Forwarding

Useful events to forward:

- `session.created`
- `session.status`
- `session.updated`
- `session.idle`
- `session.error`
- `permission.asked`
- `permission.replied`

These are useful for notifications and session visibility.

#### Custom Semantic Tools

Use app-specific tools for high-level meaning:

- `nvim_report_plan`
- `nvim_report_status`
- `nvim_report_blocked`
- `nvim_report_question`
- `nvim_report_result`

These tools let the runtime tell `nvim-vibe` things like:

- a plan is ready
- the task is blocked on user input
- the task needs permission attention
- the worker finished with a result
- the master proposes a subtree mutation

### Reliability Goal

The main goal is not strong sandbox security.
The goal is reliable operator awareness.

In practice this means:

- if an agent needs input, `nvim-vibe` should know
- if an agent hits a permission prompt, `nvim-vibe` should know
- if a planner produced a proposal, `nvim-vibe` should know
- if a session failed or completed, `nvim-vibe` should know

## Notifications v1

Use both:

- `vim.notify` for immediate attention
- sidebar markers for persistent overview

`vim.notify` is enough for v1. More advanced notification UIs can come later.

## Sidebar Evolution

The sidebar should evolve from:

- projects
- project tasks
- worktrees

to:

- projects
- project tasks
- task runtime trees
- status indicators
- blocked reasons
- solve/review actions

### Sidebar Task Actions

Initial actions:

- open task
- toggle done for plain tasks
- solve task
- approve plan
- reject plan
- refresh runtime view

Suggested key for solve:

- `s` on selected root task

### Display Hints

Per node show compactly:

- kind marker: `A`, `S`, `P`
- title
- status
- blocked marker if relevant

## Notifications

Notifications matter because `nvim-vibe` is an overview tool.

Trigger notifications on transitions into:

- `waiting_review`
- `blocked(question)`
- `blocked(permission)`
- `failed`
- `completed`

These should be derived from runtime state changes, not guessed from raw backend logs.

## Runtime Adapter Requirements

Any backend adapter should preserve these semantics:

- stable node identity
- explicit review model
- explicit sequence cursor behavior
- auditable mutations
- pause/resume for review
- enough traceability to explain state changes

OpenCode is first, but the design should remain backend-agnostic.

## Module Direction

Likely new modules:

- `nvim-vibe.tasks` for filesystem task roots and node docs
- `nvim-vibe.task_tree` for node structure and child management
- `nvim-vibe.task_runtime` for primary state + derived status
- `nvim-vibe.task_events` for append-only event log
- `nvim-vibe.opencode` for backend session adapter
- `nvim-vibe.notify` for notifications

## Implementation Phases

### Phase 1: Task Root Storage

- move directly from flat task markdown files to root task directories
- add `node.md` format
- do not spend time on migration compatibility
- breaking storage changes are acceptable in v2

### Phase 2: Runtime Tree + Status Engine

- add node identities
- add runtime state model
- add derived status computation
- add `events.jsonl`

### Phase 3: Sidebar Runtime View

- render task subtrees
- show status markers
- show blocked reasons
- add `Solve` action

### Phase 4: Planner Workflow

- create planner root session
- ingest plan proposal
- wait for human review
- materialize approved subtree

### First End-To-End Target

Do not start with full parallel orchestration.

First milestone should be:

- root task
- planner session
- plan approval
- execution of a simple `Sequence`
- question/permission notifications
- completion/failure reporting

Once that loop is stable, add `Parallel` scheduling and subtree mutation UI.

### Phase 5: OpenCode Backend

- start OpenCode sessions for master/worker nodes
- forward plugin session events
- add custom reporting tools
- map backend reports into runtime events

### Phase 6: Notifications + Review Flow

- notify on blocked states
- notify on plan approval needed
- notify on question/permission requests
- support retry/replace/bubble review actions

### Phase 7: Parallel And Mutation

- start multiple ready children for `Parallel`
- allow explicit subtree mutation
- keep auditability and sequence cursor rules intact

## Key Design Decisions

- **Projects** stay configured in `~/.local/nvim-vibe/projects.lua`
- **Task roots** live under `~/.local/nvim-vibe/tasks/<project>/<task>/`
- **Task tree** is filesystem-shaped by directories
- **Node snapshot** lives in `node.md`
- **History** lives in `events.jsonl`
- **No migration work** is required for legacy flat task storage
- **Master** belongs to composite node metadata, not child list
- **Retry** keeps child identity and uses event history for attempts
- **Leaf errors** enter review first
- **OpenCode** is a backend adapter, not the canonical task model
- **OpenCode bridge v1** uses plugin event forwarding and custom semantic tools
- **Notifications v1** use `vim.notify` plus sidebar markers
- **Notifications** are based on derived state transitions

## Non-Goals For Early v2

- adding new algebra forms beyond `Agent`, `Sequence`, `Parallel`
- making approvals a first-class task form
- using OpenCode subagent trees as canonical state
- building a perfect security/middleware layer before overview UX exists

## Guiding Principle

Prefer a small, explicit task algebra with strong overview semantics.

If behavior feels missing, first improve:

- derived status
- runtime policy
- summaries
- notifications
- backend adapters

Only add new ontology if those levers are insufficient.
