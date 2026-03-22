#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
RECEIPT_TS="$(date -u +"%Y%m%dT%H%M%SZ")"
RECEIPT_DIR="${REPO_ROOT}/receipts/${RECEIPT_TS}"
LOG_FILE="${RECEIPT_DIR}/install.log"
VERSIONS_FILE="${RECEIPT_DIR}/versions.txt"

mkdir -p "${RECEIPT_DIR}" "${REPO_ROOT}/receipts/launchd"
exec > >(tee -a "${LOG_FILE}") 2>&1

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

record_version() {
  local label="$1"
  shift
  {
    echo "## ${label}"
    "$@" 2>&1 || true
    echo
  } >> "${VERSIONS_FILE}"
}

brew_install_if_missing() {
  local command_name="$1"
  shift
  if have_cmd "${command_name}"; then
    return 0
  fi
  if ! have_cmd brew; then
    echo "missing ${command_name} and Homebrew is unavailable"
    return 1
  fi
  echo "installing ${command_name} via brew $*"
  brew "$@"
}

echo "receipt_dir=${RECEIPT_DIR}"

brew_install_if_missing docker install --cask docker || true
brew_install_if_missing tailscale install --cask tailscale || true
brew_install_if_missing curl install curl || true
brew_install_if_missing restic install restic || true

if ! have_cmd docker; then
  echo "docker is required"
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "docker daemon is not reachable. Start Docker Desktop and re-run."
  exit 1
fi

if ! have_cmd tailscale; then
  echo "tailscale is required"
  exit 1
fi

record_version "docker" docker version
record_version "docker compose" docker compose version
record_version "tailscale" tailscale version
record_version "restic" restic version

{
  echo "## tailscale status"
  tailscale status || true
} >> "${VERSIONS_FILE}"

echo "install verification complete"
