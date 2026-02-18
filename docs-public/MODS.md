# UI Mods

CodexChat supports UI mods that can:

- override design tokens (palette, typography, spacing, radius, materials, bubbles)
- register extension hooks
- register scheduled automations
- expose an optional right-side inspector slot

## Mod Roots

- Global mods: `~/CodexChat/global/mods`
- Project mods: `<project>/mods`

## Precedence

`defaults < global mod < project mod`

## Mod Structure

Each mod is a directory containing `ui.mod.json`:

```text
MyMod/
  ui.mod.json
```

CodexChat discovers mods by scanning immediate subdirectories of each mod root.

## Schema (`ui.mod.json`)

Top-level fields:

- `schemaVersion` (int): `1` (theme-only) or `2` (theme + extensions)
- `manifest` (object): `id`, `name`, `version`, optional metadata fields
- `theme` (object): token overrides
- `darkTheme` (optional object): dark-mode token overrides
- `hooks` (schema v2, optional array): event handlers
- `automations` (schema v2, optional array): cron-based automation handlers
- `uiSlots` (schema v2, optional object): optional inspector slot contract
- `future` (optional object): reserved for future surfaces

Theme override groups (all optional):

- `typography`: `titleSize`, `bodySize`, `captionSize`
- `spacing`: `xSmall`, `small`, `medium`, `large`
- `radius`: `small`, `medium`, `large`
- `palette`: `accentHex`, `backgroundHex`, `panelHex`
- `materials`: `panelMaterial`, `cardMaterial` (`ultraThin|thin|regular|thick|ultraThick`)
- `bubbles`: `style`, `userBackgroundHex`, `assistantBackgroundHex` (`plain|glass|solid`)
- `iconography`: `style` (currently `sf-symbols`)

## System Appearance Behavior

- Without a selected mod, CodexChat uses system-aware defaults.
- In dark mode, if mod only defines `theme` and omits `darkTheme`, CodexChat keeps system dark colors and applies non-color tokens.
- If `darkTheme` is present, those dark values are applied.

## Hex Color Support

Accepted formats:

- `#RGB`
- `#RRGGBB`
- `#AARRGGBB` (alpha first)

## Hot Reload

CodexChat watches global and active project mod roots and refreshes mod lists when files change.

## Extension Compatibility

- `schemaVersion: 1` mods continue to work unchanged.
- `schemaVersion: 2` enables `hooks`, `automations`, and `uiSlots`.
- If v2 extension sections are malformed, CodexChat still loads the theme and disables extension sections for that mod.
