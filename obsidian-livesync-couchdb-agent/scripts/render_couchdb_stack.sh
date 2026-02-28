#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${1:-./couchdb-livesync}"
mkdir -p "${OUT_DIR}/couchdb-data" "${OUT_DIR}/couchdb-etc"

cat > "${OUT_DIR}/docker-compose.yml" <<'YAML'
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
      - "5984:5984"
    restart: unless-stopped
YAML

cat > "${OUT_DIR}/.env.example" <<'ENV'
COUCHDB_USER=change_me
COUCHDB_PASSWORD=change_me
ENV

echo "Rendered stack at: ${OUT_DIR}"
echo "Next:"
echo "  1) cp ${OUT_DIR}/.env.example ${OUT_DIR}/.env and edit credentials"
echo "  2) cd ${OUT_DIR} && docker compose up -d"
echo "  3) export COUCH_URL=http://127.0.0.1:5984 COUCH_USER=<user> COUCH_PASSWORD=<pass>"
echo "  4) bash ../scripts/init_livesync_couchdb.sh"
