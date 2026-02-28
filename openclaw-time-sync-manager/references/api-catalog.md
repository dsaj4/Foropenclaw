# API Catalog (Official SuperSync)

This reference describes the actual endpoints exposed by `https://sync.super-productivity.com`.

## Critical Multi-Client Visibility Rules

1. `GET /api/sync/ops` must include `sinceSeq` (`sinceSeq=0` on first pull).
2. Calling `/api/sync/ops` without `sinceSeq` is invalid and should be treated as a failed run.
3. Mutation success is determined by op-log evidence:
- upload response `results[].accepted=true`
- post-pull `/api/sync/ops` contains target `entityId`
4. Never use only `snapshot.state.task.ids` to decide create/update failure.
5. If snapshot is used for rendering, normalize both `state.task` and `state.TASK`, then dedupe by `taskId`.
6. Required mutation cycle:
- pre-pull (with `sinceSeq`) -> upload -> post-pull (with `sinceSeq`) -> verify in ops.

## Canonical API Profile

- Base URL: `https://sync.super-productivity.com`
- Protocol: HTTPS REST (JSON)
- Auth: `Authorization: Bearer <token>`
- Main prefix: `/api/sync/*`
- Health endpoint: `/health`
- Important: There is no official `/v1/tasks` or `/v1/connect` on this host.

## 1) Health and Auth Context

### `GET /health`

Purpose: server liveness and DB connectivity check.

Auth: none.

Typical response:

- `status`
- `db`

---

### Auth model for sync endpoints

All `/api/sync/*` endpoints require:

- `Authorization: Bearer <token>`

Without token or with invalid token: `401`.

## 2) Core Sync Endpoints

### `GET /api/sync/status`

Purpose: inspect sync state and quota.

Output:

- `latestSeq`
- `devicesOnline`
- `storageUsedBytes`
- `storageQuotaBytes`

---

### `GET /api/sync/ops?sinceSeq={seq}&limit={limit}&excludeClient={clientId}`

Purpose: download incremental operations.

Use when:

- pre-write pull
- post-write verification pull
- normal refresh

Output:

- `ops[]`
- `hasMore`
- `latestSeq`
- optional `gapDetected`
- optional `latestSnapshotSeq`
- optional `snapshotVectorClock`
- optional `serverTime`

Hard requirement:

- requests without `sinceSeq` are invalid for this workflow.

---

### `POST /api/sync/ops`

Purpose: upload operations (create/update/delete/move/batch/full-state ops).

Body:

- `clientId`
- `ops[]`
- optional `lastKnownServerSeq`
- optional `requestId` (dedup for retries)

Operation shape (per item):

- `id`
- `clientId`
- `actionType`
- `opType` (`CRT|UPD|DEL|MOV|BATCH|SYNC_IMPORT|BACKUP_IMPORT|REPAIR`)
- `entityType` (for task use `TASK`)
- `entityId` (or `entityIds` for bulk)
- `payload`
- `vectorClock`
- `timestamp`
- `schemaVersion`

Output:

- `results[]` (`accepted`, `serverSeq`, `opId`)
- `latestSeq`

## 3) Snapshot and Maintenance Endpoints

### `GET /api/sync/snapshot`

Purpose: fetch full snapshot.

---

### `POST /api/sync/snapshot`

Purpose: upload full snapshot (migration/recovery/initialization).

---

### `DELETE /api/sync/data`

Purpose: destructive reset of all sync data for authenticated user.

Use only on explicit destructive user request.

---

### `GET /api/sync/restore-points?limit={n}`

Purpose: list restore points.

---

### `GET /api/sync/restore/{serverSeq}`

Purpose: reconstruct snapshot at a given sequence.

## 4) Task Semantics on Official API

There is no direct task CRUD REST endpoint on this host.

Task operations must be encoded through:

- `POST /api/sync/ops` with `entityType: "TASK"`
- `opType` chosen by intent:
  - create -> `CRT`
  - update/complete/reopen -> `UPD`
  - delete -> `DEL`

Task intent to op mapping:

- create task -> `actionType: [Task Shared] addTask`, `opType: CRT`
- update title/notes/due -> `actionType: [Task Shared] updateTask`, `opType: UPD`
- complete/reopen -> `actionType: [Task Shared] updateTask`, `opType: UPD`
- delete task -> delete action type, `opType: DEL`

Read task state via:

- downloaded operations (`GET /api/sync/ops`) and/or snapshot (`GET /api/sync/snapshot`)
- then materialize to local task view.

Read priority:

1. Primary: op-log from `GET /api/sync/ops`
2. Fallback: snapshot (`GET /api/sync/snapshot`) with normalization for both `task` and `TASK`
3. Do not use `snapshot.state.task.ids` alone as success/failure criterion

## 5) Encoding and Verification Rules

1. For non-ASCII text (Chinese, etc.):
- send `Content-Type: application/json; charset=utf-8`
- send body as UTF-8 bytes
2. Always send `requestId` on mutation uploads.
3. Mutation loop must be: pull -> upload ops -> pull.
4. Verify target fields after write (`title`, `notes`, `dueWithTime`/`dueDay`).
5. If verification fails (mojibake or wrong final state), do one corrective `UPD` and verify again.

## 6) Minimal Mutation Example (Task Create)

`POST /api/sync/ops` body outline:

```json
{
  "clientId": "your_client_id",
  "requestId": "req_xxx",
  "ops": [
    {
      "id": "uuid",
      "clientId": "your_client_id",
      "actionType": "[Task Shared] addTask",
      "opType": "CRT",
      "entityType": "TASK",
      "entityId": "task_xxx",
      "payload": {
        "actionPayload": {
          "task": {
            "id": "task_xxx",
            "title": "Dinner at 6 PM"
          }
        },
        "entityChanges": []
      },
      "vectorClock": {
        "your_client_id": 1
      },
      "timestamp": 1772180000000,
      "schemaVersion": 2
    }
  ]
}
```

## 7) Agent Execution Checklist

1. `GET /api/sync/status` to confirm auth and service state.
2. `GET /api/sync/ops?sinceSeq=<lastSeq>&limit=<n>` to pull latest state and clocks.
3. Build one valid `TASK` operation with required fields.
4. `POST /api/sync/ops` with `requestId` and UTF-8 body.
5. Ensure upload response has `results[0].accepted = true`.
6. Pull again with `GET /api/sync/ops` and verify:
- returned `latestSeq` advanced
- target `entityId` op exists
- target fields (`title`, `notes`, `dueWithTime`/`dueDay`) are correct
7. If mismatch, send one corrective `UPD` and verify again.
8. If snapshot is needed for display, merge `state.task` and `state.TASK`, dedupe by `taskId`, then render.
9. If any pre-pull/post-pull call omitted `sinceSeq`, mark the run invalid and rerun from step 1.

## 8) Troubleshooting: Created But Not Displayed

Symptom:

- upload returns `accepted: true`, but custom viewer still shows "not created".

Checks:

1. Confirm endpoint path is `/api/sync/*` (not `/v1/*`).
2. Confirm op is present in `GET /api/sync/ops` with expected `entityId/title`.
3. If snapshot-based parser fails or result looks stale, inspect snapshot for mixed `task` and `TASK` keys.
4. In that case, use op-log (`/api/sync/ops`) as source of truth for mutation verification.
