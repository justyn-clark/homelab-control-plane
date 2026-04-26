#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
RECEIPT_TS="$(date -u +"%Y%m%dT%H%M%SZ")"
RECEIPT_DIR="${REPO_ROOT}/receipts/${RECEIPT_TS}"
LOG_FILE="${RECEIPT_DIR}/bringup.log"
VERSIONS_FILE="${RECEIPT_DIR}/versions.txt"
HEALTH_FILE="${RECEIPT_DIR}/healthchecks.txt"
ENDPOINTS_FILE="${RECEIPT_DIR}/endpoints.txt"

mkdir -p "${RECEIPT_DIR}" "${REPO_ROOT}/receipts/launchd"
exec > >(tee -a "${LOG_FILE}") 2>&1

STACKS=(
  "core:${REPO_ROOT}/stacks/core/compose.yml:jcn-core"
  "observability:${REPO_ROOT}/stacks/observability/compose.yml:jcn-observability"
  "auth:${REPO_ROOT}/stacks/auth/compose.yml:jcn-auth"
  "ingress:${REPO_ROOT}/stacks/ingress/compose.yml:jcn-ingress"
)

require_file() {
  local path="$1"
  if [[ ! -f "${path}" ]]; then
    echo "missing required file: ${path}"
    exit 1
  fi
}

capture_versions() {
  {
    echo "## docker"
    docker version
    echo
    echo "## docker compose"
    docker compose version
    echo
    echo "## tailscale"
    tailscale version || true
    echo
    echo "## tailscale ip"
    tailscale ip -4 || true
  } > "${VERSIONS_FILE}"
}

wait_for_docker() {
  local tries=60
  until docker info >/dev/null 2>&1; do
    tries=$((tries - 1))
    if [[ "${tries}" -le 0 ]]; then
      echo "docker daemon did not become ready"
      exit 1
    fi
    sleep 5
  done
}

compose_ps() {
  local stack_name="$1"
  local compose_file="$2"
  local project_name="$3"
  docker compose -p "${project_name}" -f "${compose_file}" ps -a > "${RECEIPT_DIR}/stack-${stack_name}.ps.txt"
}

inspect_health() {
  local stack_name="$1"
  local compose_file="$2"
  local project_name="$3"
  local -a containers=()
  local tries=30

  while [[ "${tries}" -gt 0 ]]; do
    local failed=0
    compose_ps "${stack_name}" "${compose_file}" "${project_name}"

    while read -r service; do
      [[ -z "${service}" ]] && continue

      local service_failed=0
      containers=()
      while read -r container_id; do
        [[ -z "${container_id}" ]] && continue
        containers+=("${container_id}")
      done < <(docker compose -p "${project_name}" -f "${compose_file}" ps -a -q "${service}")

      if [[ "${#containers[@]}" -eq 0 ]]; then
        echo "${project_name}/${service} state=missing health=missing" >> "${HEALTH_FILE}"
        failed=1
        continue
      fi

      for container_id in "${containers[@]}"; do
        local inspect_output
        local container_name
        local container_state
        local container_health

        inspect_output="$(docker inspect --format '{{.Name}}|{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "${container_id}")"
        IFS='|' read -r container_name container_state container_health <<< "${inspect_output}"
        container_name="${container_name#/}"

        echo "${project_name}/${service} container=${container_name} state=${container_state} health=${container_health}" >> "${HEALTH_FILE}"

        if [[ "${container_state}" != "running" ]]; then
          service_failed=1
          continue
        fi

        if [[ "${container_health}" != "healthy" && "${container_health}" != "none" ]]; then
          service_failed=1
        fi
      done

      if [[ "${service_failed}" -ne 0 ]]; then
        failed=1
      fi
    done < <(docker compose -p "${project_name}" -f "${compose_file}" config --services)

    if [[ "${failed}" -eq 0 ]]; then
      return 0
    fi

    tries=$((tries - 1))
    sleep 5
  done

  compose_ps "${stack_name}" "${compose_file}" "${project_name}"
  echo "health check timeout for project ${project_name}"
  exit 1
}

http_check() {
  local name="$1"
  local host="$2"
  local path="$3"
  local expected="$4"
  local bind_ip="$5"
  local expected_location_fragment="${6:-}"
  local headers_file="${RECEIPT_DIR}/http-${name}.headers.txt"
  local code
  local location

  code="$(curl -k -sS -D "${headers_file}" -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 15 --resolve "${host}:8443:${bind_ip}" "https://${host}:8443${path}")"
  location="$(awk 'BEGIN { IGNORECASE = 1 } /^location:/ {print $2}' "${headers_file}" | tr -d '\r' | tail -n 1)"
  echo "${name} ${host}${path} expected=${expected} actual=${code} location=${location:-none}" >> "${HEALTH_FILE}"

  if [[ "${code}" != "${expected}" ]]; then
    echo "http health check failed for ${host}${path}: expected ${expected}, got ${code}"
    exit 1
  fi

  if [[ -n "${expected_location_fragment}" && "${location}" != *"${expected_location_fragment}"* ]]; then
    echo "http health check failed for ${host}${path}: expected redirect containing ${expected_location_fragment}, got ${location:-none}"
    exit 1
  fi
}

echo "receipt_dir=${RECEIPT_DIR}"

require_file "${REPO_ROOT}/stacks/core/.env"
require_file "${REPO_ROOT}/stacks/observability/.env"
require_file "${REPO_ROOT}/stacks/ingress/.env"
require_file "${REPO_ROOT}/stacks/auth/.env"
require_file "${REPO_ROOT}/stacks/auth/users_database.yml"

wait_for_docker
capture_versions

docker network inspect jcn-controlplane >/dev/null 2>&1 || docker network create jcn-controlplane >/dev/null

for entry in "${STACKS[@]}"; do
  IFS=":" read -r stack_name compose_file project_name <<< "${entry}"
  echo "starting ${stack_name}"
  docker compose -p "${project_name}" -f "${compose_file}" up -d
  compose_ps "${stack_name}" "${compose_file}" "${project_name}"
  inspect_health "${stack_name}" "${compose_file}" "${project_name}"
done

TAILNET_BIND_IP="$(grep '^TAILNET_BIND_IP=' "${REPO_ROOT}/stacks/ingress/.env" | cut -d= -f2-)"
if [[ -z "${TAILNET_BIND_IP}" ]]; then
  echo "TAILNET_BIND_IP is not set"
  exit 1
fi

http_check "auth-portal" "auth.internal.home.arpa" "/api/health" "200" "${TAILNET_BIND_IP}"
http_check "grafana-gate" "grafana.internal.home.arpa" "/" "302" "${TAILNET_BIND_IP}" "auth.internal.home.arpa"
http_check "prometheus-gate" "prom.internal.home.arpa" "/" "302" "${TAILNET_BIND_IP}" "auth.internal.home.arpa"
http_check "loki-gate" "loki.internal.home.arpa" "/ready" "302" "${TAILNET_BIND_IP}" "auth.internal.home.arpa"

cat > "${ENDPOINTS_FILE}" <<EOF
bind_ip=${TAILNET_BIND_IP}

internal_hostnames:
- auth.internal.home.arpa
- grafana.internal.home.arpa
- prom.internal.home.arpa
- prometheus.internal.home.arpa
- loki.internal.home.arpa

test_commands:
curl -k -I --resolve auth.internal.home.arpa:8443:${TAILNET_BIND_IP} https://auth.internal.home.arpa:8443/api/health
curl -k -I --resolve grafana.internal.home.arpa:8443:${TAILNET_BIND_IP} https://grafana.internal.home.arpa:8443/
curl -k -I --resolve prom.internal.home.arpa:8443:${TAILNET_BIND_IP} https://prom.internal.home.arpa:8443/
curl -k -I --resolve loki.internal.home.arpa:8443:${TAILNET_BIND_IP} https://loki.internal.home.arpa:8443/ready
EOF

echo "bringup complete"
