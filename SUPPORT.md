# Support

Use the channel that matches the kind of help you need so reports stay actionable
and private issues stay private.

## Supported Audience

CodexChat currently targets:

- macOS 14+
- Apple Silicon (`arm64`) for the direct-download release path
- a local `codex` CLI install with `codex app-server` available on `PATH`

Current runtime compatibility window:

- Validated: `codex 0.114.x`
- Grace: `codex 0.113.x`
- Outside the window: CodexChat starts in degraded mode and may gate unsupported features

## Where To Go

- Usage questions, install help, or "is this expected?" discussions:
  [GitHub Discussions](https://github.com/Bikz/codex-chat/discussions)
- Confirmed bugs:
  [GitHub Issues](https://github.com/Bikz/codex-chat/issues/new/choose)
- Security vulnerabilities:
  [GitHub Private Vulnerability Reporting](https://github.com/Bikz/codex-chat/security/advisories/new)
- Code of Conduct reports:
  contact the project maintainer privately through the repository owner's GitHub profile at <https://github.com/Bikz>

## Before Filing A Bug

Collect the same signals the maintainers use for triage:

- `swift run CodexChatCLI doctor`
- `swift run CodexChatCLI smoke`
- a deterministic repro fixture or the shortest possible manual repro steps
- whether it reproduces in the canonical `CodexChatHost` app path
- `codex --version`
- the runtime support level shown in Settings or Diagnostics (`validated`, `grace`, or `unsupported`)

## What To Include

For install/runtime issues, include:

- CodexChat version or commit SHA
- macOS version
- Apple Silicon vs Intel hardware
- local `codex --version`
- whether the issue started after a Codex CLI update
- any relevant diagnostics bundle excerpts with secrets redacted

## Triage Expectations

- new issues: first maintainer triage within 3 business days
- new pull requests: first review pass within 3 business days when quick smoke is green
- `needs-repro` issues without follow-up details may be closed after 14 days

## Notes

- Hosted GitHub Actions intentionally runs `make quick` only.
- The full contributor launch gate remains local-first:
  `make prepush-local` followed by `pnpm -s run check`.
