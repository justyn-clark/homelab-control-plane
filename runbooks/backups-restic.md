# Restic Backup Runbook

## Scope

Back up durable control plane state and config artifacts:

- Docker named volumes for Postgres, Redis, Grafana, Loki, and Authelia
- Stack configuration under `stacks/`
- Runbooks and operational scripts

Primary operator entrypoint:

```bash
RESTIC_REPOSITORY=/path/to/restic-repo \
RESTIC_PASSWORD_FILE=/path/to/restic-password \
./ops/backups/restic/backup.sh
```

## Recommended Targets

- Postgres volume snapshot or logical dump
- Redis appendonly file
- Grafana and Loki data volumes
- Authelia SQLite database and notification file
- Stack configuration files excluding `.env` and user secrets

## What The Script Captures

- Volume archives for Postgres, Redis, Prometheus, Loki, Grafana, and Authelia when the named volumes exist
- A Postgres logical dump when the core stack is running
- Stack definitions, runbooks, bootstrap scripts, and top-level contract docs
- A receipt bundle under `receipts/<timestamp>/` with backup logs and Restic output

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
