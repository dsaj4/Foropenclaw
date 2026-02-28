#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_PY="${SCRIPT_DIR}/livesync_couchdb_tool.py"

COUCH_URL="${COUCH_URL:-}"
COUCH_USER="${COUCH_USER:-}"
COUCH_PASSWORD="${COUCH_PASSWORD:-}"
COUCH_DB="${COUCH_DB:-}"
CHANGE_LOG_DIR="${CHANGE_LOG_DIR:-./change-logs}"

if [[ -z "${COUCH_URL}" || -z "${COUCH_USER}" || -z "${COUCH_PASSWORD}" || -z "${COUCH_DB}" ]]; then
  echo "ERROR: COUCH_URL, COUCH_USER, COUCH_PASSWORD, COUCH_DB are required in environment." >&2
  exit 1
fi

if [[ $# -lt 1 ]]; then
  echo "Usage:" >&2
  echo "  safe_change.sh patch --id <DOC_ID> --set key=value [--set key2=value2 ...]" >&2
  echo "  safe_change.sh delete --id <DOC_ID>" >&2
  exit 1
fi

op="$1"
shift

id=""
declare -a set_args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --id)
      id="${2:-}"
      shift 2
      ;;
    --set)
      set_args+=("--set" "${2:-}")
      shift 2
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "${id}" ]]; then
  echo "ERROR: --id is required." >&2
  exit 1
fi

if [[ "${op}" == "patch" && "${#set_args[@]}" -eq 0 ]]; then
  echo "ERROR: patch requires at least one --set key=value." >&2
  exit 1
fi
if [[ "${op}" != "patch" && "${op}" != "delete" ]]; then
  echo "ERROR: operation must be patch or delete." >&2
  exit 1
fi

ts="$(date +%Y%m%d_%H%M%S)"
mkdir -p "${CHANGE_LOG_DIR}"
run_dir="${CHANGE_LOG_DIR}/${ts}_${op}"
mkdir -p "${run_dir}"

backup_file="${run_dir}/backup-all.json"
pre_doc_file="${run_dir}/pre-doc.json"
manifest_file="${run_dir}/manifest.json"
result_file="${run_dir}/result.json"
snapshot_db="${COUCH_DB}_snap_${ts}"

echo "[1/5] Backup all docs -> ${backup_file}"
python3 "${TOOL_PY}" backup-all \
  --url "${COUCH_URL}" --user "${COUCH_USER}" --password "${COUCH_PASSWORD}" --db "${COUCH_DB}" \
  --out "${backup_file}"

echo "[2/5] Snapshot database -> ${snapshot_db}"
auth="$(printf "%s:%s" "${COUCH_USER}" "${COUCH_PASSWORD}" | base64 | tr -d '\r\n')"
curl -fsS -X PUT "${COUCH_URL%/}/${snapshot_db}" \
  -H "Authorization: Basic ${auth}" -H "Content-Type: application/json" >/dev/null || true
curl -fsS -X POST "${COUCH_URL%/}/_replicate" \
  -H "Authorization: Basic ${auth}" -H "Content-Type: application/json" \
  -d "{\"source\":\"${COUCH_DB}\",\"target\":\"${snapshot_db}\",\"create_target\":false}" >/dev/null

echo "[3/5] Capture target doc before change -> ${pre_doc_file}"
python3 "${TOOL_PY}" get \
  --url "${COUCH_URL}" --user "${COUCH_USER}" --password "${COUCH_PASSWORD}" --db "${COUCH_DB}" \
  --id "${id}" > "${pre_doc_file}"

echo "[4/5] Apply ${op}"
if [[ "${op}" == "patch" ]]; then
  python3 "${TOOL_PY}" patch \
    --url "${COUCH_URL}" --user "${COUCH_USER}" --password "${COUCH_PASSWORD}" --db "${COUCH_DB}" \
    --id "${id}" "${set_args[@]}" > "${result_file}"
else
  python3 "${TOOL_PY}" delete \
    --url "${COUCH_URL}" --user "${COUCH_USER}" --password "${COUCH_PASSWORD}" --db "${COUCH_DB}" \
    --id "${id}" > "${result_file}"
fi

echo "[5/5] Write manifest -> ${manifest_file}"
cat > "${manifest_file}" <<EOF
{
  "timestamp": "${ts}",
  "operation": "${op}",
  "target_db": "${COUCH_DB}",
  "target_id": "${id}",
  "snapshot_db": "${snapshot_db}",
  "backup_all_file": "${backup_file}",
  "pre_doc_file": "${pre_doc_file}",
  "result_file": "${result_file}"
}
EOF

echo "SAFE_CHANGE_OK"
echo "manifest: ${manifest_file}"
