#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
RECEIPT_TS="$(date -u +"%Y%m%dT%H%M%SZ")"
RECEIPT_DIR="${REPO_ROOT}/receipts/${RECEIPT_TS}"
LOG_FILE="${RECEIPT_DIR}/backup.log"
VERSIONS_FILE="${RECEIPT_DIR}/backup-versions.txt"
MANIFEST_FILE="${RECEIPT_DIR}/backup-manifest.txt"
RESTIC_BACKUP_FILE="${RECEIPT_DIR}/restic-backup.txt"
RESTIC_SNAPSHOTS_FILE="${RECEIPT_DIR}/restic-snapshots.txt"

VOLUMES=(
  "jcn-core_postgres-data"
  "jcn-core_redis-data"
  "jcn-observability_prometheus-data"
  "jcn-observability_loki-data"
  "jcn-observability_grafana-data"
  "jcn-auth_authelia-data"
)

mkdir -p "${RECEIPT_DIR}" "${REPO_ROOT}/receipts/launchd"
exec > >(tee -a "${LOG_FILE}") 2>&1

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1"
    exit 1
  }
}

capture_versions() {
  {
    echo "## restic"
    restic version
    echo
    echo "## docker"
    docker version
    echo
    echo "## docker compose"
    docker compose version
  } > "${VERSIONS_FILE}"
}

archive_volume() {
  local volume_name="$1"
  local archive_name="${RECEIPT_DIR}/${volume_name}.tar.gz"
  if ! docker volume inspect "${volume_name}" >/dev/null 2>&1; then
    echo "${volume_name} status=missing" >> "${MANIFEST_FILE}"
    return 0
  fi
  echo "archiving ${volume_name}"
  docker run --rm \
    -v "${volume_name}:/source:ro" \
    -v "${RECEIPT_DIR}:/backup" \
    busybox:1.36 \
    sh -c "tar -czf /backup/${volume_name}.tar.gz -C /source ."
  echo "${volume_name} status=archived archive=$(basename "${archive_name}")" >> "${MANIFEST_FILE}"
}

maybe_dump_postgres() {
  local env_file="${REPO_ROOT}/stacks/core/.env"
  if [[ ! -f "${env_file}" ]]; then
    echo "postgres_dump status=skipped reason=missing-core-env" >> "${MANIFEST_FILE}"
    return 0
  fi

  local container_id
  container_id="$(docker ps \
    --filter label=com.docker.compose.project=jcn-core \
    --filter label=com.docker.compose.service=postgres \
    --quiet | head -n 1)"

  if [[ -z "${container_id}" ]]; then
    echo "postgres_dump status=skipped reason=postgres-not-running" >> "${MANIFEST_FILE}"
    return 0
  fi

  set -a
  source "${env_file}"
  set +a

  echo "creating postgres logical dump"
  docker compose -p jcn-core -f "${REPO_ROOT}/stacks/core/compose.yml" exec -T postgres \
    pg_dump -U "${POSTGRES_USER}" "${POSTGRES_DB}" > "${RECEIPT_DIR}/postgres.dump.sql"
  echo "postgres_dump status=created file=postgres.dump.sql" >> "${MANIFEST_FILE}"
}

ensure_restic_repo() {
  if ! restic snapshots >/dev/null 2>&1; then
    echo "initializing restic repository"
    restic init
  fi
}

echo "receipt_dir=${RECEIPT_DIR}"

require_cmd docker
require_cmd restic
require_cmd tee

if [[ -z "${RESTIC_REPOSITORY:-}" ]]; then
  echo "RESTIC_REPOSITORY must be set"
  exit 1
fi

if [[ -z "${RESTIC_PASSWORD_FILE:-}" ]]; then
  echo "RESTIC_PASSWORD_FILE must be set"
  exit 1
fi

if [[ ! -f "${RESTIC_PASSWORD_FILE}" ]]; then
  echo "RESTIC_PASSWORD_FILE does not exist: ${RESTIC_PASSWORD_FILE}"
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "docker daemon is not reachable"
  exit 1
fi

capture_versions
: > "${MANIFEST_FILE}"

for volume_name in "${VOLUMES[@]}"; do
  archive_volume "${volume_name}"
done

maybe_dump_postgres

ensure_restic_repo

restic backup \
  "${REPO_ROOT}/stacks" \
  "${REPO_ROOT}/runbooks" \
  "${REPO_ROOT}/ops" \
  "${REPO_ROOT}/README.md" \
  "${REPO_ROOT}/CONTRACT.md" \
  "${RECEIPT_DIR}" | tee "${RESTIC_BACKUP_FILE}"

restic snapshots --latest 5 | tee "${RESTIC_SNAPSHOTS_FILE}"

echo "backup complete"

