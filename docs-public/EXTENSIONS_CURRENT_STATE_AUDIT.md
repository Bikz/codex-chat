# Extensions Current-State Audit (2026-02)

## Scope

Audit target: CodexChat extension/mod architecture across runtime, install flows, persistence, and docs.

Primary code/docs reviewed:

- `packages/CodexMods/Sources/CodexMods/UIModDefinition.swift`
- `packages/CodexMods/Sources/CodexMods/UIModDiscoveryService.swift`
- `packages/CodexExtensions/Sources/CodexExtensions/ExtensionWorkerRunner.swift`
- `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Extensions.swift`
- `apps/CodexChatApp/Sources/CodexChatApp/AppModel+RuntimeEvents.swift`
- `apps/CodexChatApp/Sources/CodexChatApp/AppModel+ModsSurface.swift`
- `apps/CodexChatApp/Sources/CodexChatApp/ModViews.swift`
- `packages/CodexChatCore/Sources/CodexChatCore/Models.swift`
- `packages/CodexChatInfra/Sources/CodexChatInfra/MetadataDatabase.swift`
- `docs-public/MODS_SHARING.md`
- `docs-public/ADR-EXTENSIONS-RUNTIME.md`

## Findings (Ordered By Severity/Risk)

1. High: Packaging and runtime metadata were split with no explicit package-level contract.
- Runtime config lived in `ui.mod.json` (`UIModDefinition`) but install/distribution concerns (entrypoint, compatibility, integrity declaration) were implicit.
- Result: a mod could be loadable but not safely distributable/reviewable.

2. High: Install flow logic was app-layer coupled and hard to reuse.
- URL/path staging, git clone, folder resolution, and copy behavior were embedded in `AppModel+ModsSurface`.
- No reusable installer primitive for future CLI/website flows.

3. High: Integrity verification was partial.
- `ui.mod.json` checksum support existed in `UIModManifest.checksum`, but package-level integrity and explicit entrypoint verification were missing.
- Trust gate in UI was host-based (`github.com/gitlab.com/bitbucket.org`) rather than manifest/declaration based.

4. Medium: Permission gating existed at execution time but not install declaration time.
- Runtime prompts are implemented in `AppModel+Extensions.ensurePermissions`.
- Developers lacked a packaging-time way to declare “expected permissions” and catch drift before users run the extension.

5. Medium: Hook/event contract is runtime-coupled and not extension-SDK friendly.
- Events are emitted from specific app paths in `AppModel+RuntimeEvents` and `AppModel+RuntimePersistence`.
- No explicit compatibility matrix for “event added/changed/removed” behavior.

6. Medium: No explicit extension lifecycle API for update/disable/rollback.
- Metadata tables exist (`extension_installs`, `extension_permissions`, `extension_hook_state`, `extension_automation_state`), but install/update/rollback UX is incomplete.
- Enable/disable is tied to selected mod per scope; uninstall/update are not first-class flows.

7. Medium: Catalog architecture exists but is effectively off by default.
- `RemoteJSONModCatalogProvider` exists in `CodexMods`, but `AppModel` defaults to `EmptyModCatalogProvider`.
- This cycle intentionally keeps distribution on GitHub URLs + local paths only.

8. Low: Sample generation was helpful but not production-shaped.
- Sample generation centered on `ui.mod.json` and did not establish a package-level manifest contract for distribution.

## Developer UX Assessment

### Create a mod (today)
- Good: Fast local entry via `Create Sample` and immediate discovery from mod folders.
- Friction: No package manifest standard for compatibility/integrity/declared permissions.

### Test locally
- Good: Hot reload and runtime hook execution via subprocess.
- Friction: Limited “preflight” validation for package metadata before install/run.

### Package/publish
- Good: “Commit folder to git and share URL” works.
- Friction: No stable package schema for registries; no explicit declaration for entrypoint/integrity beyond ad hoc fields.

### Install/update/uninstall
- Good: Install from URL/path and auto-enable is fast.
- Friction: Update/uninstall/rollback are not one coherent workflow.

## Hidden Coupling / Inconsistencies

- `ui.mod.json` simultaneously acted as runtime config and distribution identity.
- Install behavior depended on app-layer code (`AppModel+ModsSurface`) rather than reusable package/service APIs.
- Permission intent (what extension expects) and permission grants (what user allows) were stored in different places with no package-level declaration check.

## Fit For Requested Extension Ideas

1. Personal Notes (per chat, right modsBar):
- Feasible today using hook output + artifact writes + right modsBar slot.

2. Thread Summary (one-line after each turn, right modsBar):
- Feasible today with `turn.completed` hook and modsBar markdown output.

3. Prompt Book / Prompt Bar (cross-chat, project-independent prompt launcher):
- Partially feasible.
- Gap: current modsBar state is thread-scoped (`extensionModsBarByThreadID`) and does not provide first-class global extension state or cross-chat persistent UI behavior.

## Summary

CodexChat has a solid extension runtime foundation (hooks, automations, modsBar slot, permission prompts), but distribution/install ergonomics were missing a package-native contract. The key next step is a package manifest + reusable installer + GitHub/local-first install pipeline, while preserving the two-pane IA and runtime safety model.

## Prioritized Roadmap

### Quick Wins (Now/Next)

1. Ship `codex.mod.json` validation + reusable install primitive (implemented in this slice).
2. Require `codex.mod.json` at install and return explicit migration errors for missing/legacy packages (implemented in this slice).
3. Improve sample package output so generated starter is distribution-ready (implemented in this slice).

### Medium-Term

1. Add first-class update/reinstall/disable/uninstall actions in Mods UI.
2. Add rollback-safe update path (staging + atomic swap + recovery marker).
3. Add pre-install permission review UI that writes initial grant/deny choices.
4. Keep remote source policy GitHub-only while tightening install diagnostics and recovery.

### Long-Term

1. Signed registry metadata + signature verification (publisher identity and tamper evidence).
2. Expanded capability APIs for slash-command packs and richer UI cards/actions.
3. Global extension state APIs to support cross-chat features (for example Prompt Book) without violating two-pane IA.
