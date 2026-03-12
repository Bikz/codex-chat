# Security Policy

## Supported Versions

Security fixes are prioritized for:

- the latest tagged GitHub release
- the `main` branch for contributor reproductions and pending fixes

Older tags may be asked to reproduce on the latest release or `main` before triage continues.

CodexChat's current runtime compatibility window is:

- Validated: `codex 0.114.x`
- Grace: `codex 0.113.x`
- Outside that window: startup is allowed in degraded mode, but unsupported protocol features may be gated

## Reporting a Vulnerability

Please do not open public GitHub issues, pull requests, or discussions for security vulnerabilities.

This repository accepts private reports through GitHub Private Vulnerability Reporting:

- [Report a vulnerability](https://github.com/Bikz/codex-chat/security/advisories/new)

Include, when possible:

- affected CodexChat version, commit SHA, or release tag
- macOS version and hardware architecture
- local `codex --version`
- reproduction steps or proof-of-concept
- impact assessment and any suggested mitigations

Triage targets:

- initial acknowledgement within 3 business days
- status updates at least every 7 business days while a fix is in progress

Please keep details private until a fix is available and the maintainers coordinate disclosure timing.

## Scope And Safe Handling

- Test only against systems and data you own or are explicitly authorized to assess.
- Avoid destructive tests, denial-of-service attempts, or social-engineering attacks.
- Never include secrets, tokens, or private user content in reports unless strictly necessary.

## Non-Security Reports

For install help, runtime compatibility questions, or ordinary bug reports, use [SUPPORT.md](SUPPORT.md).
