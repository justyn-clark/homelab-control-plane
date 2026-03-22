# Restic Backup Runbook

## Scope

Back up durable control-host state and config artifacts:

- Docker named volumes for Postgres, Redis, Grafana, Loki, and Authelia
- Stack configuration under `stacks/`
- Runbooks and operational scripts
- The backup receipt bundle created for the current run

Primary operator entrypoint:

```bash
RESTIC_REPOSITORY=/path/to/restic-repo \
RESTIC_PASSWORD_FILE=/path/to/restic-password \
./ops/backups/restic/backup.sh
```

## What The Script Captures

- Volume archives for Postgres, Redis, Prometheus, Loki, Grafana, and Authelia when the named volumes exist
- A Postgres logical dump when the core stack is running
- The full `stacks/` tree, including local `.env` files and `stacks/auth/users_database.yml` when they exist
- The `runbooks/` and `ops/` trees
- Top-level `README.md` and `CONTRACT.md`
- A receipt bundle under `receipts/<timestamp>/` with backup logs, Restic output, volume archives, and `postgres.dump.sql` when created

## Secret Handling

This backup scope is secret-bearing by design:

- Backing up `stacks/` includes local `.env` files and the Authelia users database if present
- The receipt bundle can include `postgres.dump.sql` and volume archives with application data
- Restored receipt bundles and Restic snapshots should therefore be handled as sensitive material

If this is too broad for the environment, change the script and the runbook together. The current repository intentionally backs up the local service config and auth material needed to restore this single node.

## Example Commands

Initialize a new local Restic repository:

```bash
mkdir -p .local/restic
printf '%s\n' 'replace-this-password' > .local/restic/password.txt
chmod 600 .local/restic/password.txt
RESTIC_REPOSITORY="$(pwd)/.local/restic/repo" \
RESTIC_PASSWORD_FILE="$(pwd)/.local/restic/password.txt" \
restic init
```

Run the repository backup script:

```bash
RESTIC_REPOSITORY="$(pwd)/.local/restic/repo" \
RESTIC_PASSWORD_FILE="$(pwd)/.local/restic/password.txt" \
./ops/backups/restic/backup.sh
```

Check retention:

```bash
restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune
```

## Retention Guidance

- Daily: 7
- Weekly: 4
- Monthly: 6
- Validate restores quarterly
- Keep the Restic repository outside the Mac mini boot disk when possible
- Treat the Restic repository and restore targets as secret-bearing storage
