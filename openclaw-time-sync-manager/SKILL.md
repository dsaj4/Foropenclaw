---
name: openclaw-time-sync-manager
description: "Use this skill to execute time-management commands with token-only API sync between local and cloud data."
homepage: "https://github.com/super-productivity/super-productivity"
user-invocable: true
disable-model-invocation: false
metadata: '{"openclaw":{"homepage":"https://github.com/super-productivity/super-productivity","requires":{"bins":["curl"],"env":["SUPERSYNC_TOKEN"]},"primaryEnv":"SUPERSYNC_TOKEN","install":[{"id":"curl-brew","kind":"brew","formula":"curl","bins":["curl"],"label":"Install curl (brew)"},{"id":"curl-download","kind":"download","url":"https://curl.se/download.html","label":"Download curl"}]}}'
---

# OpenClaw Time Sync Manager

This skill manages time/task commands by keeping local and cloud state consistent through a sync-first API workflow.

Protocol profile used by this skill:

- Base URL: `https://sync.super-productivity.com`
- Protocol: HTTPS REST (JSON)
- Auth: `Authorization: Bearer <token>`
- Sync path prefix: `/api/sync/*`
- Important: Official SuperSync does **not** provide `/v1/tasks` or `/v1/connect`

Reference file:

- `{baseDir}/references/api-catalog.md`

## Trigger Conditions

Use this skill when user intent includes explicit commands OR implicit planning statements.

Explicit intents:

- creating/updating/completing/reopening/deleting tasks
- requesting today/weekly schedule
- asking for "sync now"
- enabling/disabling/changing periodic sync

Implicit intents (auto-convert to task operations):

- user states a future commitment: "I need to ...", "I have to ...", "I should ..."
- user states a time-bound plan: "tomorrow morning", "next Monday", "at 10am", "before 5pm"
- user states agenda-like items: "today I will ...", "this week I must ..."
- user states reminders in natural language: "remind me to ...", "don't let me forget ..."

Default behavior for implicit intents:

1. If statement contains actionable work + time cue, treat as `create task`.
2. If statement references an existing task and status cue ("done", "finished", "延期"), treat as update/complete.
3. If ambiguity is low, execute automatically.
4. If ambiguity is high (multiple candidate tasks, unclear date), ask one concise clarification question.

## Intent Recognition Heuristics

A sentence should be treated as actionable task intent when all are true:

1. Contains an action verb or work noun (write, prepare, submit, meeting, homework, report, review, call).
2. Contains a subject implied as user self-commitment ("I", "我", omitted first-person plan statement).
3. Contains at least one scheduling or priority cue (date/time, "today", "tomorrow", "this week", "urgent", "before ...").

If time is present but title is implicit, derive concise title from predicate phrase.

Example:

- Input: "我明天上午10点要写作业"
- Extracted intent:
  - title: `写作业`
  - dueWithTime: tomorrow 10:00 (local timezone)
  - operation: `POST /api/sync/ops` with `opType=CRT`, `entityType=TASK` (with pre/post sync)

If date is present without exact time ("明天上午"), map to default time `10:00`.
If only date is present ("明天"), set `dueDay` and leave `dueWithTime` empty.

## Required Environment

The skill requires only:

- `SUPERSYNC_TOKEN`

`SUPERSYNC_TOKEN` is the `primaryEnv` and can be injected by `skills.entries.<skill>.apiKey`.

Defaults used by the skill runtime:

- `baseUrl`: `https://sync.super-productivity.com` (unless runtime overrides it)
- `clientId`: auto-generated from token claims and host fingerprint (no manual config needed)

## Runtime Workflow

Apply this fixed execution loop:

1. `Intent -> Plan -> API -> Verify -> Respond`
2. Before every write: run `GET /api/sync/ops` with current `sinceSeq`
3. Write via `POST /api/sync/ops`
4. After write: run `GET /api/sync/ops` again to verify server sequence progression
5. Use idempotency key (`requestId`) for mutations
6. Build mutation vector clock from latest server state (do not use stale local clock)
7. On conflict: pull latest -> merge once -> retry once

If retry still fails, return a conflict report and stop mutation.

State handling:

1. Persist `lastSeq` locally after every successful pull/upload.
2. If `lastSeq` is unknown (first run), use `sinceSeq=0`.
3. If server returns `gapDetected`, fetch/apply snapshot then continue from snapshot sequence.

## Operation Contract (Do Not Omit)

Every uploaded operation for task changes must include:

1. `id` (UUID)
2. `clientId` (same as request-level `clientId`)
3. `actionType` (for task: `[Task Shared] addTask` or `[Task Shared] updateTask`)
4. `opType` (`CRT` for create, `UPD` for update/complete/reopen, `DEL` for delete)
5. `entityType` = `TASK`
6. `entityId` = target task id
7. `payload` using `actionPayload` + `entityChanges` envelope
8. `vectorClock` (merged from latest known server clocks)
9. `timestamp` (epoch ms)
10. `schemaVersion` (use latest observed server schema when available)

Request-level fields for `POST /api/sync/ops`:

1. `clientId`
2. `ops` (1..100)
3. optional `lastKnownServerSeq`
4. optional but recommended `requestId`

## Encoding Rules (Mandatory)

For any request containing non-ASCII text (for example Chinese task title/notes):

1. Send `Content-Type: application/json; charset=utf-8`
2. Send request body as UTF-8 bytes (not platform-default string encoding)
3. After mutation, re-read the task and verify text fields are not mojibake/replacement chars

## API Auto-Call Rules

### A) Query command

1. If cache is stale or user asks to refresh: `GET /api/sync/ops`
2. Build task view from synced operations / snapshot-derived local state
3. Return normalized schedule/task result

### B) Mutation command

1. `GET /api/sync/ops` (pre-pull)
2. `POST /api/sync/ops` (task create/update/complete/reopen encoded as operations)
3. `GET /api/sync/ops` (post-pull)
4. Verify by `taskId` that key fields (`title`, `notes`, `dueWithTime`/`dueDay`) match expected values
5. Return `opId` / `serverSeq` and verification status

For implicit creation intents, this sequence is mandatory and should run automatically without asking for API confirmation.

### C) Manual sync command

1. Run `GET /api/sync/ops` and `POST /api/sync/ops` cycle once
2. Return fetched/applied/uploaded operation counts

### D) Periodic sync command

1. Schedule local timer in agent runtime
2. On each tick execute manual sync cycle (`GET /api/sync/ops` + `POST /api/sync/ops` when needed)
3. Persist last run state locally

## Safety Limits

1. Do not use full snapshot overwrite APIs for normal task operations.
2. Do not delete all sync data unless user explicitly requests destructive reset.
3. If task target is ambiguous, query candidates first, then ask disambiguation.
4. If post-write verification fails (encoding mismatch or wrong final state), issue one corrective `UPD` and verify again.

## Response Format

For every mutation response include:

- `action`: operation performed
- `target`: task id/title
- `sync`: latest sequence and verification result
- `trace`: `requestId` and `opId` (if returned)

## OpenClaw Config Example

Use `~/.openclaw/openclaw.json`:

```json
{
  "skills": {
    "entries": {
      "openclaw-time-sync-manager": {
        "enabled": true,
        "apiKey": "YOUR_SUPERSYNC_TOKEN"
      }
    }
  }
}
```

## Validation and Debug

1. Verify load: `openclaw skills list`
2. Verify token injection: run `GET /api/sync/status` and confirm authenticated response
3. Verify sync loop: mutation must produce `pull -> upload ops -> pull` sequence
4. Reject any plan that uses `/v1/*`, `/api/v1/*`, `/sync`, or WebSocket-only assumptions for this host

