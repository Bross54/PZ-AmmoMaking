# Compatibility with gun mods

Ammo Making loads the nine vanilla rounds. A round another mod adds is
loaded through a small add-on of Ammo Making, one per gun mod ("pack"),
which requires that mod. Everything in a pack is generated from the main
mod's model (`AC_Calibres.EXTENSIONS`, `tests/render_addons.lua`); the
add-on holds no Lua. The round ids and AmmoType keys below were read from
the gun mods' installed files on 2026-10-17. **None of it has been seen in
game.**

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

**Left out on purpose.** Rimfire (.22, .22 LR): the priming is in the rim,
it is not reloaded. Grenades, rockets, arrows and bolts, flamethrower fuel,
machine-gun links, and GaelGunStore's AP and tracer variants (no firearm
uses them).

**What a pack does not cover.** The press and the spent cases know the
vanilla calibres only: an extension calibre is loaded by hand, and its
fired cases are not found. Its die sets are not loot.

## 3. Mods that change vanilla rounds

Rain's, GaelGunStore and Modern Firearms System redefine the vanilla round
items (weights, counts). The mod's recipes still make those items.
**Modern Firearms System makes `Base.Bullets38` a 6.8mm round**: beside it
the .38 Special recipes make MFS's 6.8mm. The game-start check says so
(`AC_Compat.ROUND_OVERRIDES`, a WARNING); nothing is changed.

## 4. Hot Brass

Beside Hot Brass (3610677934, `HBVCEFb42`) the spent cases add-on stands
down: Hot Brass ejects casings of its own. **Ammo Making: Hot Brass Casings**
(`AmmoMakingHotBrass`) resizes them at the die set exactly like spent
cases: two casings into one usable case, the resizing malus, no XP. Its
casings carry the brass of their case. The casing of each vanilla round is
Hot Brass's own table (its `SpentCasingPhysics/Init.lua`), written into
`AC_Calibres` as `hotBrassCasing`.

## 5. Translations

English names are generated with the scripts. Every other language is
derived from that language's own names of the template's items and recipes:
`python tools/derive_addon_translations.py` (`--check` fails when a file
is stale). Run it after `tests/write_recipes.lua`.

## 6. Adding a gun mod

1. Subscribe, read its `registries.lua` and ammo scripts.
2. One `AC_Calibres.define` per new round in `EXTENSIONS`, with
   `extension`, `template`, `round` and `ammoType`.
3. A feature in `AC_Features` (`mod` = the add-on's id) and a pack in
   `EXTENSION_PACKS` (`tests/render_addons.lua`); `incompatible` for any
   pack whose round ids mean another calibre.
4. `tests/write_recipes.lua`, `tools/derive_addon_translations.py`,
   `art/workshop/make_workshop_art.py` (a poster), `tools/build_release.py`
   (`MODS`), then the tests.

## 7. REQUIRES FUTURE IN-GAME VERIFICATION

- Each add-on loads beside its gun mod, and the game refuses an
  incompatible pair.
- One round per pack: made, stacking with found ones, fired by the gun mod's
  firearm.
- Hot Brass casings resized into a case.
- The MFS warning at game start.
