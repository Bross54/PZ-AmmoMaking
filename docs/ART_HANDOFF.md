# Art handoff

A brief for whoever makes the mod's final art. The mod is playable without
any of it: every visual is a placeholder today
(`docs/PLACEHOLDER_ASSETS.md` lists each one and where it is configured).
Nothing here changes gameplay, and replacing an asset is a change of one
value, not of code.

Facts about formats are marked **FILE** (read in the installed Build
42.20.4), **JAR**, or **CLUE** (seen in an installed Workshop mod; a hint,
not proof). How an asset looks in the game is **REQUIRES FUTURE IN-GAME
VERIFICATION** for every item on this page.

## 1. The three kinds of asset

### 1.1 Inventory icon

| | |
|---|---|
| Format | PNG, **32 x 32**, transparent background (CLUE: the item icons of installed mods are 32 x 32) |
| File | `media/textures/Item_<IconName>.png` in the mod that defines the item. JAR `Item`: the engine puts `Item_` in front of the script's `Icon` value |
| Wired by | the item's `Icon = <IconName>` in its script |
| Style | vanilla's inventory icons: a single object, three-quarter view, soft dark outline, no drop shadow, readable at 32 px |

### 1.2 World model (the item lying on the ground)

| | |
|---|---|
| Format | a mesh (`.fbx`; FILE: `media/models_X/WorldItems/*.FBX`) and a texture (PNG; FILE: `media/textures/WorldItems/*.png`, e.g. 128 x 128) |
| Model script | FILE `scripts/generated/models_items.txt`: `model <Name> { mesh = WorldItems/<Mesh>, texture = WorldItems/<Texture>, scale = <number>, }` |
| Wired by | the item's `WorldStaticModel = <Name>` |
| Optional | yes. An item with a good icon and a borrowed or missing world model is fine; five items of the geology stage have none today |

### 1.3 Tile sprite (a placed object)

| | |
|---|---|
| Format | PNG, **128 x 256** per face at the game's 2x scale, transparent, bottom-anchored on the floor diamond (128 x 64). FILE: every entry of `Tiles2x.pack` has that full frame |
| Projection, light | the game's 2:1 isometric; light from the upper left |
| Built by | `python tools/build_tiles.py <tiles.json>` into a `.tiles` and a `.pack` (the builder is checked by writing vanilla's own files back byte for byte) |
| Wired by | sprite names in a tile sheet; an entity script or `AC_Visuals.lua` names them |

## 2. What is needed, by priority

Priority 1 is what a player looks at most or what is plainly wrong today.

### Priority 1

| Asset | Kind | Concept | Files | Replaces (config key) |
|---|---|---|---|---|
| **Reloading Press**, south and east | tile sprite, two faces, **one tile** | a single-stage bench press on a short wooden stand: cast frame, long lever, ram, a die in the top. Muted colours, dark outline, to sit beside vanilla's `crafted_01` workshop set. Vanilla's hand press fills about 110 x 154 px at offset (4, 94) for south and 103 x 141 at (18, 107) for east; fill about the same box | `art/reloading_press/src/ammomaking_press_01_0.png` (S), `ammomaking_press_01_1.png` (E) | the two PNG files themselves; sprite names and `AC_Visuals` keys `pressSpriteSouth`, `pressSpriteEast` stay |
| Reloading Press window icon | 32 x 32 (CLUE: a `Build_<Name>.png` in `media/textures`) | the press, small | `mod/AmmoMakingPress/42/media/textures/Build_AmmoMakingReloadingPress.png` | `Icon = Build_Handpress` in `AC_ReloadingPress_xuiSkin.txt` (twice) and `AC_Visuals` key `pressWindowIcon` |
| **Laboratory Assay Analyzer**, placed | tile sprite, one tile, one or two faces | a bench-top instrument on a stand: a boxy steel cabinet with a small window, a dial and a sample tray; clearly electrical | a new sheet, e.g. `art/laboratory_analyzer/` with its own `tiles.json`, shipped by the main mod (`pack=`, `tiledef=`) | `AC_Visuals` key `analyzerWorldSprite` (today the vanilla tile `industry_03_61`) |
| Laboratory Assay Analyzer, item | icon | the same instrument | `Item_LaboratoryAssayAnalyzer.png` | `Icon = CarBatteryCharger` of `LaboratoryAssayAnalyzer` |
| Field Assay Kit, Advanced Field Assay Kit | icon each | a small roll or tin with a loupe, tweezers and paper; the advanced one a hard case with a calculator | `Item_FieldAssayKit.png`, `Item_AdvancedFieldAssayKit.png` | `Icon = FirstAid_Camping`, `Icon = MakeupCase_Professional` |
| Geological Sample | icon | a labelled jar of soil and rock | `Item_GeologicalSample.png` | `Icon = SpecimanJar_Full1` |

### Priority 2: the things that are made by the hundred

| Asset | Kind | Concept | Replaces |
|---|---|---|---|
| Empty case, one per size class (small pistol, magnum, rifle bottleneck) and the brass shotgun hull | icon; a world model is optional | an empty brass case, mouth up or lying; the hull is a short brass tube with a rim | `Icon = PistolAmmo` / `RifleAmmo308loose` / `ShotgunAmmo` of the `Case...` and `Hull12Gauge` items. One icon per class is enough: the item name tells the calibres apart |
| **Spent case**, the same classes | icon | the same case, dull and sooted at the mouth, the primer dented | the generated `AC_SpentCaseItems.txt`: set `Icon` / `WorldStaticModel` for spent cases in `AC_SpentCases.buildItems` (today each spent case copies its unused case, so a spent and an unused case look identical) |
| Copper bullet, pistol and rifle; copper shot charge | icon | a single copper projectile; a small heap of copper shot | `Icon = SteelRod_Slug` of the `Bullet...` and `ShotCharge12Gauge` items |
| Primer, four families | icon; one drawing in two sizes is enough | a tiny brass cup with an anvil | `Icon = SnapCap` of the four primer items |
| Handloading die set | icon, one for all calibres or one per class | a small box with two or three steel dies and a shell holder | `Icon = Punches_Forged` of the nine `DieSet...` items |

### Priority 3: materials

| Asset | Kind | Concept | Replaces |
|---|---|---|---|
| Zinc ore | icon and world model | a grey-blue ore lump, clearly not iron | `IronOre` (icon and both models) |
| Zinc scrap, zinc ingot | icon each | bluish-white metal; the ingot a plain bar | `AluminumScrap`, `Ingot_Silver` / `SilverBar` |
| Small brass sheet, brass case cup | icon each | a small yellow sheet; a shallow drawn cup | `Sheet_Copper_Small` / `SmallCopperSheet`, `BrassScrap` |

Not needed: brass ingot, brass scrap, copper items, gunpowder and the
finished rounds are vanilla's own items with vanilla's own art.

## 3. Naming and delivery

- **File names** as in the tables; icons always `Item_<IconName>.png`.
- **One asset, one name.** A new icon gets a new `IconName`
  (`AmmoMakingCaseSmall`, say) rather than overwriting a vanilla one: the
  mod must never change what a vanilla item looks like.
- **Where they go**: `mod/AmmoMaking/42/media/textures/` for the main
  mod's items; the add-on's folder for an add-on's.
- **What changes in the mod** for each delivered asset: one `Icon =` (or
  `WorldStaticModel =`) line in an item script, or one `value` in
  `AC_Visuals.lua`, then `lua5.1 tests/write_recipes.lua` and the suite.
  `docs/PLACEHOLDER_ASSETS.md` regenerates itself from those values and
  will show what is still borrowed.
- The item audit of the suite currently requires every icon and model to
  be one a **vanilla** item uses. With the first asset of the mod's own,
  that check takes a list of the mod's own names; it is the one test
  change the first delivery needs.

## 4. What not to draw

No weapon, no magazine, no ammunition box, no projectile in flight, no
muzzle or casing effect: the mod uses vanilla's firearms and rounds
unchanged and adds no visual effect to firing.
