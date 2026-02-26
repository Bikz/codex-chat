# Remote Control Relay: GKE Deployment

This document describes the production baseline for deploying the Rust relay on GKE with shared Redis + NATS.

## Architecture

- Stateless relay pods on GKE (`apps/RemoteControlRelayRust`)
- Shared Redis for session/token durability
- Shared NATS for cross-instance relay fanout
- External HTTPS load balancer in front of relay service

Desktop clients keep outbound-only relay connections; no desktop inbound ports are required.

## Manifests

Kubernetes manifests live in:

- `infra/remote-control-relay/gke/`

Overlays:

- `infra/remote-control-relay/gke/overlays/staging`
- `infra/remote-control-relay/gke/overlays/prod-canary`

Resources included:

- `Deployment`
- `Service`
- `HorizontalPodAutoscaler`
- `PodDisruptionBudget`
- `ConfigMap` + secret template

## Required Environment

Set these secret values before deploy:

- `PUBLIC_BASE_URL`
- `ALLOWED_ORIGINS`
- `REDIS_URL`
- `NATS_URL`

Defaults and non-secret runtime tunables are in:

- `infra/remote-control-relay/gke/base/configmap.yaml`

## Deploy

1. Build and push image

```bash
cd apps/RemoteControlRelayRust
docker build -t gcr.io/PROJECT_ID/remote-control-relay-rust:TAG .
docker push gcr.io/PROJECT_ID/remote-control-relay-rust:TAG
```

2. Update image tag in `deployment.yaml`

3. Configure secrets

```bash
cp infra/remote-control-relay/gke/secret-template.yaml /tmp/relay-secrets.yaml
# edit /tmp/relay-secrets.yaml with real values
```

`secret-template.yaml` is a reference file only and is intentionally not included in `kustomization.yaml`.

4. Apply manifests

```bash
kubectl apply -f /tmp/relay-secrets.yaml
kubectl apply -k infra/remote-control-relay/gke
```

Optional preflight validation:

```bash
make remote-control-gke-validate
```

If no kube context is configured, the validator still renders and structure-checks manifests locally and skips cluster API discovery.

Validate an overlay:

```bash
RELAY_GKE_KUSTOMIZE_DIR=infra/remote-control-relay/gke/overlays/staging make remote-control-gke-validate
```

5. Verify rollout

```bash
kubectl -n codexchat-remote-control rollout status deploy/remote-control-relay
kubectl -n codexchat-remote-control get pods,svc,hpa,pdb
```

Canary-first rollout example:

```bash
kubectl apply -f /tmp/relay-secrets.yaml
kubectl apply -k infra/remote-control-relay/gke/overlays/prod-canary
# observe metrics and error budgets
kubectl apply -k infra/remote-control-relay/gke
```

## Operational Notes

- HPA starts at `minReplicas: 3` and scales to `maxReplicas: 60`.
- PDB keeps at least two relay pods available during disruption.
- Readiness/liveness use `/healthz`.
- Monitor `/metricsz` counters for:
  - backpressure (`outboundSendFailures`, `slowConsumerDisconnects`)
  - pairing/auth throughput (`pairStart*`, `pairJoin*`, `pairRefresh*`, `wsAuth*`)

## GA Checklist Tie-In

Before GA, validate:

- Load + soak gates pass against production-like environment.
- Redis + NATS failover drills preserve deterministic reconnect behavior.
- Canary and rollback runbooks are tested in staging.

Operator runbook: `docs-public/REMOTE_CONTROL_RELAY_RUNBOOK.md`.
