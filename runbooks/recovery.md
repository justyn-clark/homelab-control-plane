# Recovery Runbook

## Reboot Recovery

1. Confirm Docker Desktop is running and reachable with `docker info`
2. Confirm Tailscale is online with `tailscale status`
3. Check launchd logs under `receipts/launchd/`
4. Run `./ops/bootstrap/macos/bringup.sh`
5. Review the latest receipt bundle for failures

## Disk Full

1. Inspect Docker disk usage with `docker system df`
2. Review large receipt bundles and old backup artifacts
3. Prune only unused images and stopped containers
4. Re-run bringup after capacity is restored

## Corrupt Volume

1. Stop the affected stack with `docker compose -p <project> -f <compose> down`
2. Restore the damaged volume from Restic or a validated dump
3. Recreate the stack with `docker compose -p <project> -f <compose> up -d`
4. Confirm health from the new receipt bundle

## Restore Procedure

1. Restore stack configs and ignored env files from secure local storage
2. Restore Postgres from `pg_restore` or `psql` against a recreated container
3. Restore named volume data for Grafana, Loki, Redis, and Authelia if required
4. Run `./ops/bootstrap/macos/bringup.sh`
5. Validate ingress and auth flows from another tailnet node

