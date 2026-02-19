## Summary

Describe the change and why it exists.

## Testing

- [ ] `make quick`
- [ ] `pnpm -s run check` (if applicable)
- [ ] `make oss-smoke`
- [ ] Host app builds in canonical path:
  - [ ] `xcodebuild -project apps/CodexChatHost/CodexChatHost.xcodeproj -scheme CodexChatHost -configuration Debug -destination "generic/platform=macOS" CODE_SIGNING_ALLOWED=NO build`

## UI / Product Guardrails

- [ ] Two-pane default UI preserved (no persistent third pane)
- [ ] Empty/loading/error states considered
- [ ] Accessibility basics considered (keyboard, VoiceOver labels, contrast)

## Architecture / Docs

- [ ] Host/CLI/shared boundaries preserved (`docs-public/ARCHITECTURE_CONTRACT.md`)
- [ ] Docs updated if architecture, run path, or release behavior changed

## Notes

Anything reviewers should pay attention to (risk, migration, follow-ups).
