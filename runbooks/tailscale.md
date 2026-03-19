# Tailscale Runbook

## Scope

This control plane assumes Tailscale is the only reachability path for operators and peer nodes.

Current default access model:

- Tailscale is used to reach the Mac mini
- Caddy binds to `127.0.0.1` by default
- Operators then access internal hostnames locally on the host, for example through Tailscale SSH
- Direct HTTP from another tailnet node requires explicitly binding Caddy to the host tailnet IP

## Tailscale SSH

- Enable Tailscale SSH on the Mac mini for admin access
- Prefer host-based tags over user-based long-lived exceptions
- Keep shell access separate from HTTP access

Example checks:

```bash
tailscale status
tailscale ssh <node-name>
tailscale ip -4
```

## ACL Guidance

- Place the control plane under a dedicated tag such as `tag:control-plane`
- Allow SSH only from trusted operator identities or a smaller admin tag
- Allow HTTP access to the Mac mini tailnet IP only if you intentionally enable direct tailnet HTTP
- Deny broad subnet style access unless there is a documented need

## Tag Guidance

- `tag:control-plane` for the Mac mini running this repo
- `tag:operator` for trusted admin workstations
- `tag:service` only if service-to-service tailnet access is later required

## Subnet Router Concept

Use a subnet router only if a private LAN segment must be bridged into the tailnet. This repo does not depend on subnet routing for v1 green. If introduced later:

- advertise only the required subnets
- document the route owner and approval path
- keep the control plane itself bound to the host tailnet IP, not the routed LAN
