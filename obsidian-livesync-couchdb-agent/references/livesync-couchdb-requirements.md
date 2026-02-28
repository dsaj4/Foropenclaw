# LiveSync-Compatible CouchDB Requirements

## Goal

Run CouchDB in a way that Obsidian Self-hosted LiveSync can connect from desktop/mobile and replicate safely.

## Minimum Server Checklist

- Enable admin account (`COUCHDB_USER`, `COUCHDB_PASSWORD`).
- Enable CORS and allow:
  - `app://obsidian.md`
  - `capacitor://localhost`
  - `http://localhost`
- Require valid users for `chttpd` and `chttpd_auth`.
- Set request size limits high enough for chunk and metadata operations.
- Expose over HTTPS for mobile usage scenarios.

## Recommended Docker Compose Baseline

```yaml
services:
  couchdb:
    image: couchdb:latest
    container_name: obsidian-livesync
    user: 5984:5984
    environment:
      - COUCHDB_USER=${COUCHDB_USER}
      - COUCHDB_PASSWORD=${COUCHDB_PASSWORD}
    volumes:
      - ./couchdb-data:/opt/couchdb/data
      - ./couchdb-etc:/opt/couchdb/etc/local.d
    ports:
      - 5984:5984
    restart: unless-stopped
```

Then run `scripts/init_livesync_couchdb.sh` to apply all runtime settings via REST API.

## Canonical Init Parameters

Use these values unless user explicitly requests otherwise:

- `chttpd/require_valid_user`: `true`
- `chttpd_auth/require_valid_user`: `true`
- `httpd/enable_cors`: `true`
- `chttpd/enable_cors`: `true`
- `cors/credentials`: `true`
- `cors/origins`: `app://obsidian.md,capacitor://localhost,http://localhost`
- `chttpd/max_http_request_size`: `4294967296`
- `couchdb/max_document_size`: `50000000`

## Connectivity Validation

After init:

1. `GET /` should return CouchDB welcome JSON (auth may be required).
2. `GET /_all_dbs` with auth should succeed.
3. `PUT /<db_name>` should return `201` or `412` (already exists).
4. LiveSync plugin test-connection should pass with URL/user/password/db.
