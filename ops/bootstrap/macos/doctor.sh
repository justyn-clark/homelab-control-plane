#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
RECEIPT_TS="$(date -u +"%Y%m%dT%H%M%SZ")"
RECEIPT_DIR="${REPO_ROOT}/receipts/${RECEIPT_TS}"
LOG_FILE="${RECEIPT_DIR}/doctor.log"
SUMMARY_FILE="${RECEIPT_DIR}/doctor-summary.txt"
VERSIONS_FILE="${RECEIPT_DIR}/doctor-versions.txt"
CHECKS_FILE="${RECEIPT_DIR}/doctor-checks.txt"
LAUNCHD_FILE="${RECEIPT_DIR}/doctor-launchd.txt"

STACKS=(
  "core:${REPO_ROOT}/stacks/core/compose.yml:jcn-core"
  "observability:${REPO_ROOT}/stacks/observability/compose.yml:jcn-observability"
  "auth:${REPO_ROOT}/stacks/auth/compose.yml:jcn-auth"
  "ingress:${REPO_ROOT}/stacks/ingress/compose.yml:jcn-ingress"
)

FAILURES=0
WARNINGS=0
DOCKER_READY=0
TAILSCALE_READY=0
TAILSCALE_IPS=""
TAILNET_BIND_IP=""

mkdir -p "${RECEIPT_DIR}" "${REPO_ROOT}/receipts/launchd"
exec > >(tee -a "${LOG_FILE}") 2>&1

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

record_check() {
  local level="$1"
  local name="$2"
  local detail="$3"

  printf '%s %s %s\n' "${level}" "${name}" "${detail}" >> "${CHECKS_FILE}"
  echo "${level}: ${name} - ${detail}"

  if [[ "${level}" == "FAIL" ]]; then
    FAILURES=$((FAILURES + 1))
  fi

  if [[ "${level}" == "WARN" ]]; then
    WARNINGS=$((WARNINGS + 1))
  fi
}

read_env_value() {
  local path="$1"
  local key="$2"

  if [[ ! -f "${path}" ]]; then
    return 0
  fi

  awk -F= -v key="${key}" '$1 == key {print substr($0, index($0, "=") + 1)}' "${path}" | tail -n 1
}

check_file_exists() {
  local name="$1"
  local path="$2"

  if [[ -f "${path}" ]]; then
    record_check PASS "${name}" "present (${path})"
  else
    record_check FAIL "${name}" "missing (${path})"
  fi
}

check_env_value() {
  local path="$1"
  local key="$2"
  local mode="$3"
  local value=""

  if [[ ! -f "${path}" ]]; then
    record_check FAIL "env:${key}" "missing file (${path})"
    return 0
  fi

  value="$(read_env_value "${path}" "${key}")"

  if [[ -z "${value}" ]]; then
    record_check FAIL "env:${key}" "value is empty in ${path}"
    return 0
  fi

  if [[ "${mode}" == "secret" && "${value}" == "replace-me" ]]; then
    record_check FAIL "env:${key}" "placeholder value remains in ${path}"
    return 0
  fi

  record_check PASS "env:${key}" "set in ${path}"
}

capture_versions() {
  {
    echo "## bash"
    bash --version
    echo

    echo "## docker"
    if have_cmd docker; then
      docker version 2>&1 || true
    else
      echo "docker missing"
    fi
    echo

    echo "## docker compose"
    if have_cmd docker; then
      docker compose version 2>&1 || true
    else
      echo "docker compose unavailable"
    fi
    echo

    echo "## tailscale"
    if have_cmd tailscale; then
      tailscale version 2>&1 || true
    else
      echo "tailscale missing"
    fi
    echo

    echo "## tailscale ip -4"
    if have_cmd tailscale; then
      tailscale ip -4 2>&1 || true
    else
      echo "tailscale missing"
    fi
  } > "${VERSIONS_FILE}"
}

check_docker() {
  if ! have_cmd docker; then
    record_check FAIL docker "docker command is missing"
    return 0
  fi

  record_check PASS docker "docker command is present"

  if docker info >/dev/null 2>&1; then
    DOCKER_READY=1
    record_check PASS docker-daemon "docker daemon is reachable"
  else
    record_check FAIL docker-daemon "docker daemon is not reachable"
  fi
}

check_tailscale() {
  if ! have_cmd tailscale; then
    record_check FAIL tailscale "tailscale command is missing"
    return 0
  fi

  record_check PASS tailscale "tailscale command is present"

  TAILSCALE_IPS="$(tailscale ip -4 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
  if [[ -n "${TAILSCALE_IPS}" ]]; then
    TAILSCALE_READY=1
    record_check PASS tailscale-ip "tailnet IPv4 present (${TAILSCALE_IPS})"
  else
    record_check FAIL tailscale-ip "no tailnet IPv4 reported by tailscale ip -4"
  fi
}

check_local_files() {
  check_file_exists "core-env" "${REPO_ROOT}/stacks/core/.env"
  check_file_exists "observability-env" "${REPO_ROOT}/stacks/observability/.env"
  check_file_exists "ingress-env" "${REPO_ROOT}/stacks/ingress/.env"
  check_file_exists "auth-env" "${REPO_ROOT}/stacks/auth/.env"
  check_file_exists "auth-users" "${REPO_ROOT}/stacks/auth/users_database.yml"
  check_file_exists "auth-bootstrap-script" "${REPO_ROOT}/ops/bootstrap/macos/bootstrap-auth.sh"

  if [[ -f "${REPO_ROOT}/ops/bootstrap/macos/bootstrap-auth.sh" && -x "${REPO_ROOT}/ops/bootstrap/macos/bootstrap-auth.sh" ]]; then
    record_check PASS auth-bootstrap-executable "bootstrap-auth.sh is executable"
  elif [[ -f "${REPO_ROOT}/ops/bootstrap/macos/bootstrap-auth.sh" ]]; then
    record_check FAIL auth-bootstrap-executable "bootstrap-auth.sh is not executable"
  fi

  check_env_value "${REPO_ROOT}/stacks/core/.env" "POSTGRES_DB" plain
  check_env_value "${REPO_ROOT}/stacks/core/.env" "POSTGRES_USER" plain
  check_env_value "${REPO_ROOT}/stacks/core/.env" "POSTGRES_PASSWORD" secret

  check_env_value "${REPO_ROOT}/stacks/observability/.env" "GRAFANA_ADMIN_USER" plain
  check_env_value "${REPO_ROOT}/stacks/observability/.env" "GRAFANA_ADMIN_PASSWORD" secret

  check_env_value "${REPO_ROOT}/stacks/ingress/.env" "TAILNET_BIND_IP" plain

  check_env_value "${REPO_ROOT}/stacks/auth/.env" "AUTHELIA_DOMAIN" plain
  check_env_value "${REPO_ROOT}/stacks/auth/.env" "AUTHELIA_DEFAULT_REDIRECTION_URL" plain
  check_env_value "${REPO_ROOT}/stacks/auth/.env" "AUTHELIA_SESSION_SECRET" secret
  check_env_value "${REPO_ROOT}/stacks/auth/.env" "AUTHELIA_STORAGE_ENCRYPTION_KEY" secret
  check_env_value "${REPO_ROOT}/stacks/auth/.env" "AUTHELIA_JWT_SECRET" secret
  check_file_exists "auth-password-hash" "${REPO_ROOT}/ops/secrets/authelia-password.hash"

  if [[ -f "${REPO_ROOT}/stacks/auth/users_database.yml" ]]; then
    if grep -Fq '${AUTHELIA_PASSWORD_HASH}' "${REPO_ROOT}/stacks/auth/users_database.yml"; then
      record_check FAIL auth-users-database "users_database.yml still contains the example password placeholder"
    else
      record_check PASS auth-users-database "users_database.yml does not contain the example password placeholder"
    fi
  fi
}

check_static_configs() {
  check_file_exists "auth-config-template" "${REPO_ROOT}/stacks/auth/authelia/configuration.yml"
  check_file_exists "auth-config-local" "${REPO_ROOT}/stacks/auth/authelia/configuration.local.yml"
  if [[ -f "${REPO_ROOT}/stacks/auth/authelia/configuration.local.yml" ]]; then
    if grep -Fq '${AUTHELIA_' "${REPO_ROOT}/stacks/auth/authelia/configuration.local.yml"; then
      record_check FAIL auth-config-local-rendered "configuration.local.yml still contains template placeholders"
    else
      record_check PASS auth-config-local-rendered "configuration.local.yml has concrete local values"
    fi
  fi
  check_file_exists "ingress-caddyfile" "${REPO_ROOT}/stacks/ingress/caddy/Caddyfile"
  check_file_exists "prometheus-config" "${REPO_ROOT}/stacks/observability/prometheus/prometheus.yml"
  check_file_exists "loki-config" "${REPO_ROOT}/stacks/observability/loki/config.yml"
  check_file_exists "promtail-config" "${REPO_ROOT}/stacks/observability/promtail/config.yml"
  check_file_exists "grafana-datasources" "${REPO_ROOT}/stacks/observability/grafana/provisioning/datasources/datasources.yml"
}

check_compose_configs() {
  local entry

  if ! have_cmd docker; then
    record_check WARN compose-config "skipped compose validation because docker is unavailable"
    return 0
  fi

  for entry in "${STACKS[@]}"; do
    local stack_name
    local compose_file
    local project_name
    local stack_dir
    local config_output

    IFS=":" read -r stack_name compose_file project_name <<< "${entry}"
    stack_dir="$(dirname "${compose_file}")"
    config_output="${RECEIPT_DIR}/compose-${stack_name}.config.txt"

    if (cd "${stack_dir}" && docker compose -p "${project_name}" -f "${compose_file}" config > "${config_output}" 2>&1); then
      record_check PASS "compose:${stack_name}" "docker compose config succeeded"
    else
      record_check FAIL "compose:${stack_name}" "docker compose config failed; see $(basename "${config_output}")"
    fi
  done
}

inspect_stack_state() {
  local stack_name="$1"
  local compose_file="$2"
  local project_name="$3"
  local container_ids=""
  local running_count=0
  local container_id

  if [[ "${DOCKER_READY}" != "1" ]]; then
    return 0
  fi

  container_ids="$(docker compose -p "${project_name}" -f "${compose_file}" ps -a -q 2>/dev/null || true)"
  if [[ -z "${container_ids}" ]]; then
    record_check INFO "stack:${stack_name}" "no containers created for ${project_name}"
    return 0
  fi

  echo "## ${stack_name}" >> "${RECEIPT_DIR}/doctor-containers.txt"
  docker compose -p "${project_name}" -f "${compose_file}" ps -a >> "${RECEIPT_DIR}/doctor-containers.txt" 2>&1 || true
  echo >> "${RECEIPT_DIR}/doctor-containers.txt"

  while IFS= read -r container_id; do
    local inspect_output
    local container_name
    local container_state
    local container_health

    [[ -z "${container_id}" ]] && continue

    inspect_output="$(docker inspect --format '{{.Name}}|{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "${container_id}")"
    IFS='|' read -r container_name container_state container_health <<< "${inspect_output}"
    container_name="${container_name#/}"

    if [[ "${container_state}" == "running" ]]; then
      running_count=$((running_count + 1))
    fi

    if [[ "${container_state}" != "running" ]]; then
      record_check FAIL "container:${container_name}" "state=${container_state} health=${container_health}"
      continue
    fi

    if [[ "${container_health}" != "healthy" && "${container_health}" != "none" ]]; then
      record_check FAIL "container:${container_name}" "state=${container_state} health=${container_health}"
      continue
    fi

    record_check PASS "container:${container_name}" "state=${container_state} health=${container_health}"
  done <<EOF
${container_ids}
EOF

  if [[ "${running_count}" -eq 0 ]]; then
    record_check WARN "stack:${stack_name}" "containers exist but none are running"
  else
    record_check PASS "stack:${stack_name}" "running containers inspected (${running_count})"
  fi
}

check_launchd() {
  local plist_template="${REPO_ROOT}/ops/bootstrap/macos/launchd/com.jcn.controlplane.plist"
  local target_plist="${HOME}/Library/LaunchAgents/com.jcn.controlplane.plist"

  : > "${LAUNCHD_FILE}"

  check_file_exists "launchd-template" "${plist_template}"

  if have_cmd plutil && [[ -f "${plist_template}" ]]; then
    if plutil -lint "${plist_template}" >> "${LAUNCHD_FILE}" 2>&1; then
      record_check PASS launchd-template-lint "template plist is valid"
    else
      record_check FAIL launchd-template-lint "template plist is invalid"
    fi
  fi

  if [[ -f "${target_plist}" ]]; then
    record_check PASS launchd-installed "installed LaunchAgent present (${target_plist})"

    if have_cmd plutil; then
      if plutil -lint "${target_plist}" >> "${LAUNCHD_FILE}" 2>&1; then
        record_check PASS launchd-installed-lint "installed LaunchAgent plist is valid"
      else
        record_check FAIL launchd-installed-lint "installed LaunchAgent plist is invalid"
      fi
    fi

    if have_cmd launchctl; then
      {
        echo "## launchctl print gui/$(id -u)/com.jcn.controlplane"
        launchctl print "gui/$(id -u)/com.jcn.controlplane" 2>&1 || true
        echo
        echo "## launchctl list | grep com.jcn.controlplane"
        launchctl list | grep 'com.jcn.controlplane' || true
      } >> "${LAUNCHD_FILE}"
      record_check INFO launchd-runtime "captured launchctl status in $(basename "${LAUNCHD_FILE}")"
    fi
  else
    record_check INFO launchd-installed "optional LaunchAgent not installed at ${target_plist}"
  fi
}

check_bind_ip_expectation() {
  TAILNET_BIND_IP="$(read_env_value "${REPO_ROOT}/stacks/ingress/.env" "TAILNET_BIND_IP")"

  if [[ -z "${TAILNET_BIND_IP}" ]]; then
    record_check FAIL ingress-bind-ip "TAILNET_BIND_IP is empty"
    return 0
  fi

  if [[ "${TAILNET_BIND_IP}" == "127.0.0.1" ]]; then
    record_check PASS ingress-bind-ip "localhost-bound ingress is configured"
    return 0
  fi

  if [[ "${TAILSCALE_READY}" != "1" ]]; then
    record_check FAIL ingress-bind-ip "TAILNET_BIND_IP is ${TAILNET_BIND_IP} but tailscale is not ready"
    return 0
  fi

  case " ${TAILSCALE_IPS} " in
    *" ${TAILNET_BIND_IP} "*)
      record_check PASS ingress-bind-ip "tailnet-bound ingress matches a tailscale IP (${TAILNET_BIND_IP})"
      ;;
    *)
      record_check FAIL ingress-bind-ip "TAILNET_BIND_IP=${TAILNET_BIND_IP} does not match tailscale IPs (${TAILSCALE_IPS})"
      ;;
  esac
}

first_container_state() {
  local project_name="$1"
  local compose_file="$2"
  local service_name="$3"
  local container_id=""

  container_id="$(docker compose -p "${project_name}" -f "${compose_file}" ps -a -q "${service_name}" 2>/dev/null | head -n 1)"
  if [[ -z "${container_id}" ]]; then
    return 0
  fi

  docker inspect --format '{{.State.Status}}' "${container_id}"
}

http_check() {
  local name="$1"
  local host="$2"
  local path="$3"
  local expected_code="$4"
  local bind_ip="$5"
  local expected_location_fragment="${6:-}"
  local headers_file="${RECEIPT_DIR}/doctor-${name}.headers.txt"
  local code=""
  local location=""

  if ! have_cmd curl; then
    record_check FAIL "http:${name}" "curl command is missing"
    return 0
  fi

  if code="$(curl -k -sS -D "${headers_file}" -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 15 --resolve "${host}:8443:${bind_ip}" "https://${host}:8443${path}")"; then
    location="$(awk 'BEGIN { IGNORECASE = 1 } /^location:/ {print $2}' "${headers_file}" | tr -d '\r' | tail -n 1)"
  else
    record_check FAIL "http:${name}" "curl failed for https://${host}${path} via ${bind_ip}"
    return 0
  fi

  if [[ "${code}" != "${expected_code}" ]]; then
    record_check FAIL "http:${name}" "expected=${expected_code} actual=${code}"
    return 0
  fi

  if [[ -n "${expected_location_fragment}" && "${location}" != *"${expected_location_fragment}"* ]]; then
    record_check FAIL "http:${name}" "expected redirect containing ${expected_location_fragment}, got ${location:-none}"
    return 0
  fi

  if [[ -n "${location}" ]]; then
    record_check PASS "http:${name}" "expected=${expected_code} actual=${code} location=${location}"
  else
    record_check PASS "http:${name}" "expected=${expected_code} actual=${code}"
  fi
}

check_http_expectations() {
  local ingress_state=""
  local auth_state=""

  if [[ "${DOCKER_READY}" != "1" ]]; then
    record_check WARN http-smoke "skipped because docker is unavailable"
    return 0
  fi

  if [[ -z "${TAILNET_BIND_IP}" ]]; then
    record_check WARN http-smoke "skipped because TAILNET_BIND_IP is unavailable"
    return 0
  fi

  ingress_state="$(first_container_state jcn-ingress "${REPO_ROOT}/stacks/ingress/compose.yml" caddy)"
  auth_state="$(first_container_state jcn-auth "${REPO_ROOT}/stacks/auth/compose.yml" authelia)"

  if [[ "${ingress_state}" != "running" ]]; then
    record_check INFO http-smoke "skipped because ingress is not running"
    return 0
  fi

  if [[ "${auth_state}" != "running" ]]; then
    record_check INFO http-smoke "skipped because auth is not running"
    return 0
  fi

  http_check auth-portal auth.internal.home.arpa /api/health 200 "${TAILNET_BIND_IP}"
  http_check grafana-gate grafana.internal.home.arpa / 302 "${TAILNET_BIND_IP}" auth.internal.home.arpa
  http_check prometheus-gate prom.internal.home.arpa / 302 "${TAILNET_BIND_IP}" auth.internal.home.arpa
  http_check loki-gate loki.internal.home.arpa /ready 302 "${TAILNET_BIND_IP}" auth.internal.home.arpa
}

write_summary() {
  local status="ok"

  if [[ "${FAILURES}" -gt 0 ]]; then
    status="fail"
  fi

  cat > "${SUMMARY_FILE}" <<EOF
status=${status}
failures=${FAILURES}
warnings=${WARNINGS}
receipt_dir=${RECEIPT_DIR}
checks_file=${CHECKS_FILE}
versions_file=${VERSIONS_FILE}
launchd_file=${LAUNCHD_FILE}
EOF
}

echo "receipt_dir=${RECEIPT_DIR}"
: > "${CHECKS_FILE}"

capture_versions
check_docker
check_tailscale
check_local_files
check_static_configs
check_compose_configs
check_launchd
check_bind_ip_expectation

for entry in "${STACKS[@]}"; do
  IFS=":" read -r stack_name compose_file project_name <<< "${entry}"
  inspect_stack_state "${stack_name}" "${compose_file}" "${project_name}"
done

check_http_expectations
write_summary

echo "doctor complete"

if [[ "${FAILURES}" -gt 0 ]]; then
  exit 1
fi
