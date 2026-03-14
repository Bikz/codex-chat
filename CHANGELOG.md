# Changelog

All notable changes to this project will be documented in this file.

The format is inspired by Keep a Changelog and uses repository tags for version
names.

## [Unreleased]

No curated changes yet.

## [0.0.10]

### Added

- Production verification tooling for remote control, including a browser-based
  reliability harness, deployment verification, and post-deploy relay
  monitoring scripts for release validation.
- Expanded relay integration coverage for rotated-token restart recovery and
  cross-pod remote-control behavior.

### Changed

- Relay auth and session handling now expose clearer websocket auth failure
  reasons, durably rotate mobile websocket tokens, and keep fresh pair-token
  state synchronized across pods.
- Remote control reconnect flows on desktop and the PWA were tightened to
  validate saved session state more aggressively and recover with fresher remote
  credentials.
- Release artifacts now emit portable `.sha256` files that reference the DMG
  filename instead of a local build path.

### Fixed

- Cross-pod delivery ordering, desktop presence synchronization before mobile
  auth, and stale websocket auth rejection handling in the Rust relay.
- Reconnect bugs that could reuse stale saved remote-control sessions or lose
  rotated-token state after pod restarts.
- Remote-control release and deployment docs so the published operational flow
  matches the shipped tooling.

## [0.0.9]

### Added

- Relay hardening and Rust service refactor work, including stricter clippy
  enforcement, split transport/service modules, signed cross-instance bus
  envelopes, replay-window enforcement, and protocol property tests.
- Runtime request protocol versioning across desktop, relay, remote-control
  surfaces, and `CodexKit`, with schema v2 handling and typed runtime contract
  support.
- Shared Codex home alignment, including one-time import of existing Codex
  history, shared login recovery, startup self-healing for legacy skill paths,
  and migration documentation.

### Changed

- Remote control now uses stable command IDs end-to-end, tighter approval and
  ack handling, background automation scheduling via the shared worker contract,
  and stronger stale-job reconciliation and trust checks for mods, skills, and
  extensions.
- The macOS app UI was polished for live workstreams, transcript activity,
  queued follow-ups, runtime issue presentation, filter/send controls, and
  active transcript auto-follow behavior.
- Remote Control PWA mobile surfaces were refreshed and package quality checks
  were stabilized.

### Fixed

- Relay and remote-control compatibility fixes for schema-versioned auth and
  management endpoints, runtime request responses, remote ack replay scoping,
  partial harness writes, and load-harness pair-request handling.
- Setup and startup fixes for shared Codex login recovery, runtime history
  import retries, legacy managed home pruning, and remote sends isolated from
  local drafts.
- Public launch/support/security guidance and release/remote-control docs were
  tightened to match the shipped behavior.

## [0.0.8] and earlier

Historical releases before the current public changelog were published without a
curated changelog file. Use GitHub Releases and `git tag` history for earlier
details.
