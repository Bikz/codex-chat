# Remote Control Relay: GKE Deployment

This document describes the production baseline for deploying the Rust relay on GKE with shared Redis + NATS.

## Architecture

- Stateless relay pods on GKE (`apps/RemoteControlRelayRust`)
- Static PWA pods on GKE (`apps/RemoteControlPWA`)
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
- `PWA Deployment`
- `PWA Service`
- `Ingress`
- `BackendConfig` (Cloud Armor policy attachment)
- `PWA BackendConfig` (Cloud Armor attachment + health check on port 8080)
- `FrontendConfig` (HTTPS redirect)
- `ManagedCertificate`
- `HorizontalPodAutoscaler`
- `PodDisruptionBudget`
- `ConfigMap` + secret template

## Required Environment

Set these secret values before deploy:

- `PUBLIC_BASE_URL` (PWA route, typically `https://<domain>/rc`)
- `ALLOWED_ORIGINS`
- `REDIS_URL`
- `NATS_URL`

Set these non-secret ingress/platform values before deploy:

- ingress host + certificate domains (base uses `remote.codexchat.app`, staging/canary overlays patch this)
- Cloud Armor policy name in `infra/remote-control-relay/gke/base/backendconfig.yaml`

Defaults and non-secret runtime tunables are in:

- `infra/remote-control-relay/gke/base/configmap.yaml`

## Deploy

1. Build and push images

```bash
cd /path/to/repo
docker build -f apps/RemoteControlRelayRust/Dockerfile -t gcr.io/PROJECT_ID/remote-control-relay-rust:TAG .
docker push gcr.io/PROJECT_ID/remote-control-relay-rust:TAG

docker build -f apps/RemoteControlPWA/Dockerfile -t gcr.io/PROJECT_ID/remote-control-pwa:TAG .
docker push gcr.io/PROJECT_ID/remote-control-pwa:TAG
```

2. Update image tags in:

- `infra/remote-control-relay/gke/base/deployment.yaml`
- `infra/remote-control-relay/gke/base/pwa-deployment.yaml`

3. Review ingress domain + Cloud Armor policy placeholders

- `infra/remote-control-relay/gke/base/ingress.yaml`
- `infra/remote-control-relay/gke/base/managedcertificate.yaml`
- `infra/remote-control-relay/gke/base/backendconfig.yaml`

4. Configure secrets

```bash
cp infra/remote-control-relay/gke/secret-template.yaml /tmp/relay-secrets.yaml
# edit /tmp/relay-secrets.yaml with real values
```

`secret-template.yaml` is a reference file only and is intentionally not included in `kustomization.yaml`.

5. Apply manifests

```bash
kubectl apply -f /tmp/relay-secrets.yaml
kubectl apply -k infra/remote-control-relay/gke
```

6. Apply baseline Cloud Armor throttles

```bash
infra/remote-control-relay/gke/scripts/harden-cloud-armor.sh PROJECT_ID
```

This configures default rate limits for `/pair*` and `/ws*` paths.

Optional preflight validation:

```bash
make remote-control-gke-validate
```

If no kube context is configured, the validator still renders and structure-checks manifests locally and skips cluster API discovery.

Validate an overlay:

```bash
RELAY_GKE_KUSTOMIZE_DIR=infra/remote-control-relay/gke/overlays/staging make remote-control-gke-validate
```

7. Verify rollout

```bash
kubectl -n codexchat-remote-control rollout status deploy/remote-control-relay
kubectl -n codexchat-remote-control rollout status deploy/remote-control-pwa
kubectl -n codexchat-remote-control get pods,svc,hpa,pdb
```

8. GA DNS + certificate gate

- Point DNS `A` record for `remote.codexchat.app` to the ingress IP.
- Wait for managed certificate status to become `Active`:

```bash
kubectl -n codexchat-remote-control get managedcertificate remote-control-relay-cert
```

- Validate externally:

```bash
curl -i https://remote.codexchat.app/healthz
curl -i https://remote.codexchat.app/rc
```

Canary-first rollout example:

```bash
kubectl apply -f /tmp/relay-secrets.yaml
kubectl apply -k infra/remote-control-relay/gke/overlays/prod-canary
# observe metrics and error budgets
kubectl apply -k infra/remote-control-relay/gke
```

Local stage-gate (load + soak + manifest preflight):

```bash
make remote-control-stage-gate
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
- Managed cert is `Active` on the GA hostname and public `/healthz` + `/rc` checks pass.

Operator runbook: `docs-public/REMOTE_CONTROL_RELAY_RUNBOOK.md`.
