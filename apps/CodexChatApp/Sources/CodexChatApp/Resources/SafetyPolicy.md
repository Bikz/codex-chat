# CodexChat Safety Policy

CodexChat applies project-level safety settings to Codex app-server turns.

## Recommended Defaults

- Untrusted projects: `read-only` sandbox + `untrusted` approvals.
- Trusted projects: `workspace-write` sandbox + `on-request` approvals.
- Network access is off by default for `workspace-write`.
- Web search defaults to `cached`.

## Riskier Modes

- `danger-full-access` removes sandbox protections.
- `approval_policy = never` allows autonomous actions without approval pauses.

Use riskier modes only for projects and commands you fully trust.

## Approval Decisions

- **Approve once**: one request is approved.
- **Approve for session**: repeated requests of the same type can proceed in the current session.
- **Decline**: request is rejected.

Always review command summaries and file changes before approving.
