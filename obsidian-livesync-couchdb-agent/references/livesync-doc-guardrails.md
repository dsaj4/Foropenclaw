# LiveSync Document Guardrails

## Critical Principle

Treat LiveSync docs as internal replication state. Unsafe edits can stop sync or corrupt note reconstruction.

## Known IDs and Types

- Version doc: `obsydian_livesync_version`
- Sync info doc: `syncinfo`
- Sync parameters doc: `_local/obsidian_livesync_sync_parameters` (or journal variant)
- Milestone doc: `_local/obsydian_livesync_milestone`
- Note metadata types: `plain`, `newnote`, `notes` (legacy)
- Chunk type: `leaf`

## Safe-to-Modify (Relatively)

- `syncinfo` value fields used for remote checks.
- Operational toggles in milestone docs when user explicitly asks lock/unlock style actions.
- Non-content flags that the user can recover from rebuild.

## High Risk

- `leaf` chunk docs.
- `children` arrays in metadata docs.
- `type`, `_id`, path obfuscation related fields.
- `_local/obsidian_livesync_sync_parameters` encryption settings.

## Mandatory Editing Rules

1. Backup DB before destructive actions.
2. Read document immediately before write.
3. Write with current `_rev`; never reuse stale revision.
4. Edit the smallest possible set of fields.
5. Keep `_id`, `type`, and structural fields unchanged unless explicitly required.
6. If encryption/path-obfuscation is enabled and user asks for content rewrite, warn about reconstruction risk first.
7. In production, prefer `scripts/safe_change.sh` so every change has backup, snapshot, and manifest.

## Path to ID Conversion Notes

- If case-insensitive mode is enabled, lowercase before hash.
- If path starts with `_`, convert to `/_...` before ID logic.
- If obfuscation is off: `_id` is path (with prefix adjustment).
- If obfuscation is on: `_id` becomes `f:<sha256-stretched-hash>`.

Use `scripts/livesync_couchdb_tool.py path2id` for repeatable conversion.
