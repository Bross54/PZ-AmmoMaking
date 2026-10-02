# Reloading press: art and the files that would switch it on

Status: **PREPARED, NOT IN THE MOD.** Nothing in this folder is shipped,
loaded or referenced by `mod/`. The press stays switched off
(`AC_Calibres.PRESS.enabled = false`), `mod.info` names no tile sheet, and
the suite fails if either changes without the tests being changed with it.

What is here:

| File | What it is |
|---|---|
| `make_art.py` | draws the two placeholder sprites (facing south, facing east), 128 x 256 each. Original programmer art, drawn from boxes and a line; it copies nothing |
| `src/ammomaking_press_01_0.png`, `_1.png` | the sprites it draws |
| `tiles.json` | the tile sheet: one tileset `ammomaking_press_01`, two tiles with the tile properties of vanilla's Hand Press |
| `AC_ReloadingPress.txt` | the entity script, a draft that follows vanilla's `Hand_Press` field for field |
| `build/` (not in git) | `ammomaking_press.tiles` and `texturepacks/AmmoMakingPress.pack`, written by `python tools/build_tiles.py art/reloading_press/tiles.json` |

## What was checked without the game

- The two binary formats. `tools/build_tiles.py --verify --install <game>`
  reads vanilla's `newtiledefinitions.tiles`, `tiledefinitions_erosion
  .tiles` and two of its texture packs and writes each back **byte for
  byte**. The files this folder builds are written by the same code.
- The built sheet reads back as described: tileset name, eight columns,
  sprite names `ammomaking_press_01_0` and `_1`, the tile properties, a 128
  x 256 frame, and every pixel of each sprite (`--selftest` does the same on
  generated sprites).
- The entity script names only things that exist in 42.20.4: the timed
  action, the build inputs, the skill, the skin's window classes and icon.
- No vanilla entity can claim these sprites: the names are the mod's own.

## What was not, and cannot be, checked without the game

**REQUIRES FUTURE IN-GAME VERIFICATION**, all of it:

- that the game loads the tile sheet from `pack=` and `tiledef=` and draws
  the sprites, and that they sit correctly on the tile;
- that the tile-definition number (6142) is used by no other enabled mod;
- that the entity loads, can be built, opens the crafting window and lists
  exactly the press recipes;
- everything in `docs/RELOADING_PRESS_DESIGN.md` 9.

## Switching the press on (a session with the game, not before)

1. Replace the placeholder sprites if better art exists (same file names,
   128 x 256, transparent background), or keep them.
2. `python tools/build_tiles.py art/reloading_press/tiles.json`
3. Copy `build/ammomaking_press.tiles` to `mod/AmmoMaking/42/media/` and
   `build/texturepacks/AmmoMakingPress.pack` to
   `mod/AmmoMaking/42/media/texturepacks/`.
4. Add to `mod/AmmoMaking/42/mod.info` the two lines the builder prints:
   `pack=AmmoMakingPress` and `tiledef=ammomaking_press 6142`.
5. Copy `AC_ReloadingPress.txt` to `mod/AmmoMaking/42/media/scripts/`.
6. Set `AC_Calibres.PRESS.enabled = true`, run `tests/write_recipes.lua`,
   and add the 27 recipe names to `Recipes.json` (each hand recipe's name
   with " (Press)").
7. Run the suite. It will fail in the places that pin "the press is off"
   (the release metadata, the press section, the Workshop text): each of
   those is a statement to change on purpose, with the game running.
8. Load a world. If it does not load, remove the `tiledef=` line first.
