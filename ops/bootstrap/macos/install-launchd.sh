#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
RECEIPT_TS="$(date -u +"%Y%m%dT%H%M%SZ")"
RECEIPT_DIR="${REPO_ROOT}/receipts/${RECEIPT_TS}"
LOG_FILE="${RECEIPT_DIR}/launchd-install.log"
PLIST_LABEL="com.jcn.controlplane"
PLIST_TEMPLATE="${REPO_ROOT}/ops/bootstrap/macos/launchd/${PLIST_LABEL}.plist"
TARGET_PLIST="${HOME}/Library/LaunchAgents/${PLIST_LABEL}.plist"
RENDERED_PLIST="${RECEIPT_DIR}/${PLIST_LABEL}.plist"
LAUNCHD_STATUS_FILE="${RECEIPT_DIR}/launchd-status.txt"
DRY_RUN="${DRY_RUN:-0}"

mkdir -p "${RECEIPT_DIR}" "${REPO_ROOT}/receipts/launchd" "$(dirname "${TARGET_PLIST}")"
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

plist_escape() {
  local value="$1"
  value="${value//&/&amp;}"
  value="${value//</&lt;}"
  value="${value//>/&gt;}"
  printf '%s' "${value}"
}

awk_escape_replacement() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//&/\\&}"
  printf '%s' "${value}"
}

write_plist() {
  local repo_root_replacement
  local stdout_replacement
  local stderr_replacement
  local bringup_replacement

  repo_root_replacement="$(awk_escape_replacement "$(plist_escape "${REPO_ROOT}")")"
  stdout_replacement="$(awk_escape_replacement "$(plist_escape "${REPO_ROOT}/receipts/launchd/bringup.stdout.log")")"
  stderr_replacement="$(awk_escape_replacement "$(plist_escape "${REPO_ROOT}/receipts/launchd/bringup.stderr.log")")"
  bringup_replacement="$(awk_escape_replacement "$(plist_escape "${REPO_ROOT}/ops/bootstrap/macos/bringup.sh")")"

  awk \
    -v bringup_script="${bringup_replacement}" \
    -v stdout_log="${stdout_replacement}" \
    -v stderr_log="${stderr_replacement}" \
    -v working_directory="${repo_root_replacement}" \
    '{
      gsub(/__BRINGUP_SCRIPT__/, bringup_script)
      gsub(/__STDOUT_LOG__/, stdout_log)
      gsub(/__STDERR_LOG__/, stderr_log)
      gsub(/__WORKING_DIRECTORY__/, working_directory)
      print
    }' \
    "${PLIST_TEMPLATE}" > "${RENDERED_PLIST}"
}

capture_status() {
  {
    echo "label=${PLIST_LABEL}"
    echo "target_plist=${TARGET_PLIST}"
    echo "dry_run=${DRY_RUN}"
    echo
    echo "## launchctl print"
    launchctl print "gui/$(id -u)/${PLIST_LABEL}" 2>&1 || true
    echo
    echo "## launchctl list"
    launchctl list | grep "${PLIST_LABEL}" || true
  } > "${LAUNCHD_STATUS_FILE}"
}

echo "receipt_dir=${RECEIPT_DIR}"

require_cmd plutil
require_cmd launchctl
require_cmd install
require_cmd id
require_cmd awk
require_file "${PLIST_TEMPLATE}"

write_plist
plutil -lint "${RENDERED_PLIST}"

if [[ "${DRY_RUN}" == "1" ]]; then
  capture_status
  echo "dry run complete"
  exit 0
fi

install -m 0644 "${RENDERED_PLIST}" "${TARGET_PLIST}"

if launchctl print "gui/$(id -u)/${PLIST_LABEL}" >/dev/null 2>&1; then
  launchctl bootout "gui/$(id -u)" "${TARGET_PLIST}" || true
fi

launchctl bootstrap "gui/$(id -u)" "${TARGET_PLIST}"
launchctl enable "gui/$(id -u)/${PLIST_LABEL}"
launchctl kickstart -k "gui/$(id -u)/${PLIST_LABEL}"

capture_status

echo "launchd install complete"
