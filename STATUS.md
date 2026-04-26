# Project Status

## Summary

This repository is a single-node private control host for one Mac mini in the JCN homelab.

It currently provides:

- Docker Compose stacks for core data services, observability, auth, and ingress
- macOS bootstrap scripts for install, auth bootstrap, bring-up, doctor validation, and optional LaunchAgent installation
- A Restic backup script with receipt output
- Runbooks for Tailscale, backup, recovery, and operator access from another tailnet client
- A receipts-first operating model for scripted actions

## Current Shape

- Ingress is private by default because Caddy binds to `127.0.0.1` unless the operator deliberately sets a tailnet IP in `TAILNET_BIND_IP`
- Authelia gates Grafana, Prometheus, and Loki through Caddy
- `bringup.sh` validates expected Compose services from the compose metadata and fails if a service container is missing, exited, dead, restarting, or unhealthy
- `doctor.sh` validates Docker, Tailscale, required local files, Compose config, LaunchAgent state, running-container health, and ingress smoke behavior when the stack is up
- HTTPS verification is limited to smoke checks: `auth.internal.home.arpa:8443/api/health` must return `200`, and protected routes must redirect toward `auth.internal.home.arpa:8443`
- The backup workflow captures named volumes, a Postgres logical dump when available, `stacks/`, `runbooks/`, `ops/`, selected top-level docs, and the current backup receipt bundle

## Current Limits

- Launchd integration is installed under `~/Library/LaunchAgents`, so it is user-session scoped rather than a machine-boot guarantee
- The LaunchAgent runs `bringup.sh` once at load or login; it is not the long-running supervisor for the Docker Compose stack
- The scripted checks do not verify a full browser login through Authelia
- `doctor.sh` is operator-invoked; `bringup.sh` does not yet require a preflight doctor pass before it starts containers
- Restore remains manual and runbook-driven
- The repo is intentionally optimized for a single operator-managed host, not a cluster or multi-node platform

## Recommended Next Steps

1. Perform and capture a full restore rehearsal against this node so backup and recovery claims are proven end to end.
2. Decide whether `doctor.sh` should become a mandatory preflight gate in the operating flow or remain an explicit operator command.
3. Keep manual browser validation in the operating cadence after auth, ingress, or image changes.
