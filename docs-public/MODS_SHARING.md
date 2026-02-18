# Create And Share Skills + Mods

This guide explains how users can create and share custom Skills and UI Mods for CodexChat.

## Skills

### Create a skill

1. Create a new folder for your skill repository.
2. Add a `SKILL.md` file with frontmatter (`name`, `description`) and clear instructions.
3. Optionally add a `scripts/` directory for helper automation.

Example structure:

```text
my-skill/
  SKILL.md
  scripts/
    run.sh
```

### Share a skill

1. Commit and push the skill folder to any git repository.
2. Share the repository URL.

### Import a skill in CodexChat

1. Open `Skills & Mods` -> `Skills`.
2. Click `New skill`.
3. Paste the git repository URL and install.
4. Enable the installed skill for your project.

Notes:

- CodexChat supports git clone installs and optional `npx skills add` installs when Node tooling is available.
- Trusted-host checks are applied in the install flow.

## Mods

### Create a mod

1. Open `Skills & Mods` -> `Mods`.
2. Click `Create Sample` in either `Global Mod` or `Project Mod`.
3. Edit the generated `ui.mod.json`.

Mod roots:

- Global mods: `~/Library/Application Support/CodexChat/Mods/Global`
- Project mods: `<project>/mods`

Example structure:

```text
my-mod/
  ui.mod.json
```

### Share a mod

1. Commit and push the mod directory to any git repository.
2. Share that repository URL.
3. Other users can clone the mod directory into either global mods or project mods.
4. In CodexChat, select the mod from the `Global Mod` or `Project Mod` picker.

## Suggested repo strategy

- Keep this main `codexchat` repo focused on product code + docs.
- Optionally create a separate community catalog repo with metadata and links to user-owned skill/mod repos.
- Allow import from external repos so creators keep ownership and release cadence.

## Related docs

- `MODS.md`: UI mod schema, precedence, and token coverage.
- `CONTRIBUTING.md`: contribution and repo conventions.
