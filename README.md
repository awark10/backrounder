# Backrounder

A 3ds Max plugin that turns a single library scene into a browsable gallery of backdrops.
Pick one from a thumbnail grid, click **IMPORT SELECTED**, and it's merged into the current
scene with its textures copied and relinked as the scene's own files — no shared folder left
dangling behind it.

Technical overview of the project: **[Claude Artifact](https://claude.ai/artifact/7HpBkgYBp7xiVArVW1Tpkq)**
(copy also in [`docs/overview/`](docs/overview/))

## Structure

| File | Role |
|---|---|
| `Background_Importer.mcr` | Main macroScript — the gallery dialog, merge import, texture copy & relink |
| `Run_Background_Importer.ms` | Installer — copies everything into `userMacros`, reloads the macro live |
| `Previews/` | 28 gallery thumbnails (160×90), one per backdrop |
| `docs/` | Copy of the technical overview page |

Not tracked here (too large for git, ~450MB): `Background_example.max` — the actual library
scene, one named object per backdrop — and the 56 source textures (`Background_NN_<suffix>.png`).
These ship inside the distributed `.zip` package instead.

## Key idea

The library and its own catalog are the same file: `getMAXFileObjectNames` lists the named
objects inside `Background_example.max` without opening it, filtered to `Background*`. Adding a
backdrop means adding an object to that one file — nothing else to register. On import, textures
are copied out of the plugin's folder into the scene's own `Textures\`, renamed to
`<sceneName>-Background<suffix>`, and the material is relinked to point at the local copies —
so the scene stops depending on the plugin once it's saved.

## Installation

Drag `Backrounder_v1.0.zip` into the Max viewport, or run `Run_Background_Importer.ms` directly
via Scripting → Run Script. Installs flat into `userMacros`; category `"Nfinite"` (not yet
renamed to `Physicl` in the code).

## Version

v1.0.
