# Art handoff

A brief for whoever makes the mod's final art. The mod is playable without
any of it. Its inventory icons and the press's window icon are already the
mod's own (section 2); the press's tile sprites are programmer art, the
analyzer's placed sprite and every world model are borrowed from vanilla
(`docs/PLACEHOLDER_ASSETS.md` lists each one and where it is configured).
Nothing here changes gameplay, and replacing an asset is a change of one
file or one value, not of code.

Facts about formats are marked **FILE** (read in the installed Build
42.20.4), **JAR**, or **CLUE** (seen in an installed Workshop mod; a hint,
not proof). How an asset looks in the game is **REQUIRES FUTURE IN-GAME
VERIFICATION** for every item on this page.

## 1. The three kinds of asset

### 1.1 Inventory icon

| | |
|---|---|
| Format | PNG, **32 x 32**, transparent background (CLUE: the item icons of installed mods are 32 x 32); a window icon `Build_<Name>.png` is **48 x 48**, like vanilla's `Build_` icons |
| File | `media/textures/Item_<IconName>.png` in the mod that defines the item. JAR `Item`: the engine puts `Item_` in front of the script's `Icon` value |
| Wired by | the item's `Icon = <IconName>` in its script; every icon of the mod's own is also listed in `AC_Visuals.ICONS` (name, mod, prefix, size) |
| Style | vanilla's inventory icons: a single object, three-quarter view, dark outline, no drop shadow, readable at 32 px, lit from the upper left |

### 1.2 World model (the item lying on the ground)

| | |
|---|---|
| Format | a mesh (`.fbx`; FILE: `media/models_X/WorldItems/*.FBX`) and a texture (PNG; FILE: `media/textures/WorldItems/*.png`, e.g. 128 x 128) |
| Model script | FILE `scripts/generated/models_items.txt`: `model <Name> { mesh = WorldItems/<Mesh>, texture = WorldItems/<Texture>, scale = <number>, }` |
| Wired by | the item's `WorldStaticModel = <Name>` |
| Optional | yes. An item with a good icon and a borrowed or missing world model is fine; four items of the geology stage have none today |

### 1.3 Tile sprite (a placed object)

| | |
|---|---|
| Format | PNG, **128 x 256** per face at the game's 2x scale, transparent, bottom-anchored on the floor diamond (128 x 64). FILE: every entry of `Tiles2x.pack` has that full frame |
| Projection, light | the game's 2:1 isometric; light from the upper left |
| Built by | `python tools/build_tiles.py <tiles.json>` into a `.tiles` and a `.pack` (the builder is checked by writing vanilla's own files back byte for byte) |
| Wired by | sprite names in a tile sheet; an entity script or `AC_Visuals.lua` names them |

## 2. Already drawn: the mod's own icons

Original pixel art drawn by `python art/icons/make_icons.py` (deterministic;
`--check` fails when a shipped file differs from a fresh drawing). Every
icon at eight times its size: `art/icons/preview.png`. They copy no vanilla
or third-party pixel and replace no vanilla icon.

They are good enough to ship, not final. An artist may redraw any of them:
keep the file name, the size and the folder, and nothing else changes. The
wiring (`Icon =` lines, `AC_Visuals.ICONS`, `AC_Visuals.SPENT_ICONS`) stays
as it is. If `make_icons.py` is no longer the source of a redrawn file,
drop that entry from the script so `--check` does not overwrite it.

| File | Mod (`media/textures/`) | Used by |
|---|---|---|
| `Item_AmmoMakingZincOre` | AmmoMaking | Zinc Ore |
| `Item_AmmoMakingZincScrap` | AmmoMaking | Zinc Scrap |
| `Item_AmmoMakingZincIngot` | AmmoMaking | Zinc Ingot |
| `Item_AmmoMakingBrassSheet` | AmmoMaking | Brass Sheet - Small |
| `Item_AmmoMakingCaseCup` | AmmoMaking | Brass Case Cup |
| `Item_AmmoMakingPrimerSmallPistol` | AmmoMaking | Small Pistol Primer |
| `Item_AmmoMakingPrimerLargePistol` | AmmoMaking | Large Pistol Primer |
| `Item_AmmoMakingPrimerSmallRifle` | AmmoMaking | Small Rifle Primer |
| `Item_AmmoMakingPrimerLargeRifle` | AmmoMaking | Large Rifle Primer |
| `Item_AmmoMakingDieSet` | AmmoMaking | the nine handloading die sets |
| `Item_AmmoMakingCasePistol` | AmmoMaking | empty 9mm and .45 ACP cases |
| `Item_AmmoMakingCaseMagnum` | AmmoMaking | empty .38 Special, .357 and .44 Magnum cases |
| `Item_AmmoMakingCaseRifle` | AmmoMaking | empty 5.56, .30-30 and .308 cases |
| `Item_AmmoMakingHull` | AmmoMaking | Empty 12 Gauge Brass Hull |
| `Item_AmmoMakingBulletPistol` | AmmoMaking | the pistol and magnum copper bullets |
| `Item_AmmoMakingBulletRifle` | AmmoMaking | the rifle copper bullets |
| `Item_AmmoMakingShot` | AmmoMaking | 12 Gauge Copper Shot Charge |
| `Item_AmmoMakingSample` | AmmoMaking | Geological Sample |
| `Item_AmmoMakingFieldKit` | AmmoMaking | Field Assay Kit |
| `Item_AmmoMakingAdvancedKit` | AmmoMaking | Advanced Field Assay Kit |
| `Item_AmmoMakingAnalyzer` | AmmoMaking | Laboratory Assay Analyzer (the item; the placed one is a tile, section 3) |
| `Item_AmmoMakingBook1` | AmmoMaking | Ammo Making I (olive cover, one brass band on the spine) |
| `Item_AmmoMakingBook2` | AmmoMaking | Ammo Making II (navy, two bands) |
| `Item_AmmoMakingBook3` | AmmoMaking | Ammo Making III (brown, three bands) |
| `Item_AmmoMakingBook4` | AmmoMaking | Ammo Making IV (oxblood, four bands) |
| `Item_AmmoMakingBook5` | AmmoMaking | Ammo Making V (steel grey, five bands) |
| `Item_AmmoMakingSpentCasePistol` | AmmoMakingSpentCases | spent 9mm and .45 ACP cases |
| `Item_AmmoMakingSpentCaseMagnum` | AmmoMakingSpentCases | spent .38 Special, .357 and .44 Magnum cases |
| `Item_AmmoMakingSpentCaseRifle` | AmmoMakingSpentCases | spent 5.56, .30-30 and .308 cases |
| `Item_AmmoMakingSpentHull` | AmmoMakingSpentCases | Spent 12 Gauge Brass Hull |
| `Build_AmmoMakingReloadingPress` | AmmoMakingPress | the press's crafting window and build menu, 48 x 48 (`Icon = Build_AmmoMakingReloadingPress` in `AC_ReloadingPress_xuiSkin.txt`, twice; `AC_Visuals` key `pressWindowIcon`) |

A spent case is the same drawing tarnished and sooted at the mouth;
`AC_SpentCases.buildItems` picks it through `AC_Visuals.SPENT_ICONS` from
the icon of the unused case. Redrawn icons should keep that pairing: a
spent case reads as the case it was, used.

## 3. What is still needed, by priority

Priority 1 is what a player looks at most or what is plainly wrong today.

### Priority 1

| Asset | Kind | Concept | Files | Replaces (config key) |
|---|---|---|---|---|
| **Reloading Press**, south and east | tile sprite, two faces, **one tile** | a single-stage bench press on a short wooden stand: cast frame, long lever, ram, a die in the top. Muted colours, dark outline, to sit beside vanilla's `crafted_01` workshop set. Vanilla's hand press fills about 110 x 154 px at offset (4, 94) for south and 103 x 141 at (18, 107) for east; fill about the same box | `art/reloading_press/src/ammomaking_press_01_0.png` (S), `ammomaking_press_01_1.png` (E), then `python tools/build_tiles.py art/reloading_press/tiles.json` | the programmer art drawn by `art/reloading_press/make_art.py`; the sprite names `ammomaking_press_01_0`, `ammomaking_press_01_1` and the `AC_Visuals` keys `pressSpriteSouth`, `pressSpriteEast` stay. Redraw the window icon `Build_AmmoMakingReloadingPress` to match |
| **Laboratory Assay Analyzer**, placed | tile sprite, one tile, one or two faces | a bench-top instrument on a stand: a boxy steel cabinet with a small window, a dial and a sample tray; clearly electrical; the same instrument as `Item_AmmoMakingAnalyzer` | a new sheet, e.g. `art/laboratory_analyzer/` with its own `tiles.json`, shipped by the main mod (`pack=`, `tiledef=`) | `AC_Visuals` key `analyzerWorldSprite` (today the vanilla tile `industry_03_61`) |

### Priority 2: world models of the things made by the hundred

Every item below has its own icon and a borrowed vanilla world model
(`docs/PLACEHOLDER_ASSETS.md` names each). A world model is optional; one
per class is enough, the item name tells the calibres apart.

| Asset | Concept | Borrowed today |
|---|---|---|
| Empty case, one per class (pistol, magnum, rifle bottleneck) and the brass hull | a single empty brass case lying on its side; the hull a short brass tube with a rim | vanilla round and shell models |
| Spent case, the same classes | the same model with a dull, sooted texture | the same as its unused case (`AC_SpentCases.buildItems`) |
| Copper bullet, pistol and rifle; copper shot charge | a single copper projectile; a small heap of copper shot | vanilla `SteelSlug` |
| Primer, four families | a tiny brass cup; one model for all four | vanilla `CapGunCap` |
| Handloading die set | a small box with two or three steel dies | vanilla `SmallMetalworkingPunches` |

### Priority 3: world models of materials

| Asset | Concept | Borrowed today |
|---|---|---|
| Zinc ore | a grey-blue ore lump, clearly not iron | vanilla `IronOre` |
| Zinc scrap, zinc ingot | bluish-white metal; the ingot a plain bar | vanilla `AluminumScrap`, `SilverBar` |
| Small brass sheet, brass case cup | a small yellow sheet; a shallow drawn cup | vanilla `SmallCopperSheet`, `BrassScrap` |
| Ammo Making skill books, five volumes | a hardback with a cartridge on the cover; one model, or a cover colour per volume as the icons have | vanilla `Book13`, `Book13_Ground` (the Reloading books') |

The four geology items (sample, two kits, analyzer item) have no world
model at all; one is welcome, not needed.

### Workshop images

Missing (`docs/AMMUNITION_ROADMAP.md` 3.2): a `poster=` image for each
`mod.info` (the mod list shows no picture without it; not an error) and
a Workshop `preview.png`, 256 x 256, beside `Contents/` of the Workshop
item (`docs/WORKSHOP_DESCRIPTION.md`). Concept: the press on its bench
with a row of finished cases; no weapon.

Not needed: brass ingot, brass scrap, copper items, gunpowder and the
finished rounds are vanilla's own items with vanilla's own art. The Test
9mm Cartridge is a debug item and keeps its vanilla icon.

## 4. Naming and delivery

- **File names** as in the tables; icons always `Item_<IconName>.png`,
  window icons `Build_<Name>.png`.
- **One asset, one name.** A new asset gets a name starting
  `AmmoMaking` rather than overwriting a vanilla one: the mod must never
  change what a vanilla item looks like.
- **Where they go**: `mod/AmmoMaking/42/media/textures/` for the main
  mod's items; the add-on's own folder for an add-on's (an add-on can only
  use what it ships itself).
- **A redrawn icon**: replace the PNG at the same name and size; nothing
  else changes. **A new icon**: add it to `AC_Visuals.ICONS` and set the
  item's `Icon =`. **A world model**: ship the model script, mesh and
  texture, set the item's `WorldStaticModel =`. **A sprite**: replace the
  source PNG and rebuild the sheet, or change one `value` in
  `AC_Visuals.lua`. Then `lua5.1 tests/write_recipes.lua` and the suite;
  `docs/PLACEHOLDER_ASSETS.md` regenerates itself and shows what is still
  borrowed.

## 5. What not to draw

No weapon, no magazine, no ammunition box, no projectile in flight, no
muzzle or casing effect: the mod uses vanilla's firearms and rounds
unchanged and adds no visual effect to firing.
