# BubbleMap

WoW Forever addon: a square minimap with its own map drawing, and a map window. Part of the Bubble suite
(BubbleQuest, BubbleFonts): no Bubble addon requires another; siblings are optional and reached through
their public API (BubbleQuest: the `BubbleQuestAPI` global, `ns.Quest` here, feature-detected).
Design: [docs/design.md](docs/design.md); terrain data: [docs/terrain-map.md](docs/terrain-map.md).
Split out of the BubbleQuest repository (github.com/ChefJulio/bubble-quest) on 2026-11-21 with its history;
older notes there call BubbleQuest "Questmarker".

## API ground truth

Model knowledge of the WoW API is out of date and retail-flavored. Forever runs the modern client
(build pinned in `tools/toolchain.json`) with Midnight addon restrictions (secret values, protected calls).

- Before using any API, event, widget method or Blizzard frame, verify it in `.tools/wow-ui-source`
  (Forever branch): `Interface/AddOns/Blizzard_APIDocumentationGenerated/` for API signatures and
  restriction flags, the rest of `Interface/` for how Blizzard itself uses it. Never guess.
- `.tools/` is created by `python tools/lint.py`; run it once if missing.

## Lint: mandatory

Run `python tools/lint.py` after every Lua/XML change. It must print `lint: OK`.

- Never silence a finding to get a pass. Fix the call, or for a restricted call that is genuinely
  correct, add `-- apiguard: allow <specific reason>` and tell the user what was acknowledged and why.
- A clean lint does not prove runtime behavior: secret values, taint and combat lockdown only show up
  in-game. Say so when handing changes over for testing.

## Map data

`Data/Tiles.lua` (terrain tiles) and `Data/Overlays.lua` (every zone's map overlays) are generated:
`python tools/terrain.py` and `python tools/overlays.py`, from wago.tools at the build in
`tools/toolchain.json`. Never edit them by hand; when the build pin moves, regenerate both
(`--check` tells whether they match).

## Releases

Automatic: pushing a tag `vX.Y.Z` runs `.github/workflows/release.yml` (BigWigs packager), which
uploads the zip to CurseForge and GitHub Releases. `-beta`/`-alpha` in the tag sets the release type.
Needs the `CF_API_KEY` repo secret and `## X-Curse-Project-ID` in the TOC.
Before tagging: replace `CHANGELOG.md` with this release's notes (only this release's), commit, and
check `python tools/package.py --check`. The TOC's version is `@project-version@`, filled from the
tag. `python tools/package.py` builds the same zip locally for testing.

## Conventions

- Lua: 2-space indent; addon state lives on the private namespace (`local ADDON_NAME, ns = ...`).
  New globals only when the client requires them (SavedVariables, `SLASH_*`, bindings); add those to
  `diagnostics.globals` in `.luarc.json`.
- Never create, move or show/hide secure frames in combat; queue until `PLAYER_REGEN_ENABLED`.
- Hide Blizzard UI, never modify it. Never replace Blizzard functions or scripts (`SetScript` on
  their frames, overwriting globals): that taints. Post-hooks (`HookScript`, `hooksecurefunc`)
  are allowed where needed. Never call Blizzard's update functions from a hook.
- A new file in the TOC needs a full client restart, not /reload, before it loads.
- Testing is in-game: `/reload`, BugSack/BugGrabber for errors.
