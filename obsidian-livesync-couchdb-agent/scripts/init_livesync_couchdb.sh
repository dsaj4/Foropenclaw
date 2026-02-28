#!/usr/bin/env bash
set -euo pipefail

COUCH_URL="${COUCH_URL:-${hostname:-}}"
COUCH_USER="${COUCH_USER:-${username:-}}"
COUCH_PASSWORD="${COUCH_PASSWORD:-${password:-}}"
COUCH_NODE="${COUCH_NODE:-${node:-_local}}"
COUCH_BIND_ADDRESS="${COUCH_BIND_ADDRESS:-0.0.0.0}"
COUCH_DB="${COUCH_DB:-${database:-}}"
COUCH_ORIGINS="${COUCH_ORIGINS:-app://obsidian.md,capacitor://localhost,http://localhost}"
COUCH_REQUIRE_VALID_USER="${COUCH_REQUIRE_VALID_USER:-true}"

if [[ -z "${COUCH_URL}" ]]; then
  echo "ERROR: COUCH_URL is required" >&2
  exit 1
fi
if [[ -z "${COUCH_USER}" ]]; then
  echo "ERROR: COUCH_USER is required" >&2
  exit 1
fi
if [[ -z "${COUCH_PASSWORD}" ]]; then
  echo "ERROR: COUCH_PASSWORD is required" >&2
  exit 1
fi

echo "-- Configuring CouchDB for Obsidian LiveSync..."

auth=(-u "${COUCH_USER}:${COUCH_PASSWORD}" -H "Content-Type: application/json")

until curl -fsS -X POST "${COUCH_URL}/_cluster_setup" "${auth[@]}" -d "{\"action\":\"enable_single_node\",\"username\":\"${COUCH_USER}\",\"password\":\"${COUCH_PASSWORD}\",\"bind_address\":\"${COUCH_BIND_ADDRESS}\",\"port\":5984,\"singlenode\":true}" >/dev/null; do
  sleep 3
done

until curl -fsS -X PUT "${COUCH_URL}/_node/${COUCH_NODE}/_config/chttpd/require_valid_user" "${auth[@]}" -d "\"${COUCH_REQUIRE_VALID_USER}\"" >/dev/null; do
  sleep 3
done
until curl -fsS -X PUT "${COUCH_URL}/_node/${COUCH_NODE}/_config/chttpd_auth/require_valid_user" "${auth[@]}" -d "\"${COUCH_REQUIRE_VALID_USER}\"" >/dev/null; do
  sleep 3
done
until curl -fsS -X PUT "${COUCH_URL}/_node/${COUCH_NODE}/_config/httpd/WWW-Authenticate" "${auth[@]}" -d '"Basic realm=\"couchdb\""' >/dev/null; do
  sleep 3
done
until curl -fsS -X PUT "${COUCH_URL}/_node/${COUCH_NODE}/_config/httpd/enable_cors" "${auth[@]}" -d '"true"' >/dev/null; do
  sleep 3
done
until curl -fsS -X PUT "${COUCH_URL}/_node/${COUCH_NODE}/_config/chttpd/enable_cors" "${auth[@]}" -d '"true"' >/dev/null; do
  sleep 3
done
until curl -fsS -X PUT "${COUCH_URL}/_node/${COUCH_NODE}/_config/chttpd/max_http_request_size" "${auth[@]}" -d '"4294967296"' >/dev/null; do
  sleep 3
done
until curl -fsS -X PUT "${COUCH_URL}/_node/${COUCH_NODE}/_config/couchdb/max_document_size" "${auth[@]}" -d '"50000000"' >/dev/null; do
  sleep 3
done
until curl -fsS -X PUT "${COUCH_URL}/_node/${COUCH_NODE}/_config/cors/credentials" "${auth[@]}" -d '"true"' >/dev/null; do
  sleep 3
done
until curl -fsS -X PUT "${COUCH_URL}/_node/${COUCH_NODE}/_config/cors/origins" "${auth[@]}" -d "\"${COUCH_ORIGINS}\"" >/dev/null; do
  sleep 3
done

if [[ -n "${COUCH_DB}" ]]; then
  status="$(curl -s -o /dev/null -w "%{http_code}" -X PUT "${COUCH_URL}/${COUCH_DB}" "${auth[@]}" || true)"
  if [[ "${status}" == "201" || "${status}" == "202" || "${status}" == "412" ]]; then
    echo "Database ready: ${COUCH_DB} (status ${status})"
  else
    echo "WARNING: Database create/check returned status ${status}" >&2
  fi
fi

echo "<-- CouchDB LiveSync configuration complete."
