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
- A reachable tailnet IP for this Mac mini
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

## Testing From The Tailnet

The ingress stack binds Caddy to `127.0.0.1` by default. Reachability is intended through Tailscale access to the host, with local testing through `curl --resolve` unless your private DNS already maps the internal names:

```bash
curl -I --resolve grafana.internal:80:127.0.0.1 http://grafana.internal/
curl -I --resolve prom.internal:80:127.0.0.1 http://prom.internal/
curl -I --resolve auth.internal:80:127.0.0.1 http://auth.internal/
```

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
