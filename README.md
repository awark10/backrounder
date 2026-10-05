# Backrounder

A 3ds Max 2022 plugin that shows the **Knowledge Hub** (kh-physicl.com) backplate library as a
browsable gallery inside Max. Sign in with your Hub account, pick a backdrop from the thumbnail
grid, click **IMPORT SELECTED**, and it's downloaded, merged into the current scene, and its
textures are copied and relinked as the scene's own files.

Technical overview of the project: **[Claude Artifact](https://claude.ai/artifact/7HpBkgYBp7xiVArVW1Tpkq)**
(copy also in [`docs/overview/`](docs/overview/); describes v1.0)

## Structure

| File | Role |
|---|---|
| `Background_Importer.mcr` | macroScript (category `Physicl`, "BG Importer") — loads the two files below and opens the dialog |
| `KH_Client.ms` | Knowledge Hub client — login, session cookie, card list, Drive downloads, cache, JSON reader |
| `Backrounder_UI.ms` | Login dialog, gallery dialog, import (merge + texture copy & relink) |
| `Run_Background_Importer.ms` | Installer — copies the three files into `userMacros`, reloads the macro live |
| `docs/` | Copy of the v1.0 technical overview page |

`Previews/` and the v1.0 local library (`Background_example.max` + textures) are no longer used.

## How it works

- **Login:** `POST /api/auth/login` with email and password; the Hub answers with a Supabase
  session cookie. With "Remember me" the cookie is saved to `Backrounder_cache\session.dat`,
  encrypted per Windows user (DPAPI). The password is never stored.
- **Library:** `GET /api/library/cards?folderId=…` (folder "Exterior scene Backplates") returns the
  cards as JSON; only `published` cards are shown. An expired session shows the login dialog again.
- **Thumbnails:** Drive's server-side thumbnail (`drive.google.com/thumbnail?id=…&sz=w320`, ~60 KB)
  instead of the full preview (up to 100 MB), cached in `Backrounder_cache\thumbs`.
- **Import:** requires a saved scene. Downloads the card's zip from Drive into
  `Backrounder_cache\packages`, unpacks it, merges the objects named after the background (or the
  whole file), then copies every bitmap they use into `<scene folder>\textures\` as
  `<sceneName>-<original name>` and relinks the maps. Cache file names include the Drive id, so a
  file replaced on the Hub is fetched again.

## Installation

Unzip the package and run `Run_Background_Importer.ms` via Scripting → Run Script. Then
Customize → Customize User Interface → Toolbars → category `Physicl` → drag "BG Importer" to a
toolbar. A Knowledge Hub account is required.

## Version

v2.0 — Knowledge Hub login and library; v1.0 used a bundled local library.
