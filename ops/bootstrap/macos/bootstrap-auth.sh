#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
RECEIPT_TS="$(date -u +"%Y%m%dT%H%M%SZ")"
RECEIPT_DIR="${REPO_ROOT}/receipts/${RECEIPT_TS}"
LOG_FILE="${RECEIPT_DIR}/auth-bootstrap.log"
SUMMARY_FILE="${RECEIPT_DIR}/auth-bootstrap-summary.txt"
INPUTS_FILE="${RECEIPT_DIR}/auth-bootstrap-inputs.txt"
FILES_FILE="${RECEIPT_DIR}/auth-bootstrap-files.txt"

AUTH_ENV_EXAMPLE="${REPO_ROOT}/stacks/auth/env.example"
AUTH_ENV_FILE="${REPO_ROOT}/stacks/auth/.env"
USERS_EXAMPLE_FILE="${REPO_ROOT}/stacks/auth/users_database.example.yml"
USERS_FILE="${REPO_ROOT}/stacks/auth/users_database.yml"
AUTH_COMPOSE_FILE="${REPO_ROOT}/stacks/auth/compose.yml"

FORCE_REGENERATE="${FORCE_REGENERATE:-0}"
AUTH_USERNAME="${AUTH_USERNAME:-admin}"
AUTH_DISPLAY_NAME="${AUTH_DISPLAY_NAME:-JCN Admin}"
AUTH_EMAIL="${AUTH_EMAIL:-admin@example.internal}"
AUTHELIA_DOMAIN_OVERRIDE="${AUTHELIA_DOMAIN:-}"
AUTHELIA_DEFAULT_REDIRECTION_URL_OVERRIDE="${AUTHELIA_DEFAULT_REDIRECTION_URL:-}"
AUTHELIA_PASSWORD_HASH_OVERRIDE="${AUTHELIA_PASSWORD_HASH:-}"
AUTH_PASSWORD="${AUTH_PASSWORD:-}"

AUTHELIA_DOMAIN_VALUE=""
AUTHELIA_DEFAULT_REDIRECTION_URL_VALUE=""
AUTHELIA_SESSION_SECRET_VALUE=""
AUTHELIA_STORAGE_ENCRYPTION_KEY_VALUE=""
AUTHELIA_JWT_SECRET_VALUE=""
AUTHELIA_PASSWORD_HASH_VALUE=""

AUTHELIA_DOMAIN_STATUS=""
AUTHELIA_DEFAULT_REDIRECTION_URL_STATUS=""
AUTHELIA_SESSION_SECRET_STATUS=""
AUTHELIA_STORAGE_ENCRYPTION_KEY_STATUS=""
AUTHELIA_JWT_SECRET_STATUS=""
AUTHELIA_PASSWORD_HASH_STATUS=""
USERS_WRITTEN=0

mkdir -p "${RECEIPT_DIR}" "${REPO_ROOT}/receipts/launchd"
exec > >(tee -a "${LOG_FILE}") 2>&1

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1"
    exit 1
  }
}

require_file() {
  local path="$1"
  if [[ ! -f "${path}" ]]; then
    echo "missing required file: ${path}"
    exit 1
  fi
}

read_env_value() {
  local path="$1"
  local key="$2"
  [[ -f "${path}" ]] || return 0
  awk -F= -v key="${key}" '$1 == key {print substr($0, index($0, "=") + 1)}' "${path}" | tail -n 1
}

random_hex() {
  openssl rand -hex 32
}

authelia_hash_image() {
  local image
  image="$(awk '/image:[[:space:]]+authelia\\/authelia:/ {print $2; exit}' "${AUTH_COMPOSE_FILE}")"

  if [[ -z "${image}" ]]; then
    echo "unable to determine Authelia image from ${AUTH_COMPOSE_FILE}" >&2
    exit 1
  fi

  printf '%s' "${image}"
}

generate_password_hash() {
  if [[ -n "${AUTHELIA_PASSWORD_HASH_OVERRIDE}" ]]; then
    printf '%s' "${AUTHELIA_PASSWORD_HASH_OVERRIDE}"
    return 0
  fi

  if [[ -z "${AUTH_PASSWORD}" ]]; then
    echo "AUTH_PASSWORD or AUTHELIA_PASSWORD_HASH must be set" >&2
    exit 1
  fi

  docker run --rm "$(authelia_hash_image)" \
    authelia crypto hash generate argon2 --password "${AUTH_PASSWORD}" | tail -n 1 | sed 's/^Digest: //'
}

set_value_and_status() {
  local existing_value="$1"
  local candidate_value="$2"
  local status_var="$3"
  local value_var="$4"
  local final_value=""
  local final_status=""

  if [[ "${FORCE_REGENERATE}" == "1" ]]; then
    final_value="${candidate_value}"
    final_status="generated"
  elif [[ -n "${existing_value}" && "${existing_value}" != "replace-me" ]]; then
    final_value="${existing_value}"
    final_status="preserved"
  else
    final_value="${candidate_value}"
    final_status="generated"
  fi

  printf -v "${value_var}" '%s' "${final_value}"
  printf -v "${status_var}" '%s' "${final_status}"
}

write_env_file() {
  cat > "${AUTH_ENV_FILE}" <<EOF
AUTHELIA_DOMAIN=${AUTHELIA_DOMAIN_VALUE}
AUTHELIA_DEFAULT_REDIRECTION_URL=${AUTHELIA_DEFAULT_REDIRECTION_URL_VALUE}
AUTHELIA_SESSION_SECRET=${AUTHELIA_SESSION_SECRET_VALUE}
AUTHELIA_STORAGE_ENCRYPTION_KEY=${AUTHELIA_STORAGE_ENCRYPTION_KEY_VALUE}
AUTHELIA_JWT_SECRET=${AUTHELIA_JWT_SECRET_VALUE}
AUTHELIA_PASSWORD_HASH=${AUTHELIA_PASSWORD_HASH_VALUE}
EOF
}

write_users_file() {
  cat > "${USERS_FILE}" <<EOF
users:
  ${AUTH_USERNAME}:
    displayname: "${AUTH_DISPLAY_NAME}"
    email: "${AUTH_EMAIL}"
    password: "${AUTHELIA_PASSWORD_HASH_VALUE}"
    groups:
      - admins
EOF
}

validate_outputs() {
  require_file "${AUTH_ENV_FILE}"
  require_file "${USERS_FILE}"
  grep -q '^AUTHELIA_SESSION_SECRET=' "${AUTH_ENV_FILE}"
  grep -q '^AUTHELIA_STORAGE_ENCRYPTION_KEY=' "${AUTH_ENV_FILE}"
  grep -q '^AUTHELIA_JWT_SECRET=' "${AUTH_ENV_FILE}"
  grep -q '^AUTHELIA_PASSWORD_HASH=' "${AUTH_ENV_FILE}"
  grep -q "^  ${AUTH_USERNAME}:" "${USERS_FILE}"
}

write_receipts() {
  cat > "${INPUTS_FILE}" <<EOF
force_regenerate=${FORCE_REGENERATE}
auth_username=${AUTH_USERNAME}
auth_display_name=${AUTH_DISPLAY_NAME}
auth_email=${AUTH_EMAIL}
authelia_domain=${AUTHELIA_DOMAIN_VALUE}
authelia_default_redirection_url=${AUTHELIA_DEFAULT_REDIRECTION_URL_VALUE}
password_hash_source=$([[ -n "${AUTHELIA_PASSWORD_HASH_OVERRIDE}" ]] && echo provided || echo generated-or-preserved)
password_provided=$([[ -n "${AUTH_PASSWORD}" ]] && echo yes || echo no)
EOF

  cat > "${FILES_FILE}" <<EOF
auth_env_file=${AUTH_ENV_FILE}
auth_env_status=$([[ -f "${AUTH_ENV_FILE}" ]] && echo present || echo missing)
users_file=${USERS_FILE}
users_file_status=$([[ -f "${USERS_FILE}" ]] && echo present || echo missing)
AUTHELIA_SESSION_SECRET=${AUTHELIA_SESSION_SECRET_STATUS}
AUTHELIA_STORAGE_ENCRYPTION_KEY=${AUTHELIA_STORAGE_ENCRYPTION_KEY_STATUS}
AUTHELIA_JWT_SECRET=${AUTHELIA_JWT_SECRET_STATUS}
AUTHELIA_PASSWORD_HASH=${AUTHELIA_PASSWORD_HASH_STATUS}
AUTHELIA_DOMAIN=${AUTHELIA_DOMAIN_STATUS}
AUTHELIA_DEFAULT_REDIRECTION_URL=${AUTHELIA_DEFAULT_REDIRECTION_URL_STATUS}
users_database_action=$([[ "${USERS_WRITTEN}" == "1" ]] && echo written || echo preserved)
EOF

  cat > "${SUMMARY_FILE}" <<EOF
status=ok
auth_username=${AUTH_USERNAME}
auth_email=${AUTH_EMAIL}
auth_env_file=${AUTH_ENV_FILE}
users_file=${USERS_FILE}
session_secret=${AUTHELIA_SESSION_SECRET_STATUS}
storage_encryption_key=${AUTHELIA_STORAGE_ENCRYPTION_KEY_STATUS}
jwt_secret=${AUTHELIA_JWT_SECRET_STATUS}
password_hash=${AUTHELIA_PASSWORD_HASH_STATUS}
users_database=$([[ "${USERS_WRITTEN}" == "1" ]] && echo written || echo preserved)
receipt_dir=${RECEIPT_DIR}
EOF
}

echo "receipt_dir=${RECEIPT_DIR}"

require_cmd openssl
require_cmd docker
require_cmd awk
require_file "${AUTH_ENV_EXAMPLE}"
require_file "${USERS_EXAMPLE_FILE}"
require_file "${AUTH_COMPOSE_FILE}"

set_value_and_status \
  "$(read_env_value "${AUTH_ENV_FILE}" "AUTHELIA_DOMAIN")" \
  "${AUTHELIA_DOMAIN_OVERRIDE:-$(read_env_value "${AUTH_ENV_EXAMPLE}" "AUTHELIA_DOMAIN")}" \
  AUTHELIA_DOMAIN_STATUS \
  AUTHELIA_DOMAIN_VALUE

set_value_and_status \
  "$(read_env_value "${AUTH_ENV_FILE}" "AUTHELIA_DEFAULT_REDIRECTION_URL")" \
  "${AUTHELIA_DEFAULT_REDIRECTION_URL_OVERRIDE:-$(read_env_value "${AUTH_ENV_EXAMPLE}" "AUTHELIA_DEFAULT_REDIRECTION_URL")}" \
  AUTHELIA_DEFAULT_REDIRECTION_URL_STATUS \
  AUTHELIA_DEFAULT_REDIRECTION_URL_VALUE

set_value_and_status \
  "$(read_env_value "${AUTH_ENV_FILE}" "AUTHELIA_SESSION_SECRET")" \
  "$(random_hex)" \
  AUTHELIA_SESSION_SECRET_STATUS \
  AUTHELIA_SESSION_SECRET_VALUE

set_value_and_status \
  "$(read_env_value "${AUTH_ENV_FILE}" "AUTHELIA_STORAGE_ENCRYPTION_KEY")" \
  "$(random_hex)" \
  AUTHELIA_STORAGE_ENCRYPTION_KEY_STATUS \
  AUTHELIA_STORAGE_ENCRYPTION_KEY_VALUE

set_value_and_status \
  "$(read_env_value "${AUTH_ENV_FILE}" "AUTHELIA_JWT_SECRET")" \
  "$(random_hex)" \
  AUTHELIA_JWT_SECRET_STATUS \
  AUTHELIA_JWT_SECRET_VALUE

EXISTING_PASSWORD_HASH="$(read_env_value "${AUTH_ENV_FILE}" "AUTHELIA_PASSWORD_HASH")"
if [[ "${FORCE_REGENERATE}" != "1" && -n "${EXISTING_PASSWORD_HASH}" && "${EXISTING_PASSWORD_HASH}" != "replace-me" ]]; then
  AUTHELIA_PASSWORD_HASH_VALUE="${EXISTING_PASSWORD_HASH}"
  AUTHELIA_PASSWORD_HASH_STATUS="preserved"
else
  AUTHELIA_PASSWORD_HASH_VALUE="$(generate_password_hash)"
  AUTHELIA_PASSWORD_HASH_STATUS="generated"
fi

write_env_file

if [[ "${FORCE_REGENERATE}" == "1" || ! -f "${USERS_FILE}" ]]; then
  write_users_file
  USERS_WRITTEN=1
fi

validate_outputs
write_receipts

echo "auth bootstrap complete"
