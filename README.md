# homelab-control-plane

Reproducible Mac mini control plane for the JCN homelab.

The repo builds a private-by-default control plane with these fixed defaults:

- Ingress: Caddy
- Auth: Authelia
- Core: Postgres and Redis
- Observability: Prometheus, Grafana, Loki, and Promtail
- Backups: Restic runbook and retention guidance
- Supervisor: macOS launchd
- Network boundary: Tailscale only

## What This Is

This repository is an infrastructure-only control plane for a single Mac mini. It is not an application repo. It exists to define and operate a private control-plane baseline for JCN homelab services with receipts, explicit runbooks, and predictable bootstrap flows.

The current implementation is a single-node Compose-based stack with four active layers:

- `core`: Postgres and Redis
- `observability`: Prometheus, Grafana, Loki, and Promtail
- `auth`: Authelia
- `ingress`: Caddy

See [STATUS.md](/Users/justin/Documents/Justyn Clark Network/REPOS/homelab-control-plane/STATUS.md) for the current state, coherency gaps, hardening opportunities, and recommended next steps.

## Layout

```text
.
|- CONTRACT.md
|- README.md
|- ops/
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

1. Prepare local env files from the committed templates.

```bash
cp stacks/core/env.example stacks/core/.env
cp stacks/observability/env.example stacks/observability/.env
cp stacks/ingress/env.example stacks/ingress/.env
cp stacks/auth/env.example stacks/auth/.env
cp stacks/auth/users_database.example.yml stacks/auth/users_database.yml
```

2. Generate non-committed secrets and hashes into `stacks/auth/.env`.

```bash
AUTHELIA_SESSION_SECRET="$(openssl rand -hex 32)" \
AUTHELIA_STORAGE_ENCRYPTION_KEY="$(openssl rand -hex 32)" \
AUTHELIA_JWT_SECRET="$(openssl rand -hex 32)" \
AUTHELIA_PASSWORD_HASH="$(docker run --rm authelia/authelia:4 authelia crypto hash generate argon2 --password 'change-me-now' | tail -n 1)" \
python3 - <<'PY'
from pathlib import Path

auth_env = Path("stacks/auth/.env")
auth_lines = auth_env.read_text().splitlines()
values = {
    "AUTHELIA_SESSION_SECRET": __import__("os").environ["AUTHELIA_SESSION_SECRET"],
    "AUTHELIA_STORAGE_ENCRYPTION_KEY": __import__("os").environ["AUTHELIA_STORAGE_ENCRYPTION_KEY"],
    "AUTHELIA_JWT_SECRET": __import__("os").environ["AUTHELIA_JWT_SECRET"],
    "AUTHELIA_PASSWORD_HASH": __import__("os").environ["AUTHELIA_PASSWORD_HASH"],
}
updated = []
for line in auth_lines:
    if "=" in line and not line.startswith("#"):
        key = line.split("=", 1)[0]
        updated.append(f"{key}={values.get(key, line.split('=', 1)[1])}")
    else:
        updated.append(line)
auth_env.write_text("\n".join(updated) + "\n")
PY
```

3. Adjust `stacks/auth/users_database.yml` if you want a different username or email.

4. Run the bootstrap flow.

```bash
./ops/bootstrap/macos/install.sh
./ops/bootstrap/macos/bringup.sh
```

5. Optional: install launchd persistence after the stack is healthy.

```bash
DRY_RUN=1 ./ops/bootstrap/macos/install-launchd.sh
./ops/bootstrap/macos/install-launchd.sh
```

6. Optional: run a Restic backup once the stack has data.

```bash
RESTIC_REPOSITORY=/path/to/restic-repo \
RESTIC_PASSWORD_FILE=/path/to/restic-password \
./ops/backups/restic/backup.sh
```

## Green Verification Sequence

This command sequence should produce green health checks for the included services once the env files are in place:

```bash
cp stacks/core/env.example stacks/core/.env
cp stacks/observability/env.example stacks/observability/.env
cp stacks/ingress/env.example stacks/ingress/.env
cp stacks/auth/env.example stacks/auth/.env
cp stacks/auth/users_database.example.yml stacks/auth/users_database.yml
AUTHELIA_SESSION_SECRET="$(openssl rand -hex 32)" \
AUTHELIA_STORAGE_ENCRYPTION_KEY="$(openssl rand -hex 32)" \
AUTHELIA_JWT_SECRET="$(openssl rand -hex 32)" \
AUTHELIA_PASSWORD_HASH="$(docker run --rm authelia/authelia:4 authelia crypto hash generate argon2 --password 'change-me-now' | tail -n 1)" \
python3 - <<'PY'
from pathlib import Path
import os
auth_env = Path("stacks/auth/.env")
auth_lines = auth_env.read_text().splitlines()
values = {
    "AUTHELIA_SESSION_SECRET": os.environ["AUTHELIA_SESSION_SECRET"],
    "AUTHELIA_STORAGE_ENCRYPTION_KEY": os.environ["AUTHELIA_STORAGE_ENCRYPTION_KEY"],
    "AUTHELIA_JWT_SECRET": os.environ["AUTHELIA_JWT_SECRET"],
    "AUTHELIA_PASSWORD_HASH": os.environ["AUTHELIA_PASSWORD_HASH"],
}
auth_env.write_text("\n".join(
    f"{line.split('=', 1)[0]}={values.get(line.split('=', 1)[0], line.split('=', 1)[1])}"
    if "=" in line and not line.startswith("#") else line
    for line in auth_lines
) + "\n")
PY
./ops/bootstrap/macos/install.sh
./ops/bootstrap/macos/bringup.sh
```

## Access Model

The current default is localhost-bound ingress:

- `stacks/ingress/env.example` sets `TAILNET_BIND_IP=127.0.0.1`
- Caddy therefore publishes only on localhost by default
- Operators reach the Mac mini through Tailscale, then access the control plane locally on that host

Default local verification:

```bash
curl -I --resolve grafana.internal:80:127.0.0.1 http://grafana.internal/
curl -I --resolve prom.internal:80:127.0.0.1 http://prom.internal/
curl -I --resolve auth.internal:80:127.0.0.1 http://auth.internal/
```

If you want direct HTTP reachability from other tailnet nodes, set `TAILNET_BIND_IP` in `stacks/ingress/.env` to the host tailnet IP before running `bringup.sh`. That path is supported by the code but is not the default.

Protected routes should return `302` to `auth.internal` before login. The Auth portal health endpoint should return `200`.

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
   |- bringup.log
   |- endpoints.txt
   |- healthchecks.txt
   |- stack-auth.ps.txt
   |- stack-core.ps.txt
   |- stack-ingress.ps.txt
   |- stack-observability.ps.txt
   `- versions.txt
```

## Boot Persistence

The launchd asset lives at [ops/bootstrap/macos/launchd/com.jcn.controlplane.plist](/Users/justin/Documents/Justyn Clark Network/REPOS/homelab-control-plane/ops/bootstrap/macos/launchd/com.jcn.controlplane.plist). Use [ops/bootstrap/macos/install-launchd.sh](/Users/justin/Documents/Justyn Clark Network/REPOS/homelab-control-plane/ops/bootstrap/macos/install-launchd.sh) to render the plist with the current repo path, lint it, and install it as a user LaunchAgent with receipt output.

```bash
DRY_RUN=1 ./ops/bootstrap/macos/install-launchd.sh
./ops/bootstrap/macos/install-launchd.sh
```

The installer writes deterministic runtime logs under `receipts/launchd/` and a timestamped install receipt under `receipts/<timestamp>/`.

## Runbooks

- [runbooks/tailscale.md](/Users/justin/Documents/Justyn Clark Network/REPOS/homelab-control-plane/runbooks/tailscale.md)
- [runbooks/backups-restic.md](/Users/justin/Documents/Justyn Clark Network/REPOS/homelab-control-plane/runbooks/backups-restic.md)
- [runbooks/recovery.md](/Users/justin/Documents/Justyn Clark Network/REPOS/homelab-control-plane/runbooks/recovery.md)
- [runbooks/onboarding-new-node.md](/Users/justin/Documents/Justyn Clark Network/REPOS/homelab-control-plane/runbooks/onboarding-new-node.md)

## Current Status

The repo is coherent as a single-node infrastructure baseline, but not yet complete as a fully automated homelab product. The most important remaining gaps are auth bootstrap, restore automation, stronger smoke tests, and a deliberate decision on whether direct tailnet HTTP should stay opt-in or become the default.
