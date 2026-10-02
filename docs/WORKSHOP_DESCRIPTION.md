# Steam Workshop material

Status: **PREPARED, NOT PUBLISHED.** Nothing here has been uploaded. This
file holds the text and the checklist for the day the mod is published; the
release itself is built by `tools/build_release.py`.

Wording used below, on purpose:

- **seen in game**: the developer saw it work in Project Zomboid 42.20.4
- **implemented**: written and checked offline (Lua logic, data, and the
  installed game's files); not yet seen in game
- **source-verified**: read from the installed 42.20.4 scripts, Lua or jar

Nothing that is only *implemented* may be described to players as tested.

## 1. Title

```text
Ammo Making [B42]
```

## 2. Short description (the mod list line; equals `mod.info`)

```text
Advanced ammunition manufacturing, mining and metallurgy for Project Zomboid Build 42.
```

## 3. Workshop description (Steam BBCode)

```text
[h1]Ammo Making[/h1]

Make ammunition from the ground up: find ore, mine it, smelt brass, and load the nine vanilla cartridges by hand.

[b]Work in progress, Build 42.20 or later, single player.[/b] Recipes, balance and item names may still change between versions.

[h2]What it adds[/h2]
[list]
[*][b]Ammo Making skill[/b] with 10 levels. Levels unlock calibres and shorten the work.
[*][b]Geology.[/b] Every save has its own hidden copper and zinc. Dig a geological sample with a shovel, then assay it: a field kit gives a rough grade, an advanced kit a range, the powered laboratory analyzer a precise figure a day later.
[*][b]Mining.[/b] Inside an assayed area, a pickaxe takes ore from the ground. Deposits are finite and stay depleted.
[*][b]Metallurgy[/b] on the vanilla furnaces and forge: zinc and copper ingots, brass (7 copper + 3 zinc), small brass sheets, case cups.
[*][b]Ammunition.[/b] Die sets, cases, copper bullets, four kinds of primer, gunpowder from charcoal and fertilizer, and assembly into the [b]vanilla[/b] rounds: 9mm, .38 Special, .45 ACP, .357 Magnum, .44 Magnum, 5.56, .30-30, .308 and 12 gauge shells. Vanilla firearms, magazines and ammo boxes work with them unchanged.
[*][b]Die sets as rare loot[/b] in gun stores, garage gun lockers and hunters' things. They can always be forged instead.
[*][b]Brass recycling.[/b] Unwanted brass parts become brass scrap at half the brass, and scrap is recast into ingots.
[*][b]Inspection.[/b] Empty cases and loose handloaded rounds show their calibre and case quality.
[/list]

[h2]What it does not do (yet)[/h2]
[list]
[*]A handloaded round fires exactly like a factory round. Case quality is recorded and shown; it has no effect on shooting.
[*]No spent cases: firing leaves nothing to pick up.
[*]No reloading press: everything is done by hand at a surface.
[*]The assay kits and the laboratory analyzer are not craftable or lootable yet; they come from the debug menu.
[/list]

[h2]Multiplayer[/h2]
Not supported. Mining and placing the laboratory analyzer are switched off for multiplayer clients, and nothing is synchronised between players. The crafting recipes are ordinary vanilla recipes, but they have not been tried on a server.

[h2]Compatibility[/h2]
[list]
[*]Project Zomboid [b]Build 42.20 or later[/b]. Not for Build 41.
[*]No other mod is required.
[*]It replaces no vanilla file, item, recipe or function. It adds its own items and recipes, adds entries to four vanilla loot lists, and puts a level requirement on its own recipes.
[*]It can be added to an existing save: geology is worked out from the save itself and nothing is stored until you dig or mine. Containers that were already filled keep what they have, so die sets only turn up in places not visited yet. (Not yet tried on a long-running save.)
[/list]

[h2]Testing status[/h2]
Seen working in game (42.20.4): geological sampling, mining with a pickaxe, depletion and exhausted deposits.
Implemented and checked against the installed game's files, but not yet seen in game: metallurgy, case stock, every ammunition recipe, die-set loot, brass recycling, the placed laboratory analyzer.
Please report anything that does not work, with the relevant lines of console.txt.

[h2]Debug mode[/h2]
With the game started in -debug, right-click the ground for [b]Ammo Making Debug[/b]: kits for every stage, level setting, and a compatibility check. The mod also checks its assumptions about the game at every start and writes any problem to console.txt, each line beginning with [AmmoMaking].

[h2]Source and credits[/h2]
Source, design documents and tests are in the project repository. Developed with substantial AI assistance; see the repository's disclosure.
Unofficial mod, not affiliated with The Indie Stone.
```

## 4. Tags

`Build 42`, `Items`, `Weapons`, `Realistic`, `Skills` (the names offered by
the game's uploader on the day decide).

## 5. Dependencies

None. `mod.info` has no `require=` line, and a test fails if one appears
without this file being updated.

## 6. What the upload needs, and what exists

| Needed | State |
|---|---|
| The mod folder `AmmoMaking/` (`42/`, `common/`) | built by `python tools/build_release.py` into `release/AmmoMaking/` and `release/AmmoMaking-<version>.zip` |
| `mod.info` with `name`, `id`, `modversion`, `versionMin`, `description` | present; validated by the builder |
| `poster=` image in the mod folder | **missing: needs art** (the mod list shows no picture without it; not an error) |
| Workshop item folder: `Contents/mods/AmmoMaking/` beside `preview.png` (256 x 256) and `workshop.txt` | **not created: needs `preview.png`**; `workshop.txt` is written by the game's own uploader |
| Changelog | `CHANGELOG.md` |
| In-game pass on the published build | **not done**: see `DEVELOPMENT.md`, *REQUIRES IN-GAME VERIFICATION* |

The game's uploader (main menu, Workshop) reads the item folder from
`Zomboid/Workshop/<ItemName>/`. Copy `release/AmmoMaking/` to
`Zomboid/Workshop/AmmoMaking/Contents/mods/AmmoMaking/`, add `preview.png`,
and upload from the game. **None of this was done or tried.**

## 7. Before publishing: the gate

```text
python tools/build_release.py --install "<Project Zomboid install>" --mutants
```

and then, with the game, the list in `DEVELOPMENT.md`. A first public
version should not go out before at least one full chain, ore to a fired
round, has been made in game: every ammunition recipe is so far
*implemented*, not *seen in game*.

## 8. REQUIRES FUTURE IN-GAME VERIFICATION

- That the mod list shows the version from `modversion=` and accepts
  `versionMin=42.20.0` on 42.20.4 (source-verified: `GameVersion.parse` and
  `isLessThan` compare major and minor only, and installed Workshop mods
  use the same line; not seen with this mod).
- That the built folder, copied into `Zomboid/mods/`, loads exactly as the
  repository's `mod/AmmoMaking` does.
- The uploader's folder layout and tag names.
