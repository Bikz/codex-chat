# Extensions API (Experimental)

This page is a compatibility landing page.

The canonical builder guide for extension authoring is:

- [`MODS_SHARING.md`](./MODS_SHARING.md)

Use these sections in the canonical guide:

- Schema (`schemaVersion: 1`): [`MODS_SHARING.md#uimodjson-schema`](./MODS_SHARING.md#uimodjson-schema)
- Package manifest (`codex.mod.json`): [`EXTENSIONS_SPEC_VNEXT.md`](./EXTENSIONS_SPEC_VNEXT.md)
- Hook events: [`MODS_SHARING.md#hook-events`](./MODS_SHARING.md#hook-events)
- Worker protocol: [`MODS_SHARING.md#worker-protocol`](./MODS_SHARING.md#worker-protocol)
- Permissions and safety: [`MODS_SHARING.md#permissions-and-safety`](./MODS_SHARING.md#permissions-and-safety)
- Mods bar slot contract: [`MODS_SHARING.md#mods-bar-contract`](./MODS_SHARING.md#mods-bar-contract)
- Packaging/sharing/install: [`MODS_SHARING.md#install-and-sharing`](./MODS_SHARING.md#install-and-sharing)
- Quickstart: [`EXTENSIONS_QUICKSTART.md`](./EXTENSIONS_QUICKSTART.md)
- Current-state audit: [`EXTENSIONS_CURRENT_STATE_AUDIT.md`](./EXTENSIONS_CURRENT_STATE_AUDIT.md)
- ADR: [`ADR-EXTENSIONS-PACKAGE-MANIFEST.md`](./ADR-EXTENSIONS-PACKAGE-MANIFEST.md)
- Breaking-change ADR: [`ADR-MODS-SCHEMA-RESET-V1.md`](./ADR-MODS-SCHEMA-RESET-V1.md)
- Mods bar actions + GitHub subdir install ADR: [`ADR-MODS-BAR-ACTIONS-AND-GITHUB-SUBDIR-INSTALL.md`](./ADR-MODS-BAR-ACTIONS-AND-GITHUB-SUBDIR-INSTALL.md)

Stability:

- Extension APIs are experimental and may change across minor versions.
- Distribution channel for this cycle is GitHub URLs + local paths only (no hosted catalog onboarding).
- Current Mods bar UX contract uses global persisted UI state across chats/new drafts, with docked `rail`/`peek`/`expanded` modes (see `MODS_SHARING.md` and `EXTENSIONS_QUICKSTART.md`).
