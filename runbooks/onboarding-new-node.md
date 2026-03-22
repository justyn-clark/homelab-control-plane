# Onboarding Another Tailnet Client

## Goal

Join another machine to the tailnet and verify it can reach this single control host. This runbook is about operator access from another device, not provisioning another control-plane node.

## Steps

1. Install Tailscale on the client machine
2. Join the client to the correct tailnet
3. Confirm ACLs allow access to the Mac mini or its tailnet IP
4. If ingress is still localhost-bound, reach the Mac mini with Tailscale SSH or another approved operator path and test there
5. If direct tailnet HTTP was explicitly enabled by setting `TAILNET_BIND_IP` to the host tailnet IP, test against that configured address from the client

Example:

```bash
tailscale ssh <mac-mini-name>
curl -I --resolve auth.internal:80:127.0.0.1 http://auth.internal/api/health
curl -I --resolve grafana.internal:80:127.0.0.1 http://grafana.internal/
curl -I --resolve prom.internal:80:127.0.0.1 http://prom.internal/
```

## Expected Results

- `auth.internal/api/health` responds with `200`
- Protected service routes return `302` with a redirect toward `auth.internal`
- Access succeeds only from approved tailnet identities
- This is an HTTP smoke check only, not proof of a complete browser login flow
