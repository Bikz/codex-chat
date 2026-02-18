# UI Mods

CodexChat supports a simple UI mod system that overrides design tokens (colors, spacing, typography, materials, bubble style).

## Where Mods Live

- Global mods: `~/Library/Application Support/CodexChat/Mods/Global`
- Project mods: `<project>/mods`

## Precedence

Effective theme is computed as:

`defaults < global mod < project mod`

## Mod Structure

Each mod is a directory containing a `ui.mod.json` definition file:

```
MyMod/
  ui.mod.json
```

CodexChat discovers mods by scanning the immediate subdirectories of the global/project mod roots.

## `ui.mod.json` Schema (v1)

Top-level fields:

- `schemaVersion` (int): currently `1`
- `manifest` (object):
  - `id` (string): stable identifier (ex: `com.example.my-mod`)
  - `name` (string)
  - `version` (string)
  - optional: `author`, `license`, `description`, `homepage`, `repository`, `checksum`
- `theme` (object): token overrides
- optional `darkTheme` (object): token overrides used only while system appearance is dark
- optional: `future` (object): reserved for future UI surfaces (no third pane is shipped today)

Theme overrides (all optional):

- `typography`: `titleSize`, `bodySize`, `captionSize`
- `spacing`: `xSmall`, `small`, `medium`, `large`
- `radius`: `small`, `medium`, `large`
- `palette`: `accentHex`, `backgroundHex`, `panelHex`
- `materials`: `panelMaterial`, `cardMaterial` (values: `ultraThin|thin|regular|thick|ultraThick`)
- `bubbles`: `style`, `userBackgroundHex`, `assistantBackgroundHex` (styles: `plain|glass|solid`)
- `iconography`: `style` (currently: `sf-symbols`)

## Tokenized Surface Coverage (Updated February 18, 2026)

- Mod-driven material tokens now style the main card/panel containers across sidebar lists, skills, memory, mods, trust banners, and approval/review sheets.
- CodexChat uses a shared `tokenCard(style:radius:strokeOpacity:)` helper in `packages/CodexChatUI/Sources/CodexChatUI/TokenCard.swift` to keep card styling consistent.
- When adding new rounded containers, prefer token-based `tokenCard(...)` usage over hardcoded `.thinMaterial` / `.regularMaterial` so selected mods propagate correctly.
- The chat composer text input now follows `typography.bodySize` from design tokens.

### System Appearance Defaults And Fallbacks

- With no mod selected, CodexChat uses system-aware defaults in both light and dark mode.
- In dark mode, if a selected mod defines only `theme` and omits `darkTheme`, CodexChat keeps system dark colors and applies only non-color tokens from `theme` (typography, spacing, radius, materials, iconography, bubble style).
- If `darkTheme` is present, its values apply on top of that dark fallback behavior.

Colors accept `#RGB`, `#RRGGBB`, or `#AARRGGBB` (alpha-first) hex.

### Example

```json
{
  "schemaVersion": 1,
  "manifest": {
    "id": "com.example.green-glass",
    "name": "Green Glass",
    "version": "1.0.0",
    "author": "Example"
  },
  "theme": {
    "palette": {
      "accentHex": "#2E7D32",
      "backgroundHex": "#F7F8F7",
      "panelHex": "#FFFFFF"
    },
    "materials": {
      "panelMaterial": "thin",
      "cardMaterial": "regular"
    },
    "bubbles": {
      "style": "glass",
      "userBackgroundHex": "#2E7D32",
      "assistantBackgroundHex": "#FFFFFF"
    }
  },
  "darkTheme": {
    "palette": {
      "accentHex": "#2E7D32",
      "backgroundHex": "#000000",
      "panelHex": "#121212"
    },
    "bubbles": {
      "style": "glass",
      "userBackgroundHex": "#2E7D32",
      "assistantBackgroundHex": "#1C1C1E"
    }
  }
}
```

## Hot Reload

CodexChat watches the global and active project mod roots and refreshes the available mods when files change.
