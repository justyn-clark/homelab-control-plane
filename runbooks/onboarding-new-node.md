# Onboarding A New Node

## Goal

Join a new machine to the tailnet and verify it can reach the control plane services.

## Steps

1. Install Tailscale on the new machine
2. Join the node to the correct tailnet
3. Confirm ACLs allow access to the control plane tailnet IP
4. Resolve the target Mac mini tailnet IP with `tailscale ip -4 <node-name>` or use MagicDNS if configured
5. Test the ingress endpoints with `curl --resolve`

Example:

```bash
CONTROL_PLANE_IP="$(tailscale ip -4 <mac-mini-name> | head -n 1)"
curl -I --resolve auth.internal:80:${CONTROL_PLANE_IP} http://auth.internal/
curl -I --resolve grafana.internal:80:${CONTROL_PLANE_IP} http://grafana.internal/
curl -I --resolve prom.internal:80:${CONTROL_PLANE_IP} http://prom.internal/
```

## Expected Results

- `auth.internal` responds with `200`
- Protected service routes return `302` before login
- Access succeeds only from approved tailnet identities

