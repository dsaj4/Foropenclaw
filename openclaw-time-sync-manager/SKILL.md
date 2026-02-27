---
name: openclaw-time-sync-manager
description: "Use this skill to execute time-management commands with API-based local/cloud database sync, including periodic sync and manual sync."
homepage: "https://github.com/super-productivity/super-productivity"
user-invocable: true
disable-model-invocation: false
metadata: '{"openclaw":{"homepage":"https://github.com/super-productivity/super-productivity","requires":{"bins":["curl"],"env":["SUPERSYNC_BASE_URL","SUPERSYNC_TOKEN","SUPERSYNC_CLIENT_ID"]},"primaryEnv":"SUPERSYNC_TOKEN","install":[{"id":"curl-brew","kind":"brew","formula":"curl","bins":["curl"],"label":"Install curl (brew)"},{"id":"curl-download","kind":"download","url":"https://curl.se/download.html","label":"Download curl"}]}}'
---

# OpenClaw Time Sync Manager

This skill manages time/task commands by keeping local and cloud state consistent through a sync-first API workflow.

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
  - operation: `POST /v1/tasks` (with pre/post sync)

If date is present without exact time ("明天上午"), map to default time `10:00`.
If only date is present ("明天"), set `dueDay` and leave `dueWithTime` empty.

## Required Environment

The skill expects these environment variables:

- `SUPERSYNC_BASE_URL`
- `SUPERSYNC_TOKEN`
- `SUPERSYNC_CLIENT_ID`

`SUPERSYNC_TOKEN` is the `primaryEnv` and can be injected by `skills.entries.<skill>.apiKey`.

## Runtime Workflow

Apply this fixed execution loop:

1. `Intent -> Plan -> API -> Verify -> Respond`
2. Before every write: run `POST /v1/sync/pull`
3. After every write: run `POST /v1/sync/pull`
4. Use idempotency key (`requestId`) for mutations
5. On conflict: pull latest -> merge once -> retry once

If retry still fails, return a conflict report and stop mutation.

## API Auto-Call Rules

### A) Query command

1. If cache is stale or user asks to refresh: `POST /v1/sync/pull`
2. Query tasks: `GET /v1/tasks` or `GET /v1/tasks/{taskId}`
3. Return normalized schedule/task result

### B) Mutation command

1. `POST /v1/sync/pull`
2. Task mutation API (`POST /v1/tasks`, `PATCH /v1/tasks/{id}`, `POST /v1/tasks/{id}/complete`, `POST /v1/tasks/{id}/reopen`)
3. `POST /v1/sync/pull`
4. Return `opId` / `serverSeq` and verification status

For implicit creation intents, this sequence is mandatory and should run automatically without asking for API confirmation.

### C) Manual sync command

1. Call `POST /v1/sync/run` with mode `two_way`
2. Return fetched/pushed counts

### D) Periodic sync command

1. Enable/change: `POST /v1/sync/schedule`
2. Read current schedule: `GET /v1/sync/schedule`
3. Disable: `DELETE /v1/sync/schedule`

## Safety Limits

1. Do not use full snapshot overwrite APIs for normal task operations.
2. Do not delete all sync data unless user explicitly requests destructive reset.
3. If task target is ambiguous, query candidates first, then ask disambiguation.

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
        "apiKey": "YOUR_SUPERSYNC_TOKEN",
        "env": {
          "SUPERSYNC_BASE_URL": "https://sync.example.com",
          "SUPERSYNC_CLIENT_ID": "obsidian_local_client"
        }
      }
    }
  }
}
```

## Validation and Debug

1. Verify load: `openclaw skills list`
2. Verify env injection: run a task command and check first API call is `/v1/connect` or `/v1/sync/status`
3. Verify sync loop: mutation must produce `pull -> mutate -> pull` sequence

