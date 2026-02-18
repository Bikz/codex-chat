# UI Mods

CodexChat supports UI mods that override design tokens (palette, typography, spacing, radius, materials, bubbles).

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

## Schema (`ui.mod.json`, v1)

Top-level fields:

- `schemaVersion` (int): currently `1`
- `manifest` (object): `id`, `name`, `version`, optional metadata fields
- `theme` (object): token overrides
- `darkTheme` (optional object): dark-mode token overrides
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
