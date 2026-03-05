# Repository Contract

## Purpose

This repository defines a single-node control plane for a JCN homelab running on macOS. It is the source of truth for stack definitions, bootstrap logic, runbooks, and receipts conventions.

This repository contains infrastructure only. It must not include application source or product code for JCNBot, loopexec, reaper-studio, or other JCN application repositories.

## Boundaries

- Single repository only
- Single-node control plane only
- No Kubernetes, k3s, Talos, Proxmox, or cluster control plane abstractions
- No public ingress or public listeners
- No committed secrets
- No optional application workloads in the v1 green path
- No application source trees or bundled app runtimes for JCNBot, loopexec, reaper-studio, or similar JCN projects

## Invariants

- macOS `launchd` is the only boot persistence supervisor defined here
- Every operational script writes a timestamped receipt bundle under `receipts/`
- All service entrypoints are private-by-default and intended for tailnet reachability only
- Ingress uses Caddy
- Authentication uses Authelia forward-auth
- Core services are Postgres and Redis
- Observability uses Prometheus, Grafana, Loki, and Promtail
- Backups are documented around Restic
- Environment defaults are expressed through committed `env.example` files only
- Secrets are supplied at runtime through ignored files and local operator workflows

## Network Model

- Docker services communicate across a shared internal bridge network named `jcn-controlplane`
- Only Caddy publishes host ports
- Caddy binds to `TAILNET_BIND_IP` or `127.0.0.1`
- Internal hostnames are routed by Host header and intended to resolve only within the tailnet or via `curl --resolve`

## Receipts Contract

Each receipt bundle is stored under `receipts/<timestamp>/` and must include:

- version capture for Docker, Compose, and Tailscale
- per-stack `docker compose ps` output
- health-check results
- effective hostnames and test commands
- script stdout log when the script performs multi-step orchestration

## Change Discipline

- New dependencies require explicit justification and must fit the existing control plane model
- Divergence from the fixed defaults in this contract requires changing this file first
- Documentation and runbooks are part of the deliverable, not optional follow-up work
