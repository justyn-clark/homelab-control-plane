# Restic Backup Runbook

## Scope

Back up durable control plane state and config artifacts:

- Docker named volumes for Postgres, Redis, Grafana, Loki, and Authelia
- Stack configuration under `stacks/`
- Runbooks and operational scripts

## Recommended Targets

- Postgres volume snapshot or logical dump
- Redis appendonly file
- Grafana and Loki data volumes
- Authelia SQLite database and notification file
- Stack configuration files excluding `.env` and user secrets

## Example Commands

Create a Postgres dump:

```bash
docker compose -p jcn-core -f stacks/core/compose.yml exec -T postgres \
  pg_dump -U "${POSTGRES_USER}" "${POSTGRES_DB}" > postgres.dump.sql
```

Run a Restic backup:

```bash
export RESTIC_REPOSITORY=/path/to/restic-repo
export RESTIC_PASSWORD_FILE=/path/to/restic-password
restic backup \
  stacks \
  runbooks \
  postgres.dump.sql
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

