# API Catalog

This reference defines each API used by the skill and when to call it.

## Global Request Rules

1. For non-ASCII text (for example Chinese task titles/notes), always send:
- `Content-Type: application/json; charset=utf-8`
- request body encoded as UTF-8 bytes
2. For mutation requests, always send an idempotency key (`requestId`).
3. Before mutation, refresh sync state first and build mutation clock from latest server state.
4. After mutation, re-read by `taskId` and verify key fields (`title`, `notes`, `dueWithTime`/`dueDay`).
5. If post-write verification fails, run one corrective `PATCH` and verify again.

## 1) Connection APIs

### `POST /v1/connect`

Purpose: initialize gateway settings for cloud sync.

Use when:

- session starts
- endpoint/token/clientId changes

Input:

- `baseUrl`
- `bearerToken`
- `clientId`
- `schemaVersion`

Output:

- `ok`
- `latestSeq`

---

### `GET /v1/health`

Purpose: verify gateway and cloud reachability.

Use when:

- before first task command
- troubleshooting connectivity issues

Output:

- `ok`
- `serverTime` (optional)

## 2) Sync APIs

### `GET /v1/sync/status`

Purpose: read sync metadata.

Use when:

- reporting sync health
- deciding whether cache is stale

Output:

- `latestSeq`
- `devicesOnline`
- `storageUsedBytes`
- `storageQuotaBytes`

---

### `POST /v1/sync/pull`

Purpose: pull remote operations into local DB.

Use when:

- before all writes (mandatory)
- before reads if cache stale
- after writes to verify propagation and get latest vector clock basis

Input:

- `limit` (optional)

Output:

- `latestSeq`
- `fetchedOps`
- `hasMore`

---

### `POST /v1/sync/run`

Purpose: active sync execution (manual command).

Use when:

- user asks "sync now"
- retrying after transient network errors

Input:

- `mode`: `pull_only | push_only | two_way`

Output:

- `latestSeq`
- `pushedOps`
- `fetchedOps`
- `ok`

---

### `POST /v1/sync/schedule`

Purpose: configure periodic sync.

Use when:

- user asks to enable/change timed sync

Input:

- `enabled` (boolean)
- `intervalSec` (for example 300)
- `mode` (default `two_way`)

Output:

- `enabled`
- `intervalSec`
- `nextRunAt`

---

### `GET /v1/sync/schedule`

Purpose: read periodic sync config/state.

Use when:

- user asks "is auto-sync enabled?"

Output:

- `enabled`
- `intervalSec`
- `lastRunAt`
- `nextRunAt`

---

### `DELETE /v1/sync/schedule`

Purpose: disable periodic sync.

Use when:

- user explicitly asks to stop auto-sync

Output:

- `ok`

## 3) Task Query APIs

### `GET /v1/tasks`

Purpose: query tasks from local DB/cache.

Use when:

- list tasks by status/date/project
- answer "today/this week plan"

Query:

- `status`: `open | done | all`
- `dueFrom`
- `dueTo`
- `projectId`

Output:

- `items[]` task list

---

### `GET /v1/tasks/{taskId}`

Purpose: fetch one task detail.

Use when:

- user references a single task by id
- pre-check before patch/complete/reopen

Output:

- task object

## 4) Task Mutation APIs

All mutation APIs must include idempotency semantics (`requestId` or equivalent).

### `POST /v1/tasks`

Purpose: create a task.

Use when:

- user asks to add a task

Expected behavior:

1. pre-sync pull
2. create
3. post-sync pull
4. read by `taskId` and verify stored fields

Output:

- `ok`
- `opId`
- `serverSeq`

---

### `PATCH /v1/tasks/{taskId}`

Purpose: update task fields.

Use when:

- title/date/project/tags/notes/status change

Expected behavior:

1. pre-sync pull
2. patch
3. post-sync pull
4. read by `taskId` and verify stored fields

Output:

- `ok`
- `opId`
- `serverSeq`

---

### `POST /v1/tasks/{taskId}/complete`

Purpose: mark task done.

Use when:

- user says complete/finish/done

Output:

- `ok`
- `opId`
- `serverSeq`

---

### `POST /v1/tasks/{taskId}/reopen`

Purpose: reopen done task.

Use when:

- user says reopen/undo complete

Output:

- `ok`
- `opId`
- `serverSeq`

## 5) Auto-Invocation Rules For Time Commands

1. Query command:
- stale cache -> `pull`
- then query API

2. Mutation command:
- `pull` -> mutation -> `pull`
- verify by `taskId`
- if conflict, repeat once after pull+merge
- if encoding/state mismatch, do one corrective patch + verify

3. Manual sync command:
- call `sync/run(two_way)` directly

4. Periodic sync command:
- configure with `sync/schedule` APIs

5. All responses should include:
- changed entities
- sync result (`latestSeq`)
- operation trace (`opId` or request id)
