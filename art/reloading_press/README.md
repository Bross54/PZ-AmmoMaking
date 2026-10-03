# Reloading press: art source

The Reloading Press is an **experimental add-on mod**,
`mod/AmmoMakingPress`. This folder holds the source of its tile sheet; the
built sheet, the station entity and the press recipes are in the add-on.
Nothing of the press is in the main mod: the press exists only in a game
where the add-on is ticked (feature `reloadingPress`, `AC_Features.lua`).

| File | What it is |
|---|---|
| `make_art.py` | draws the two placeholder sprites (facing south, facing east), 128 x 256 each. Original programmer art, drawn from boxes and a line; it copies nothing |
| `src/ammomaking_press_01_0.png`, `_1.png` | the sprites it draws. **PLACEHOLDER_VISUAL**: replace these two files with final art under the same names |
| `tiles.json` | the tile sheet: one tileset `ammomaking_press_01`, two tiles with the tile properties of vanilla's Hand Press, and where the built files go (`output`) |

Built from them, into the add-on, by
`python tools/build_tiles.py art/reloading_press/tiles.json`:

| File in `mod/AmmoMakingPress/42/media/` | |
|---|---|
| `ammomaking_press.tiles` | the tile definitions |
| `texturepacks/AmmoMakingPress.pack` | the texture pack |

and named by the add-on's `mod.info`:

```text
pack=AmmoMakingPress
tiledef=ammomaking_press 6142
```

`python tools/build_tiles.py art/reloading_press/tiles.json --check`
fails when the built files differ from a fresh build; the release gate
runs it.

## Replacing the placeholder art

1. Put the new sprites at `src/ammomaking_press_01_0.png` (south) and
   `_1.png` (east): 128 x 256, transparent background, bottom-anchored on
   the floor diamond (`docs/ART_HANDOFF.md`).
2. `python tools/build_tiles.py art/reloading_press/tiles.json`
3. Run the suite. No Lua, script or recipe changes: the sprite names stay.

## What was checked without the game

- The two binary formats. `tools/build_tiles.py --verify --install <game>`
  reads vanilla's `newtiledefinitions.tiles`, `tiledefinitions_erosion
  .tiles` and two of its texture packs and writes each back **byte for
  byte**. The files built here are written by the same code.
- The built sheet reads back as described: tileset name, eight columns,
  sprite names `ammomaking_press_01_0` and `_1`, the tile properties, a 128
  x 256 frame, and every pixel of each sprite (`--selftest` does the same on
  generated sprites).
- The entity script names only things that exist in 42.20.4: the timed
  action, the build inputs, the skill, the skin's window classes and icon.
- No vanilla entity can claim these sprites: the names are the add-on's own.
- An installed Workshop mod ships a station the same way (an add-on with
  `require=`, `pack=`, `tiledef=`, a `CraftBench` entity built from the
  build menu); see `docs/REFERENCE_IMPLEMENTATIONS.md`. A clue, not proof.

## What was not, and cannot be, checked without the game

**REQUIRES FUTURE IN-GAME VERIFICATION**, all of it:

- that the game loads the tile sheet from `pack=` and `tiledef=` and draws
  the sprites, and that they sit correctly on the tile;
- that the tile-definition number (6142) is used by no other enabled mod;
- that the entity loads, can be built, opens the crafting window and lists
  exactly the press recipes;
- that the placed press can be picked up and put down again and is still a
  station afterwards;
- everything in `docs/RELOADING_PRESS_DESIGN.md` 9.

If a world does not load with the add-on ticked, untick the add-on: the
main mod contains nothing of the press. `docs/INGAME_VALIDATION.md` has the
steps.
