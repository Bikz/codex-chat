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
- optional: `future` (object): reserved for future UI surfaces (no third pane is shipped today)

Theme overrides (all optional):

- `typography`: `titleSize`, `bodySize`, `captionSize`
- `spacing`: `xSmall`, `small`, `medium`, `large`
- `radius`: `small`, `medium`, `large`
- `palette`: `accentHex`, `backgroundHex`, `panelHex`
- `materials`: `panelMaterial`, `cardMaterial` (values: `ultraThin|thin|regular|thick|ultraThick`)
- `bubbles`: `style`, `userBackgroundHex`, `assistantBackgroundHex` (styles: `plain|glass|solid`)
- `iconography`: `style` (currently: `sf-symbols`)

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
  }
}
```

## Hot Reload

CodexChat watches the global and active project mod roots and refreshes the available mods when files change.

