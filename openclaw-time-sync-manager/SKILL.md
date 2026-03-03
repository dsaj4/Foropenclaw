---
name: openclaw-time-sync-manager
description: "Use this skill to execute time/task commands with token-only API sync between local and cloud data."
homepage: "https://github.com/super-productivity/super-productivity"
user-invocable: true
disable-model-invocation: false
metadata: '{"openclaw":{"homepage":"https://github.com/super-productivity/super-productivity","requires":{"bins":["curl"],"env":["SUPERSYNC_TOKEN"]},"primaryEnv":"SUPERSYNC_TOKEN","install":[{"id":"curl-brew","kind":"brew","formula":"curl","bins":["curl"],"label":"Install curl (brew)"},{"id":"curl-download","kind":"download","url":"https://curl.se/download.html","label":"Download curl"}]}}'
---

# OpenClaw Time Sync Manager

Token-only SuperSync workflow for creating/updating tasks safely across multiple clients.

## Protocol

1. Base URL: `https://sync.super-productivity.com`
2. Auth: `Authorization: Bearer <SUPERSYNC_TOKEN>`
3. Prefix: `/api/sync/*`
4. Do not use `/v1/*` or `/api/v1/*` on this host.

Reference: `{baseDir}/references/api-catalog.md`

## Trigger Conditions

Use this skill when user intent is task/time sync related:

1. Explicit: create/update/complete/reopen/delete task, sync now, periodic sync.
2. Implicit: commitment + schedule cue (for example "明天上午10点写作业") -> create task.
3. If ambiguity is high (multiple candidate tasks or unclear date), ask one concise clarification.

## Critical Rules (Must Follow)

1. `GET /api/sync/ops` must always include `sinceSeq`.
2. Every mutation must run this sequence:
   `pre-pull(with sinceSeq) -> upload -> post-pull(with sinceSeq) -> verify in ops`.
3. Mutation success is judged by op-log:
   `POST /api/sync/ops` accepted + post-pull contains target `entityId`.
4. Never judge failure only from `snapshot.state.task.ids`.
5. Use UTF-8 body bytes for non-ASCII text.
6. Use `requestId` for idempotency.
7. Build vector clock from latest server clocks before each mutation.
8. If clock merge fails, abort mutation (`VECTOR_CLOCK_NOT_MERGED`).

## Required Environment

1. `SUPERSYNC_TOKEN` (primary env)
2. Default runtime values:
   - `baseUrl = https://sync.super-productivity.com`
   - `clientId = derived from token/host`

## Runtime Workflow

1. Parse intent.
2. Pre-pull: `GET /api/sync/ops?sinceSeq=<lastSeq>&limit=<n>`.
3. Build merged vector clock (see next section).
4. Upload mutation via `POST /api/sync/ops`.
5. Post-pull: `GET /api/sync/ops?sinceSeq=<preLatestSeq>&limit=<n>`.
6. Verify target `entityId` and expected fields.
7. Persist new `lastSeq`.

If conflict/rejection occurs: pull latest -> merge once -> retry once -> if still failing, return conflict report.

## Vector Clock Hard Rule

### Construction

1. Start empty clock.
2. Merge `snapshotVectorClock` (if present).
3. Merge every returned `op.vectorClock`.
4. Merge rule: keep max counter per key.
5. Ensure current `clientId` exists, then increment by `+1`.
6. Use resulting clock for outgoing op(s).

### Invalid Patterns (Reject)

1. Isolated clock like `{ "<clientId>": 1 }` while server has history.
2. Upload without pre-pull.
3. Counter rollback/reset.

### Quality Gate

1. If server known clock has other keys, outgoing clock must not be single-key.
2. Outgoing included counters must not be less than observed counters.
3. On failure: stop and return `VECTOR_CLOCK_NOT_MERGED`.

## Operation Contract

Each task mutation op must include:

1. `id`
2. `clientId` (same as request-level `clientId`)
3. `actionType`: `[Task Shared] addTask` or `[Task Shared] updateTask`
4. `opType`: `CRT|UPD|DEL`
5. `entityType`: `TASK`
6. `entityId`: task id
7. `payload`: `actionPayload + entityChanges` envelope
8. `vectorClock`: merged clock
9. `timestamp`: epoch ms
10. `schemaVersion`: latest observed (normally `2`)

`POST /api/sync/ops` request fields:

1. `clientId`
2. `ops` (1..100)
3. `lastKnownServerSeq` (recommended)
4. `requestId` (recommended)

## Minimal PowerShell Template

```powershell
$base = "https://sync.super-productivity.com"
$token = $env:SUPERSYNC_TOKEN
$clientId = "openclaw_cli_demo"
$headers = @{
  Authorization = "Bearer $token"
  "Content-Type" = "application/json; charset=utf-8"
}

function Merge-SuperSyncVectorClock {
  param(
    [Parameter(Mandatory = $true)] $PrePullResponse,
    [Parameter(Mandatory = $true)] [string] $ClientId
  )
  $merged = @{}
  if ($PrePullResponse.snapshotVectorClock) {
    $PrePullResponse.snapshotVectorClock.PSObject.Properties | ForEach-Object {
      $k = $_.Name; $v = [int]$_.Value
      if (-not $merged.ContainsKey($k) -or $merged[$k] -lt $v) { $merged[$k] = $v }
    }
  }
  foreach ($row in ($PrePullResponse.ops | Where-Object { $_.op -and $_.op.vectorClock })) {
    $row.op.vectorClock.PSObject.Properties | ForEach-Object {
      $k = $_.Name; $v = [int]$_.Value
      if (-not $merged.ContainsKey($k) -or $merged[$k] -lt $v) { $merged[$k] = $v }
    }
  }
  if (-not $merged.ContainsKey($ClientId)) { $merged[$ClientId] = 0 }
  $merged[$ClientId] = [int]$merged[$ClientId] + 1
  return $merged
}

# Pre-pull
$lastSeq = 0
$pre = Invoke-RestMethod -Uri "$base/api/sync/ops?sinceSeq=$lastSeq&limit=200" -Headers $headers -Method Get
$clock = Merge-SuperSyncVectorClock -PrePullResponse $pre -ClientId $clientId

# Gate: reject isolated clock when server already has history
$knownKeys = @()
if ($pre.snapshotVectorClock) { $knownKeys = @($pre.snapshotVectorClock.PSObject.Properties.Name) }
if ($knownKeys.Count -gt 0 -and $clock.Keys.Count -le 1) {
  throw "VECTOR_CLOCK_NOT_MERGED"
}
```

## Mutation Verification Rules

After upload, require all:

1. `results[].accepted=true`
2. post-pull includes target `entityId`
3. fields match expected (`title`, `notes`, `dueWithTime` or `dueDay`)

If any fail, mark mutation as failed and report diagnostic data.

## Safety Limits

1. Do not use full snapshot overwrite for normal task CRUD.
2. Do not call destructive reset (`DELETE /api/sync/data`) unless explicitly requested.
3. If post-write verification fails, allow one corrective `UPD` then re-verify once.

## Response Format

For every mutation response include:

1. `action`
2. `target` (task id/title)
3. `sync` (latest seq + verification status)
4. `trace` (`requestId`, `opId`)

## OpenClaw Config Example

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

## Validation Checklist

1. `openclaw skills list` shows this skill loaded.
2. `GET /api/sync/status` succeeds with auth.
3. Every mutation log contains pre-pull, upload, post-pull.
4. `GET /api/sync/ops` calls always include `sinceSeq`.
5. Debug log for mutation includes:
   - source clock summary (`snapshotVectorClock` size, ops count)
   - merged clock size and local counter
   - quality gate pass/fail
