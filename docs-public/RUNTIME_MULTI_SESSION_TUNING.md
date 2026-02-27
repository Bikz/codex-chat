# Runtime Multi-Session Tuning

This document describes runtime knobs and diagnostics for high-concurrency Codex Chat workloads (for example, ~20 active sessions across many threads/projects).

## Environment Variables

### Global turn concurrency

- `CODEXCHAT_MAX_PARALLEL_TURNS`
  - Global hard ceiling for concurrent turns.
  - Existing setting; still enforced by `TurnConcurrencyScheduler`.

### Runtime pool sizing

- `CODEXCHAT_RUNTIME_POOL_SIZE`
  - Runtime worker process count.
  - Sharding remains enabled with a minimum of `2`.
  - Default is hardware-aware (Apple Silicon performance-core profile), typically:
    - up to `8` workers on 8 P-core machines
    - up to `11` workers on 12 P-core machines
    - bounded to `12` workers by default (override up to `16` via env var)

### Per-worker backpressure

- `CODEXCHAT_MAX_PARALLEL_TURNS_PER_WORKER`
  - Maximum in-flight turns per runtime worker process.
  - Default: hardware-aware autoscaling (`2...5`) based on core profile.
  - Enforced by `WorkerTurnScheduler` in `RuntimePool`.

### Adaptive concurrency

- `CODEXCHAT_ADAPTIVE_CONCURRENCY_BASE_PER_WORKER`
  - Baseline adaptive limit multiplier.
  - Default: hardware-aware autoscaling (`3...5`) (baseline = `workerCount * basePerWorker`).

- `CODEXCHAT_ADAPTIVE_CONCURRENCY_TTFT_P95_BUDGET_MS`
  - TTFT p95 pressure budget used by adaptive control.
  - Default: `2500`.

- `CODEXCHAT_ADAPTIVE_CONCURRENCY_BACKOFF_MULTIPLIER`
  - Backoff aggressiveness multiplier when under pressure.
  - Default: `1.0`.

### Turn-start disk I/O

- `CODEXCHAT_TURN_START_IO_MAX_CONCURRENCY`
  - Maximum concurrent checkpoint/snapshot jobs at turn start.
  - Default: hardware-aware autoscaling (`3...8`) based on core profile.
  - Higher values improve burst throughput; lower values reduce disk pressure.

## Runtime Signals Used By Adaptive Control

Adaptive concurrency now incorporates:

- queued turn pressure
- runtime worker queue pressure
- active turns
- degraded workers and worker failures
- thermal pressure
- rolling TTFT p95 (from `RuntimePerformanceSignals`)
- runtime event backlog pressure (from `RuntimeEventDispatchBridge`)

Pressure mode ramps down quickly and ramps up slowly to avoid oversubscription.

## Diagnostics Surface

Diagnostics now includes:

- adaptive turn limit
- rolling TTFT p95
- total queued turns
- per-worker in-flight turns and queue depth

## Load Harness Verification

Use the runtime load harness tests for regression checks:

```bash
cd apps/CodexChatApp
swift test --filter 'RuntimePoolLoadHarnessTests'
```

Real-runtime smoke remains opt-in:

```bash
CODEXCHAT_RUNTIME_LOAD_HARNESS_REAL=1 swift test --filter 'RuntimePoolLoadHarnessTests/testRealRuntimeLoadSmokeWhenEnabled'
```
