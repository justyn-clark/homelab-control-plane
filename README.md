# homelab-control-plane

[![macOS](https://img.shields.io/badge/macOS-launchd-black)](ops/bootstrap/macos/)
[![Docker Compose](https://img.shields.io/badge/Docker-Compose-2496ED)](stacks/)
[![Caddy + Authelia](https://img.shields.io/badge/Ingress-Caddy%20%2B%20Authelia-00C389)](stacks/ingress/compose.yml)
[![Network Boundary](https://img.shields.io/badge/Network-Tailscale-242424)](runbooks/tailscale.md)

Single-node Mac mini control host for the JCN homelab.

The repo defines a private-by-default Docker Compose baseline with these fixed defaults:

- Ingress: Caddy
- Auth: Authelia
- Core: Postgres and Redis
- Observability: Prometheus, Grafana, Loki, and Promtail
- Backups: Restic script and runbook
- Optional bring-up trigger: macOS user LaunchAgent
- Network boundary: Tailscale only

## What This Is

This repository is an infrastructure-only control host for one Mac mini. It is not an application repo, not a cluster manager, and not a Kubernetes platform. It exists to define and operate a private internal-services baseline with receipts, explicit runbooks, and predictable bootstrap flows.

The current implementation is a single-node Compose stack with four active layers:

- `core`: Postgres and Redis
- `observability`: Prometheus, Grafana, Loki, and Promtail
- `auth`: Authelia
- `ingress`: Caddy

See [STATUS.md](STATUS.md) for the current state and remaining limitations.

## Layout

```text
.
|- CONTRACT.md
|- README.md
|- STATUS.md
|- ops/
|  |- backups/
|  |- bootstrap/macos/
|  `- secrets/
|- receipts/
|- runbooks/
`- stacks/
   |- auth/
   |- core/
   |- ingress/
   |- observability/
   `- optional/
```

## Preconditions

- macOS with Docker Desktop installed and running
- Tailscale installed, logged in, and the host joined to the target tailnet
- Local operator access to the Mac mini over Tailscale SSH or an equivalent Tailscale path
- Shell access with permission to run `docker` and `launchctl`

## Bring Up

1. Prepare local files from the committed templates.

```bash
cp stacks/core/env.example stacks/core/.env
cp stacks/observability/env.example stacks/observability/.env
cp stacks/ingress/env.example stacks/ingress/.env
cp stacks/auth/env.example stacks/auth/.env
cp stacks/auth/users_database.example.yml stacks/auth/users_database.yml
```

2. Bootstrap the local Authelia files.

```bash
AUTH_PASSWORD='change-me-now' ./ops/bootstrap/macos/bootstrap-auth.sh
```

Optional overrides:

```bash
AUTH_USERNAME=justin \
AUTH_DISPLAY_NAME='Justyn Clark' \
AUTH_EMAIL='justin@example.internal' \
AUTH_PASSWORD='change-me-now' \
./ops/bootstrap/macos/bootstrap-auth.sh
```

3. Run the operator doctor before first bring-up.

```bash
./ops/bootstrap/macos/doctor.sh
```

4. Run the bootstrap flow.

```bash
./ops/bootstrap/macos/install.sh
./ops/bootstrap/macos/bringup.sh
```

5. Run the operator doctor again after bring-up to capture a post-start receipt.

```bash
./ops/bootstrap/macos/doctor.sh
```

6. Optional: install the user LaunchAgent after the stack is healthy.

```bash
DRY_RUN=1 ./ops/bootstrap/macos/install-launchd.sh
./ops/bootstrap/macos/install-launchd.sh
```

7. Optional: run a Restic backup once the stack has data.

```bash
RESTIC_REPOSITORY=/path/to/restic-repo \
RESTIC_PASSWORD_FILE=/path/to/restic-password \
./ops/backups/restic/backup.sh
```

## Operator Doctor

`./ops/bootstrap/macos/doctor.sh` is the operator validation command for this repo.

It writes a receipt bundle under `receipts/<timestamp>/` and validates, when applicable:

- Docker command availability and daemon reachability
- Tailscale command availability and tailnet IPv4 presence
- Required local env files and auth bootstrap outputs
- Compose file and mounted config presence
- `docker compose config` for each stack
- LaunchAgent template validity and installed LaunchAgent status when present
- Container state and health for stacks that already have containers
- Ingress and auth smoke behavior when Caddy and Authelia are running

The doctor is intentionally safe to run both before and after `bringup.sh`.

## Smoke Verification Sequence

This command sequence should produce green file validation, Compose validation, container health checks, and HTTP smoke checks once the local files are in place:

```bash
cp stacks/core/env.example stacks/core/.env
cp stacks/observability/env.example stacks/observability/.env
cp stacks/ingress/env.example stacks/ingress/.env
cp stacks/auth/env.example stacks/auth/.env
cp stacks/auth/users_database.example.yml stacks/auth/users_database.yml
AUTH_PASSWORD='change-me-now' ./ops/bootstrap/macos/bootstrap-auth.sh
./ops/bootstrap/macos/doctor.sh
./ops/bootstrap/macos/install.sh
./ops/bootstrap/macos/bringup.sh
./ops/bootstrap/macos/doctor.sh
```

`bringup.sh` checks the expected Compose service set for each stack and fails if an expected container is missing or lands in `created`, `dead`, `exited`, `restarting`, or `unhealthy` state.

## Access Model

The default ingress path is localhost-bound:

- `stacks/ingress/env.example` sets `TAILNET_BIND_IP=127.0.0.1`
- Caddy therefore publishes only on localhost by default
- Operators reach the Mac mini through Tailscale, then access the control host locally on that machine

Default local smoke checks:

```bash
curl -k -I --resolve grafana.internal.home.arpa:8443:127.0.0.1 https://grafana.internal.home.arpa:8443/
curl -k -I --resolve prom.internal.home.arpa:8443:127.0.0.1 https://prom.internal.home.arpa:8443/
curl -k -I --resolve auth.internal.home.arpa:8443:127.0.0.1 https://auth.internal.home.arpa:8443/api/health
curl -k -I --resolve loki.internal.home.arpa:8443:127.0.0.1 https://loki.internal.home.arpa:8443/ready
```

If you want direct HTTPS reachability from other tailnet nodes, set `TAILNET_BIND_IP` in `stacks/ingress/.env` to the host tailnet IP before running `bringup.sh`. That path is supported by the code but is not the default.

The scripted HTTPS checks are smoke checks only:

- `auth.internal.home.arpa/api/health` must return `200`
- Protected routes must return `302` with a redirect toward `auth.internal.home.arpa`
- These checks use Caddy's local CA, so command-line smoke checks pass `-k` unless the local CA is trusted
- These checks do not prove an interactive Authelia login flow or full browser usability

## Sample Receipt Tree

Template only. Actual timestamps and outputs are created at runtime.

```text
receipts/
|- .gitkeep
|- launchd/
|  |- .gitkeep
|  |- bringup.stderr.log
|  `- bringup.stdout.log
`- 20260305T150405Z/
   |- auth-bootstrap-files.txt
   |- auth-bootstrap-inputs.txt
   |- auth-bootstrap-summary.txt
   |- bringup.log
   |- doctor-checks.txt
   |- doctor-containers.txt
   |- doctor-launchd.txt
   |- doctor-summary.txt
   |- doctor-versions.txt
   |- endpoints.txt
   |- healthchecks.txt
   |- http-auth-portal.headers.txt
   |- http-grafana-gate.headers.txt
   |- http-loki-gate.headers.txt
   |- http-prometheus-gate.headers.txt
   |- stack-auth.ps.txt
   |- stack-core.ps.txt
   |- stack-ingress.ps.txt
   |- stack-observability.ps.txt
   `- versions.txt
```

## LaunchAgent Behavior

The committed launchd asset at [`ops/bootstrap/macos/launchd/com.jcn.controlplane.plist`](ops/bootstrap/macos/launchd/com.jcn.controlplane.plist) is a portable template with repo-path placeholders. [`ops/bootstrap/macos/install-launchd.sh`](ops/bootstrap/macos/install-launchd.sh) renders that template with the current repo path, lints the rendered plist, and installs it to `~/Library/LaunchAgents/com.jcn.controlplane.plist`.

```bash
DRY_RUN=1 ./ops/bootstrap/macos/install-launchd.sh
./ops/bootstrap/macos/install-launchd.sh
```

This LaunchAgent is user-session scoped:

- It runs `bringup.sh` once when the agent is loaded or when that user logs in
- It does not use `KeepAlive` or `StartInterval`
- It is not a daemon supervisor for the Compose stack
- It is not a machine-boot guarantee for a headless host because `~/Library/LaunchAgents` requires the user session

Docker Compose restart policies remain responsible for keeping already-started containers running after bring-up.

The installer writes deterministic runtime logs under `receipts/launchd/` and a timestamped install receipt under `receipts/<timestamp>/`.

## Runbooks

- [runbooks/tailscale.md](runbooks/tailscale.md)
- [runbooks/backups-restic.md](runbooks/backups-restic.md)
- [runbooks/recovery.md](runbooks/recovery.md)
- [runbooks/onboarding-new-node.md](runbooks/onboarding-new-node.md)

## Current Status

The repo is operationally coherent as a single-node private services baseline. The main limitations that still remain are user-session-scoped launchd behavior, manual restore work, and the lack of an interactive browser-auth validation path in the scripted checks.
