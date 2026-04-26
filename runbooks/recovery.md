# Recovery Runbook

## Reboot Recovery

1. Confirm Docker Desktop is running and reachable with `docker info`
2. Confirm Tailscale is online with `tailscale status`
3. Run `./ops/bootstrap/macos/doctor.sh` to capture a pre-bring-up validation receipt
4. If the optional LaunchAgent is installed, remember it is user-session scoped under `~/Library/LaunchAgents`; confirm the operator account is logged in and check `receipts/launchd/`
5. Run `./ops/bootstrap/macos/bringup.sh` manually if the stack is not already healthy
6. Run `./ops/bootstrap/macos/doctor.sh` again and review the latest receipt bundle for failures

## Disk Full

1. Inspect Docker disk usage with `docker system df`
2. Review large receipt bundles and old backup artifacts
3. Prune only unused images and stopped containers
4. Re-run `./ops/bootstrap/macos/doctor.sh` and `./ops/bootstrap/macos/bringup.sh` after capacity is restored

## Corrupt Volume

1. Stop the affected stack with `docker compose -p <project> -f <compose> down`
2. Restore the damaged volume from Restic or a validated dump
3. Recreate the stack with `docker compose -p <project> -f <compose> up -d`
4. Confirm health with `./ops/bootstrap/macos/doctor.sh` and the new receipt bundle

## Restore Procedure

1. Restore the backed-up `stacks/` tree if local `.env` files or `users_database.yml` were lost; this repository's backup script includes them when present
2. Restore Postgres from `postgres.dump.sql`, `pg_restore`, or `psql` against a recreated container as appropriate
3. Restore named volume data for Grafana, Loki, Redis, and Authelia if required
4. Run `./ops/bootstrap/macos/doctor.sh`
5. Run `./ops/bootstrap/macos/bringup.sh`
6. Validate the receipt bundle with `./ops/bootstrap/macos/doctor.sh`, then perform manual browser validation if auth-gated access must be proven interactively
