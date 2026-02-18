# Create And Share Skills + Mods

## Skills

### Create

1. Create a skill folder.
2. Add `SKILL.md` with clear instructions and metadata.
3. Optionally add helper scripts.

Example:

```text
my-skill/
  SKILL.md
  scripts/
    run.sh
```

### Share

1. Push the skill folder/repo to git.
2. Share the repository URL.

### Import In CodexChat

1. Open `Skills & Mods`.
2. Go to `Skills`.
3. Click `New skill`.
4. Paste repository URL and install.
5. Enable for the target project.

## Mods

### Create

1. Open `Skills & Mods`.
2. Go to `Mods`.
3. Click `Create Sample` in Global or Project section.
4. Edit generated `ui.mod.json`.

Mod roots:

- Global: `~/CodexChat/global/mods`
- Project: `<project>/mods`

Example:

```text
my-mod/
  ui.mod.json
```

### Share

1. Push mod directory/repo to git.
2. Share the URL.
3. Other users clone into global or project mod root.
4. Select mod in CodexChat picker.

## Suggested Catalog Strategy

- Keep this main repo focused on product code and docs.
- Maintain an external community catalog repo with links to user-owned skill/mod repos.
- Let creators own release cadence in their own repos.

## Related Docs

- `MODS.md`
- `CONTRIBUTING.md`
- `ARCHITECTURE_CONTRACT.md`
