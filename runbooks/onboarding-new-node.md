# Onboarding A New Node

## Goal

Join a new machine to the tailnet and verify it can reach the control plane services.

## Steps

1. Install Tailscale on the new machine
2. Join the node to the correct tailnet
3. Confirm ACLs allow access to the control plane tailnet IP
4. Reach the Mac mini with Tailscale SSH or another approved Tailscale operator path
5. Test the ingress endpoints locally on the Mac mini by resolving them to `127.0.0.1`

Example:

```bash
tailscale ssh <mac-mini-name>
curl -I --resolve auth.internal:80:127.0.0.1 http://auth.internal/
curl -I --resolve grafana.internal:80:127.0.0.1 http://grafana.internal/
curl -I --resolve prom.internal:80:127.0.0.1 http://prom.internal/
```

## Expected Results

- `auth.internal` responds with `200`
- Protected service routes return `302` before login
- Access succeeds only from approved tailnet identities
- If direct tailnet HTTP is later enabled, update this runbook and test against the configured tailnet bind IP
