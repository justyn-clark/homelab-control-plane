#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
RECEIPT_TS="$(date -u +"%Y%m%dT%H%M%SZ")"
RECEIPT_DIR="${REPO_ROOT}/receipts/${RECEIPT_TS}"
LOG_FILE="${RECEIPT_DIR}/launchd-install.log"
PLIST_LABEL="com.jcn.controlplane"
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

plist_escape() {
  local value="$1"
  value="${value//&/&amp;}"
  value="${value//</&lt;}"
  value="${value//>/&gt;}"
  printf '%s' "${value}"
}

write_plist() {
  local repo_root_escaped
  local stdout_escaped
  local stderr_escaped
  local bringup_escaped

  repo_root_escaped="$(plist_escape "${REPO_ROOT}")"
  stdout_escaped="$(plist_escape "${REPO_ROOT}/receipts/launchd/bringup.stdout.log")"
  stderr_escaped="$(plist_escape "${REPO_ROOT}/receipts/launchd/bringup.stderr.log")"
  bringup_escaped="$(plist_escape "${REPO_ROOT}/ops/bootstrap/macos/bringup.sh")"

  cat > "${RENDERED_PLIST}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${PLIST_LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${bringup_escaped}</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StartInterval</key>
  <integer>300</integer>
  <key>StandardOutPath</key>
  <string>${stdout_escaped}</string>
  <key>StandardErrorPath</key>
  <string>${stderr_escaped}</string>
  <key>WorkingDirectory</key>
  <string>${repo_root_escaped}</string>
</dict>
</plist>
EOF
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

