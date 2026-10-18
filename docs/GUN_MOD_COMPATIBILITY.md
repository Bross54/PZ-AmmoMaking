# Compatibility with gun mods

Ammo Making loads the nine vanilla rounds. A round another mod adds is
loaded through a small add-on of Ammo Making, one per gun mod ("pack"),
which requires that mod. Everything in a pack is generated from the main
mod's model (`AC_Calibres.EXTENSIONS`, `tests/render_addons.lua`); the
add-on holds no Lua. The round ids and AmmoType keys below were read from
the gun mods' installed files on 2026-10-17 (Guns of 93 and Post Soviet
Armory on 2026-10-18), and are checked against them by
`tools/pz_compat.py` (section 6). **None of it has been seen in game.**

## 1. The packs

| Add-on | Gun mod (Workshop, mod id) | Cannot be loaded with |
|---|---|---|
| Ammo Making: 7.62x39 (`AmmoMakingCalibre762x39`) | Vanilla Weapons Plus - Gunworks Edition (3773834525, `MarzVanillaGuns`) | the Rain's packs |
| Ammo Making: Vanilla Firearms Expansion (`AmmoMakingVFE`) | Vanilla Firearms Expansion B42 (3761077099, `VFExpansion1`) | the Rain's packs |
| Ammo Making: Rain's Firearms (`AmmoMakingRains`) | B42 Rain's Firearms & Gun Parts (3773858287, `B42RainsFirearmsAndGunParts4220`) | 7.62x39, VFE, Rain's Expanded |
| Ammo Making: Rain's Firearms Expanded (`AmmoMakingRainsExpanded`) | ... Expanded (3773858287, `B42RainsFirearmsAndGunPartsExpanded4220`) | 7.62x39, VFE, Rain's |
| Ammo Making: GaelGunStore (`AmmoMakingGaelGunStore`) | GaelGunStore (3616176188, `GaelGunStore_B42`) | - |
| Ammo Making: Real Firearms (`AmmoMakingRealFirearms`) | Real Firearms (3238830225, `RealFirearms`) | - |
| Ammo Making: Modern Firearms System (`AmmoMakingMFS`) | Modern Firearms System (3633421539, `ModernFirearmsSystem`) | - |
| Ammo Making: Guns of 93 (`AmmoMakingGuns93`) | Guns of 93: B42 Test Build (3183820077, `guns93`) | - |
| Ammo Making: Post Soviet Armory (`AmmoMakingPSA`) | Post Soviet Armory B42 (3722136144, `PostSovietArmoryB42`) | - |

**Why some cannot be loaded together.** `Base.762Bullets` is the 7.62x39 of
Vanilla Weapons Plus and VFE, and the 7.62x51 of Rain's. Whichever gun mod
loads last owns the item; a pack built for the other would make the wrong
round. The add-ons say `incompatible=` on both sides, so the game refuses
the pair. A round two packs agree on (`Base.223Bullets`, `Base.762x39Bullets`,
`Base.Bullets50`) is one calibre, generated identically into each.

## 2. The calibres

Each has a die set, a case (a hull for the shells), a copper bullet and a
cast bullet, and twelve recipes: the four steps, regrinding, annealing, a
cast in every mould material, the cast assembly (a rifle's with a gas
check) and lubing. Item looks and English names come from a vanilla
template (.308, .357 Magnum, 12 Gauge). A calibre whose name is already
taken is marked: (RF), (MFS), M43.

| Calibre | Round | Class | Packs |
|---|---|---|---|
| 7.62x39 | `Base.762Bullets` | rifle | calibre762x39, packVFE |
| .223 | `Base.223Bullets` | rifle | packVFE, packRains, packRainsExpanded |
| 7.62x51 | `Base.762Bullets` | rifle | packRains, packRainsExpanded |
| 7.62x39 M43 | `Base.762x39Bullets` | rifle | packRains, packRainsExpanded, packGaelGunStore |
| .45-70 | `Base.4570Bullets` | rifle | packRainsExpanded |
| .45 Colt | `Base.45ColtBullets` | pistol | packRainsExpanded |
| 7.63x25 | `Base.763x25Bullets` | pistol | packRainsExpanded |
| .32 ACP | `Base.Bullets32` | pistol | packGaelGunStore |
| 9x39 | `Base.9x39Bullets` | rifle | packGaelGunStore |
| 5.45x39 | `Base.545x39Bullets` | rifle | packGaelGunStore |
| 7.62x54R | `Base.762x54rBullets` | rifle | packGaelGunStore |
| 7.92x57 | `Base.792x57Bullets` | rifle | packGaelGunStore |
| .30-06 | `Base.30_06Bullets` | rifle | packGaelGunStore |
| .303 British | `Base.303Bullets` | rifle | packGaelGunStore |
| .50 AE | `Base.Bullets50Magnum` | pistol | packGaelGunStore |
| .50 BMG | `Base.Bullets50` | rifle | packGaelGunStore, packMFS |
| 9x19 (RF) | `Base.RF_9x19Bullets` | pistol | packRealFirearms |
| 9x18 (RF) | `Base.RF_9x18Bullets` | pistol | packRealFirearms |
| .45 ACP (RF) | `Base.RF_45Bullets` | pistol | packRealFirearms |
| .357 Magnum (RF) | `Base.RF_357Bullets` | pistol | packRealFirearms |
| .380 ACP (RF) | `Base.RF_380Bullets` | pistol | packRealFirearms |
| .500 Magnum (RF) | `Base.RF_500Bullets` | pistol | packRealFirearms |
| 7.62x25 (RF) | `Base.RF_762x25Bullets` | pistol | packRealFirearms |
| .30 Carbine (RF) | `Base.RF_30CarbineBullets` | rifle | packRealFirearms |
| 5.45x39 (RF) | `Base.RF_545x39Bullets` | rifle | packRealFirearms |
| 5.56x45 (RF) | `Base.RF_556x45Bullets` | rifle | packRealFirearms |
| 7.62x39 (RF) | `Base.RF_762x39Bullets` | rifle | packRealFirearms |
| 7.62x51 (RF) | `Base.RF_762x51Bullets` | rifle | packRealFirearms |
| 7.62x54R (RF) | `Base.RF_762x54Bullets` | rifle | packRealFirearms |
| 7.92x33 (RF) | `Base.RF_792x33Bullets` | rifle | packRealFirearms |
| 7.92x57 (RF) | `Base.RF_792x57Bullets` | rifle | packRealFirearms |
| .30-06 (RF) | `Base.RF_3006Bullets` | rifle | packRealFirearms |
| 12.7x55 (RF) | `Base.RF_127x55Bullets` | rifle | packRealFirearms |
| 12 Gauge (RF) | `Base.RF_12GaugeBullets` | shotgun | packRealFirearms |
| 5.8x42 | `Base.A_58bullets` | rifle | packMFS |
| 5.45x39 (MFS) | `Base.545Bullets` | rifle | packMFS |
| 8.6mm | `Base.Bullets86` | rifle | packMFS |
| 14.5mm | `Base.Bullets145` | rifle | packMFS |
| 10mm Auto | `Base.10mmBullets` | pistol | packGuns93 |
| .25 ACP | `Base.25Bullets` | pistol | packGuns93 |
| .30-06 (G93) | `Base.3006Bullets` | rifle | packGuns93 |
| .30 Carbine | `Base.30CarBullets` | rifle | packGuns93 |
| .380 ACP | `Base.380Bullets` | pistol | packGuns93 |
| .40 S&W | `Base.40Bullets` | pistol | packGuns93 |
| .45 Colt (G93) | `Base.45LCBullets` | pistol | packGuns93 |
| 7.62x39 (G93) | `Base.76239Bullets` | rifle | packGuns93 |
| 7.92x57 (G93) | `Base.792Bullets` | rifle | packGuns93 |
| 12 Gauge Slug | `Base.SlugBullets` | shotgun | packGuns93 |
| 9x18 | `Base.Bullets9x18mm` | pistol | packPSA |
| 9x19 | `Base.Bullets9x19mm` | pistol | packPSA |
| 9x39 (PSA) | `Base.Bullets9x39mm` | rifle | packPSA |
| 5.45x39 (PSA) | `Base.Bullets545x39` | rifle | packPSA |
| 7.62x25 | `Base.Bullets762x25` | pistol | packPSA |
| 7.62x38R | `Base.Bullets762x38R` | pistol | packPSA |
| 7.62x39 (PSA) | `Base.Bullets762x39` | rifle | packPSA |
| 7.62x54R (PSA) | `Base.Bullets762x54R` | rifle | packPSA |
| 23x75 | `Base.23x75ShotgunShells` | shotgun | packPSA |
| 12x70 | `Base.12x70ShotgunShells` | shotgun | packPSA |

**Left out on purpose.** Rimfire (.22, .22 LR): the priming is in the rim,
it is not reloaded. Grenades, rockets, arrows and bolts, flamethrower fuel,
machine-gun links (Guns of 93's belts), GaelGunStore's AP and tracer
variants (no firearm uses them) and Post Soviet Armory's 7.65x21 (no
firearm uses it). Guns of 93's slugs are an item of their own, so unlike
vanilla's single shell they are a calibre: the 12 gauge's hull, wad and
charge.

**What a pack covers besides its hand recipes** (since 2026-10-18):

- **Press recipes**: each calibre's case, bullet, assembly and cast
  assembly at the press. They are offered only where the press add-on's
  station exists (REQUIRES FUTURE IN-GAME VERIFICATION: a recipe whose
  bench tag no station has is never offered).
- **Spent cases**: each calibre's spent case is an item of the pack, with
  its resizing (two for one), steel-wool cleaning and scrapping. A shot
  leaves one only where the spent cases add-on is on
  (`AC_SpentCases.getSpentCaseForRound` reads every calibre in the game).
  Its icon is the spent cases add-on's; without that add-on the item shows
  the game's default icon, and is never left anyway. The case tumbler
  tumbles the vanilla calibres only.
- **Die sets as loot**: the same lists and tiers as the vanilla die sets,
  on a budget of their own: all of a game's extension die sets together
  weigh at most `AC_Loot.CONFIG.extensionListWeight` (0.25) times the list's
  scale, so even with every pack at once the fullest room (a row of
  military lockers) holds under one die set in twelve containers.

## 3. Mods that change vanilla rounds

Rain's, GaelGunStore and Modern Firearms System redefine the vanilla round
items (weights, counts). The mod's recipes still make those items.
**Modern Firearms System makes `Base.Bullets38` a 6.8mm round**: beside it
the .38 Special recipes make MFS's 6.8mm. The game-start check says so
(`AC_Compat.ROUND_OVERRIDES`, a WARNING); nothing is changed.

## 4. Casings of other mods

### 4.1 Hot Brass

Beside Hot Brass (3610677934, `HBVCEFb42`) the spent cases add-on stands
down: Hot Brass ejects casings of its own. **Ammo Making: Hot Brass Casings**
(`AmmoMakingHotBrass`) resizes them at the die set exactly like spent
cases: two casings into one usable case, the resizing malus, no XP. Its
casings carry the brass of their case. The casing of each vanilla round is
Hot Brass's own table (its `SpentCasingPhysics/Init.lua`), written into
`AC_Calibres` as `hotBrassCasing`.

### 4.2 Modern Firearms System

MFS (3633421539, `ModernFirearmsSystem`) leaves casings of its own too
(`MFSEject`, a sandbox switch that is on by default), for its rounds and
the vanilla ones, and replaces `ISRackFirearm:ejectSpentRounds` and
`ISReloadWeaponAction:ejectSpentRounds` at `OnInitGlobalModData` without
calling vanilla's (`MFSEject/TimedActionsHooks.lua`, read 2026-10-18).
Beside it the spent cases add-on stands down (a conflict of the feature).
The MFS calibre add-on (`AmmoMakingMFS`) resizes its casings at the die set
like Hot Brass's (`AC_SpentCases.CASING_BRIDGES.mfs`, `mfsCasing` per
vanilla calibre): 9mm, .45, .44, .308, 5.56 and 12 gauge. Not the .38: MFS
makes that round a 6.8mm and ejects a .30-06 casing for it.

## 5. Other ammunition-making mods

A game-start WARNING names each that is active
(`AC_Compat.OVERLAPPING_MODS`, mod ids from their Workshop pages on
2026-10-18): Ammo Maker (`ammomaker`), Ammocraft (`ammocraft`), Ammo
Reloading Bench (`ammobench`), Load It! (`LoadIt`), Ammo Reloading Toolset
(`DeonReloadingBench`), Vanilla Ammo Crafting (`vac`), Crafting Ammo
(`MakeBullets`), Ammo Craft (`AmmoCraft`), Rat's Ammo Crafting (`RAC`) and
Hot Brass Ammo Crafting (`HBAmmoCraft`), Guns of 93's Surplus, Reloading
and Crafting Add-On (`Guns93SurplusAmmoAddon`) and Gunsmith: The 1993
Arsenal (`Gunsmith1993`: read from the installed mod; it replaces the
vanilla rounds with graded rounds of its own and casts bullets at the
forges, so it gets no pack). Nothing is shared or switched off:
the player has two ways to the same rounds. None of them was installed or
read beyond its Workshop page except `HBAmmoCraft` and `Gunsmith1993`.

## 6. The installed gun mods, checked

`tools/pz_compat.py --update` reads every pack's gun mod from the Workshop
folder and records, in `tests/engine_snapshot.lua` (`gunMods`), whether it
defines each round, how many of its firearms and magazines name the
AmmoType the pack expects, and whether it defines the casings a bridge
resizes. The suite fails when one is missing; the tool warns. A gun mod
not installed where the snapshot is recorded is not judged.

A round two gun mods share is one item under a key of each mod's own:
`AC_Calibres.ammoTypeOf(calibre, feature)`, from `ammoTypes` beside
`ammoType`. On 2026-10-18 this found four keys that were another mod's:
VFE's 7.62x39 is `vfe:bullets_762`, Rain's .223 `firearms:bullets_223`,
GaelGunStore's 7.62x39 `ggs:762x39_bullets`, MFS's .50 `efk:cat_bullets50`.
The mod never read those keys in play (the hooks take the round from the
firearm), so nothing in the game changed.

## 7. Translations

English names are generated with the scripts. Every other language is
derived from that language's own names of the template's items and recipes:
`python tools/derive_addon_translations.py` (`--check` fails when a file
is stale). Run it after `tests/write_recipes.lua`.

## 8. Adding a gun mod

1. Subscribe, read its `registries.lua` and ammo scripts.
2. One `AC_Calibres.define` per new round in `EXTENSIONS`, with
   `extension`, `template`, `round` and `ammoType`.
3. A feature in `AC_Features` (`mod` = the add-on's id) and a pack in
   `EXTENSION_PACKS` (`tests/render_addons.lua`); `incompatible` for any
   pack whose round ids mean another calibre.
4. `tests/write_recipes.lua`, `tools/derive_addon_translations.py`,
   `art/workshop/make_workshop_art.py` (a poster), `tools/build_release.py`
   (`MODS`), then the tests.

## 9. REQUIRES FUTURE IN-GAME VERIFICATION

- Each add-on loads beside its gun mod, and the game refuses an
  incompatible pair.
- One round per pack: made, stacking with found ones, fired by the gun mod's
  firearm.
- Hot Brass casings resized into a case; MFS casings likewise, and the
  spent cases off beside MFS.
- The MFS warning at game start.
