---
name: obsidian-livesync-couchdb-agent
description: Deploy and operate a CouchDB instance compatible with Obsidian Self-hosted LiveSync, and perform safe, revision-aware remote document edits from a server-side agent. Use when asked to set up LiveSync-ready CouchDB, inspect/patch/delete specific CouchDB docs, compute LiveSync document IDs from Obsidian paths, or enforce guardrails while remotely managing a vault via CouchDB.
---

# Obsidian LiveSync CouchDB Agent

## Overview

Use this skill to: (1) provision a CouchDB server with LiveSync-required settings, and (2) modify remote docs safely with strict `_rev` handling and backup-first workflow.
Always treat direct content mutation as high risk unless the request explicitly asks for low-level database changes.

## Quick Start

1. Ensure server prerequisites: `docker`, `curl`, and Python 3.
2. Provision CouchDB (single-node):
   - generate stack: `scripts/render_couchdb_stack.sh`
   - apply LiveSync config: `scripts/init_livesync_couchdb.sh`
3. Inspect or edit remote docs using:
   `scripts/livesync_couchdb_tool.py`
4. Load references for safety rules and document semantics:
   - `references/livesync-couchdb-requirements.md`
   - `references/livesync-doc-guardrails.md`
   - `references/rollback-mechanism.md`
   - `references/server-agent-prompt-template.md`

## Workflow

### 1) Prepare Environment Variables

Set at least:
- `COUCH_URL` (example: `http://127.0.0.1:5984`)
- `COUCH_USER`
- `COUCH_PASSWORD`
- `COUCH_DB`

### 2) Initialise CouchDB for LiveSync

Run:
```bash
bash scripts/init_livesync_couchdb.sh
```

Override defaults by exporting:
- `COUCH_BIND_ADDRESS` (default `0.0.0.0`)
- `COUCH_NODE` (default `_local`)
- `COUCH_ORIGINS` (default `app://obsidian.md,capacitor://localhost,http://localhost`)
- `COUCH_REQUIRE_VALID_USER` (default `true`)

### 3) Operate Documents with Revision Safety

List docs:
```bash
python scripts/livesync_couchdb_tool.py list --url "$COUCH_URL" --user "$COUCH_USER" --password "$COUCH_PASSWORD" --db "$COUCH_DB" --limit 30
```

Backup before edit:
```bash
python scripts/livesync_couchdb_tool.py backup-all --url "$COUCH_URL" --user "$COUCH_USER" --password "$COUCH_PASSWORD" --db "$COUCH_DB" --out backup.json
```

Patch one field by id:
```bash
python scripts/livesync_couchdb_tool.py patch --url "$COUCH_URL" --user "$COUCH_USER" --password "$COUCH_PASSWORD" --db "$COUCH_DB" --id "syncinfo" --set "value=new-random-token"
```

Delete one doc:
```bash
python scripts/livesync_couchdb_tool.py delete --url "$COUCH_URL" --user "$COUCH_USER" --password "$COUCH_PASSWORD" --db "$COUCH_DB" --id "<DOC_ID>"
```

### 4) Use Rollback-Enforced Change Path (Recommended)

Do not run direct `patch/delete` in production paths.

Safe patch:
```bash
bash scripts/safe_change.sh patch --id "syncinfo" --set "value=new-random-token"
```

Safe delete:
```bash
bash scripts/safe_change.sh delete --id "<DOC_ID>"
```

Rollback by manifest:
```bash
python3 scripts/rollback_change.py --manifest "<path-to-manifest.json>" --url "$COUCH_URL" --user "$COUCH_USER" --password "$COUCH_PASSWORD"
```
### 5) Resolve Obsidian Path to LiveSync Doc ID

Compute `_id` from a vault path:
```bash
python scripts/livesync_couchdb_tool.py path2id --path "Notes/Todo.md" --case-insensitive
```

If path obfuscation is enabled in plugin settings:
```bash
python scripts/livesync_couchdb_tool.py path2id --path "Notes/Todo.md" --case-insensitive --obfuscate-passphrase "<PATH_OBFUSCATION_PASSPHRASE>"
```

## Decision Rules

- Refuse blind bulk rewrites of `leaf` (chunk) docs unless user explicitly accepts data-corruption risk.
- Prefer metadata-only changes or operational docs (`syncinfo`, versioning, lock/milestone) for remote control tasks.
- Always fetch latest `_rev` immediately before `PUT` or `DELETE`.
- Always produce a backup file before destructive actions.
- For production change requests, use `scripts/safe_change.sh` and keep its manifest file.
- Never reset or drop DB unless explicitly asked.

## Resources

### scripts/
- `scripts/render_couchdb_stack.sh`: generate a Docker Compose stack scaffold for CouchDB.
- `scripts/init_livesync_couchdb.sh`: configure CouchDB for LiveSync via REST API.
- `scripts/livesync_couchdb_tool.py`: list/get/backup/patch/delete docs and compute LiveSync path-based `_id`.
- `scripts/safe_change.sh`: enforce backup + snapshot + manifest before patch/delete.
- `scripts/rollback_change.py`: rollback a single safe change using manifest and latest `_rev`.

### references/
- `references/livesync-couchdb-requirements.md`: required CouchDB and CORS settings for plugin compatibility.
- `references/livesync-doc-guardrails.md`: safe edit boundaries for LiveSync document types.
- `references/rollback-mechanism.md`: rollback strategy and operating rules.
- `references/server-agent-prompt-template.md`: prompt template for server-side automation agent.
