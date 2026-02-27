# Remote Control Relay Runbook

This runbook covers basic operations for the production Rust relay service.

## Service Scope

- API + websocket relay for remote control sessions
- Session durability via Redis
- Cross-instance routing via NATS
- Kubernetes deployment target: GKE

## Primary Signals

Use `/metricsz` and infrastructure dashboards.

High-signal counters:

- `pairStartFailures`, `pairJoinFailures`, `pairRefreshFailures`
- `wsAuthFailures`
- `outboundSendFailures`
- `slowConsumerDisconnects`

Capacity and pressure:

- `activeWebSockets`
- `pendingJoinWaiters`
- `commandRateLimitBuckets`
- `snapshotRateLimitBuckets`

Edge protection:

- Cloud Armor policy: `remote-control-relay-cloud-armor`
- Pair and websocket path throttle rules are managed by:
  - `infra/remote-control-relay/gke/scripts/harden-cloud-armor.sh`
- Kubernetes network policy baseline:
  - `networkpolicy-default-deny-ingress.yaml`
  - `networkpolicy-allow-relay-ingress.yaml`
  - `networkpolicy-allow-pwa-ingress.yaml`
  - `networkpolicy-allow-nats-ingress.yaml`

Production alert provisioning:

- `infra/remote-control-relay/gke/scripts/setup-monitoring-alerts.sh`
- Optional notification wiring via `ALERT_NOTIFICATION_CHANNELS`.

## SLO Guardrails (initial)

- Pair join success rate: >= 99.5%
- Websocket auth success rate: >= 99.9%
- Backpressure counters near zero under normal load

## Incident Triage

1. Confirm scope
- Check if issue is global or one region.
- Verify relay deployment health (`kubectl get pods,svc,hpa -n codexchat-remote-control`).

2. Check dependency health
- Redis connection and latency.
- NATS connectivity and lag.
- Managed certificate status on the public hostname.

3. Inspect relay counters
- Spike in `wsAuthFailures`: investigate origin config/token rotation/client compatibility.
- Spike in `pairJoinFailures`: inspect desktop connectivity, join token expiry, approval timeouts.
- Spike in `outboundSendFailures` or `slowConsumerDisconnects`: inspect overload/backpressure and client reconnect behavior.

4. Mitigate
- Scale up relay replicas (temporary) and verify HPA behavior.
- Reduce ingress pressure with stricter rate limits if abuse is detected.
- Restart degraded pods only after confirming Redis/NATS are healthy.

## Alert Verification

```bash
PROJECT_ID=<your-project>
infra/remote-control-relay/gke/scripts/setup-monitoring-alerts.sh "${PROJECT_ID}"
gcloud monitoring policies list \
  --project "${PROJECT_ID}" \
  --filter 'display_name~"^Remote Control -"' \
  --format='table(displayName,enabled)'
```

Expected alert set:

- `Remote Control - wsAuthFailures High`
- `Remote Control - pairJoinFailures High`
- `Remote Control - outboundSendFailures High`
- `Remote Control - slowConsumerDisconnects High`
- `Remote Control - Redis Latency High`
- `Remote Control - NATS Health Degraded`

## Rollback Procedure

1. Identify last known good image tag.
2. Roll deployment back:

```bash
kubectl -n codexchat-remote-control rollout undo deploy/remote-control-relay
kubectl -n codexchat-remote-control rollout status deploy/remote-control-relay
```

3. Validate:
- `/healthz` returns `ok`.
- Pair + websocket auth counters recover.
- Load gate smoke (`make remote-control-load-gated`) passes against staging/prod target.

## Failover Drill Checklist

- Kill one zone worth of pods and confirm service continuity.
- Restart relay pods while keeping Redis + NATS up; verify sessions recover deterministically.
- Restart NATS/Redis in isolation and verify reconnect behavior + explicit client recovery path.

## Post-Incident

1. Capture timeline and customer impact window.
2. Record root cause and metric anomalies.
3. Add regression checks:
- relay integration test if protocol/logic issue
- load/soak gate update if performance/reliability issue
4. Update this runbook and GA plan status.

## Common Operator Pitfalls

- If `kubectl apply -f` is used on individual files without a namespace, resources may land in `default`.
- If ingress hostname and secret `PUBLIC_BASE_URL` do not match, QR pairing links can fail.
- If managed cert is `Provisioning`, public HTTPS checks may fail even when pod/ingress backends are healthy.
