# Rollback Mechanism

## Objective

Make every change revertible with low operator effort and explicit evidence.

## Mechanism Layers

1. Pre-change full backup (`backup-all.json`)
2. Pre-change full DB snapshot (`<db>_snap_<timestamp>`)
3. Per-change manifest with target id and pre-change doc JSON
4. Deterministic rollback script using latest `_rev`

## Standard Flow

Use `scripts/safe_change.sh` instead of direct patch/delete:

```bash
export COUCH_URL=http://127.0.0.1:5984
export COUCH_USER=admin
export COUCH_PASSWORD=secret
export COUCH_DB=obsidian_livesync

bash scripts/safe_change.sh patch --id syncinfo --set value=new-token
```

Output includes `manifest: <path>`.

Rollback:

```bash
python3 scripts/rollback_change.py \
  --manifest "<path-to-manifest.json>" \
  --url "$COUCH_URL" --user "$COUCH_USER" --password "$COUCH_PASSWORD"
```

## Operational Rules

- Never run direct `patch/delete` in production paths.
- Keep `change-logs/` under retention policy (for example 14-30 days).
- For incident response, first run targeted rollback by manifest.
- If broad corruption exists, switch clients to snapshot DB or restore from storage snapshot.
