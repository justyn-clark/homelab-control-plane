# Project Status

## Summary

This repository is an infrastructure-only control plane scaffold for a single Mac mini in the JCN homelab.

It currently provides:

- Docker Compose stacks for core data services, observability, auth, and ingress
- macOS bootstrap scripts for install, bringup, and launchd installation
- A Restic backup script with receipt output
- Runbooks for Tailscale, onboarding, backup, and recovery
- A receipts-first operating model for scripted actions

## Product Intent Versus Current Reality

The product intent is a private-by-default control plane that is reached only through Tailscale.

The current codebase supports that intent partially:

- The stack composition and supervisor model are in place
- Ingress is private by default because Caddy binds to `127.0.0.1` unless the operator chooses a different `TAILNET_BIND_IP`
- Authelia gates Grafana, Prometheus, and Loki through Caddy
- Direct tailnet HTTP access is not enabled by default because `TAILNET_BIND_IP` defaults to `127.0.0.1`
- Tailnet access today is best understood as operator access to the host, then local access to the control plane, unless the operator explicitly binds Caddy to a tailnet IP

## Coherency Gaps

- There is no one-command env generation flow for Authelia secrets and user bootstrap
- There is no restore automation yet, only recovery documentation
- There is no alerting, dashboard pack, or SLO layer on top of Prometheus and Grafana
- There is no automated validation that Authelia forward-auth behavior still returns the expected status codes after image upgrades
- There is no DNS automation for the `*.internal` hostnames
- The stack is still optimized for a single operator-managed node, not multiple nodes or shared ownership

## Hardening Opportunities

- Add a deterministic env initialization script for auth secrets and operator bootstrap
- Add a restore script that reverses the Restic backup workflow with receipts
- Pin and periodically review image digests instead of tags alone
- Add receipt-driven smoke tests that assert protected routes, redirects, and container health in one place
- Add a minimal Prometheus alert rules file and provision Grafana dashboards
- Add explicit Docker volume restore procedures and verification checks

## Future Scale Paths

- Split shared config generation from node-local state so a second control-plane node can reuse the same patterns
- Move from manual hostname resolution to a deliberate private DNS pattern
- Introduce per-service contracts for new internal tools rather than growing the repo into a mixed app-and-infra codebase
- Add node role overlays under `stacks/optional/` instead of changing the v1 base path
- Standardize a small set of operational commands so AI agents and human operators use the same flow

## Recommended Next Steps

1. Add an auth bootstrap script that creates `.env` files and a valid `users_database.yml` from local operator input or generated defaults.
2. Add a restore script for Restic plus a recovery receipt that proves restore viability.
3. Add a doctor or smoke-test script that validates Docker, Tailscale, launchd, and HTTP auth behavior before and after bringup.
4. Decide whether direct tailnet HTTP should remain opt-in or become the default, then align `TAILNET_BIND_IP`, runbooks, and validation around that choice.

