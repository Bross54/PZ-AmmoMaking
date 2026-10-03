# Ammunition quality at run time: where it could live

Status: **IMPLEMENTED, EXPERIMENTAL, OFF BY DEFAULT, NEVER RUN IN THE
GAME.** The tally of section 4 (`AC_QualityTally.lua`, section 8) is wired
to vanilla's reload functions by `AC_QualityCarrier.lua` (section 9), behind
the sandbox option *Track ammunition quality in magazines and firearms*,
single player only. With the option off nothing is wrapped, listened to or
stored. It has no effect on firing. An effect is written
(`AC_QualityEffects.lua`, 9.4) and locked: no setting switches it on.
Sections 1 to 7 are the research as it was written before the wiring.

Today a handloaded round carries its casing quality in the loose item's
ModData (`AC_CaseQuality`). The record is lost the moment vanilla turns the
round into a count: at loading and at boxing (`LOOT_AND_RECYCLING.md` 3.1).
This document compares the places a quality could live so that, one day, it
can reach the shot.

Vanilla facts are marked **FILE**, **JAR** or **INFERRED** and were read
from the installed Build 42.20.4. They are set out in full in
`SPENT_CASE_RESEARCH.md`, section 1.

## 1. What vanilla keeps, and where it throws things away

| Fact | Evidence |
|---|---|
| An item's ammunition state is `ammoType`, `maxAmmo`, `currentAmmoCount`. A firearm adds `containsClip`, `roundChambered`, `isJammed` (saved) and the spent state (not saved) | JAR `InventoryItem`, `HandWeapon.save` / `load` |
| An item's ModData is saved, for firearms and magazines alike | JAR `InventoryItem.save`: the table is written when non-empty; `HandWeapon.save` calls it |
| Items never merge: a container holds individual objects; the inventory pane only groups rows by display name | JAR `InventoryItem.CanStack` returns false, `ItemContainer.AddItem`; FILE `ISInventoryPane.lua:2090-2134` |
| Loading a round **removes the round item** and adds one to a counter | FILE `ISLoadBulletsInMagazine.lua:128-131` (`RemoveOneOf(itemKey, true)`), `ISReloadWeaponAction.lua:239-244` |
| Which round is taken is not chosen by ModData | FILE `getSomeType(itemKey, count)`, `RemoveOneOf(itemKey, true)` |
| Unloading **creates new round items** | FILE `ISUnloadBulletsFromMagazine.lua:114-118`, `ISUnloadBulletsFromFirearm.lua:74-85`, `ISRackFirearm.lua:82-87` (`instanceItem(itemKey)`) |
| **Inserting a magazine destroys the magazine item**; the gun keeps a boolean and the count | FILE `ISInsertMagazine.lua:44-48` |
| **Ejecting creates a new magazine item** and copies the count onto it | FILE `ISEjectMagazine.lua:33-42` (`instanceItem(self.gun:getMagazineType())`) |
| On a server, weapon ModData reaches the owning client with every `syncHandWeaponFields`; magazine ModData travels with `syncItemFields` | JAR `SyncHandWeaponFieldsPacket`, `SyncItemFieldsPacket` |
| All of these state changes run where `not isClient()` | FILE, each action |

Two consequences shape everything below:

- **A magazine is not one object through its life.** ModData written on a
  magazine item is gone when the magazine is inserted, and the magazine
  that comes out is a different item. Anything on a magazine has to be
  copied to the gun on insert and back on eject, by the mod.
- **Nothing vanilla moves ModData between round, magazine and gun.** Any
  carrier means wrapping the seven functions where rounds change place.

The touch points:

| Function | What moves | Needed by |
|---|---|---|
| `ISLoadBulletsInMagazine:animEvent` (`:128`) | round → magazine | magazine guns |
| `ISUnloadBulletsFromMagazine:animEvent` (`:113`) | magazine → round | magazine guns |
| `ISInsertMagazine:loadAmmo` (`:42`) | magazine → gun | magazine guns |
| `ISEjectMagazine:unloadAmmo` (`:31`) | gun → magazine | magazine guns |
| `ISReloadWeaponAction:loadAmmo` (`:235`) | round → gun | revolvers, shotguns, tube and internal-magazine rifles |
| `ISUnloadBulletsFromFirearm:animEvent` (`:74`) | gun → round | the same |
| `ISRackFirearm:removeBullet` (`:82`) | chamber → round | every gun that can be racked |
| `Events.OnWeaponSwingHitPoint` | a round is fired | all; additive, no wrap |

## 2. The candidate carriers

### A. ModData on the magazine

The per-magazine record: what the rounds in it are.

- Save: yes. Reload: only if copied to the gun at insert and back at
  eject.
- Fails alone: revolvers, shotguns and internal-magazine rifles have no
  magazine item at all (thirteen of the twenty vanilla firearms).

### B. ModData on the weapon

The per-gun record of what is loaded, chamber included.

- Save: yes. Server to client: carried by vanilla's own sync.
- Works for every firearm. For a magazine gun it is the record while the
  magazine is in, and has to be handed to the magazine item on eject.

### C. A parallel queue, one entry per round

An ordered list beside the count (`{ 82, 82, 71, "factory", … }`), on the
magazine or the weapon; the shot reads the entry on top.

- Exact: each round keeps its own quality through load, fire and unload.
- Needs every touch point to push or pop in step with vanilla's count, in
  the right order (a magazine is last in, first out; a revolver cylinder
  and a tube are not obviously either).
- One missed path, by a vanilla change or another mod's reload action, and
  the list and the count disagree. It then needs a repair rule anyway, and
  the repair rule is option D.
- A partial unload must decide which entries leave.

### D. An aggregate per container

Two numbers beside the count: how many of the loaded rounds are handloaded
and the sum of their qualities (`{ n = 9, q = 702 }`). Factory rounds are
the rest of the count, at a fixed nominal quality.

- Loading a handloaded round: `n + 1`, `q + quality`. A factory round:
  nothing.
- A shot, an unload or a rack-out removes one round "of the mix": the
  share `n / count` says whether it was a handloaded one, and it leaves
  with the mean `q / n`.
- Order does not exist, so no path can get it wrong. If the count and the
  tally ever disagree, clamp `n` to the count and scale `q`: the record
  degrades toward "factory", it never invents quality.
- Loses the individual round: one fine round among poor ones is averaged.

### E. State derived at load time

Nothing stored per round: when a magazine or gun is loaded, a single figure
is fixed (say the mean quality at that moment) and every shot until the
next load uses it, with a deterministic draw from a counter in the same
ModData.

- Cheapest to keep right; it is D with the tally frozen between loads.
- Wrong after a partial unload or a top-up unless recomputed, which makes
  it D again.

## 3. Comparison

| | A. Magazine ModData | B. Weapon ModData | C. Queue per round | D. Aggregate | E. Derived at load |
|---|---|---|---|---|---|
| Survives save and load | yes | yes | yes (a list in ModData) | yes | yes |
| Survives insert and eject | only with a copy in both directions | is the gun's own | only with a copy of the whole list | only with a copy of two numbers | only with a copy |
| Reload (loose rounds) | – | wrap one function | push per round, in order | add per round | recompute |
| Partial magazine unload | n/a | n/a | must choose which entries | remove at the mean | stale |
| Mixing factory and handloaded | – | – | exact | exact in number, averaged in quality | averaged |
| Covers guns without a magazine | **no** | yes | on the weapon | on the weapon | on the weapon |
| Multiplayer later | `syncItemFields` | `syncHandWeaponFields` already carries it | the same, but a list per sync | two numbers per sync | one number |
| Vanilla functions wrapped | 4 | 3 | 7 | 7 | 7 |
| Breaks when a path is missed | record lost | record lost | **list and count diverge** | clamps toward factory | stale until next load |
| Duplication risk | none (no item) | none | a repair that pads the list could invent good rounds | none: the clamp only removes | none |
| Complexity | low, incomplete | low, incomplete | high | moderate | low, weak |

A and B are **places**; C, D and E are **shapes**. The real choice is a
shape, stored on B while the rounds are in a gun and on A while they are in
a loose magazine.

By firearm class:

| Class | Where the record sits | Touch points |
|---|---|---|
| Magazine-fed (7 guns) | the magazine item while it is out, the weapon while it is in; copied at insert and eject. The chambered round belongs to the weapon | all seven |
| Revolvers (3) | the weapon | loose-round reload, unload from firearm, the shot |
| Shotguns and internal-magazine rifles (10) | the weapon | the same three, and the rack (`removeBullet`) for pump, bolt and lever |

## 4. Recommendation

**An aggregate tally (D), kept on the weapon while rounds are in a gun and
on the magazine item while they are in a loose magazine.**

```text
one record per weapon or loose magazine (the ModData key is not chosen yet)
  version     layout of the record
  count       rounds the record describes
  handloaded  handloaded rounds among them     0 .. count
  qualitySum  sum of their casing qualities    handloaded * 1 .. handloaded * 100
  phase       0 to below 1: how far the record is towards handing out its
              next handloaded round (section 7); bookkeeping, not provenance
factory rounds = count - handloaded, at a fixed nominal quality
```

`count` repeats what vanilla already keeps (`getCurrentAmmoCount()`), on
purpose. Vanilla's number is the authority; the copy is how the record
notices that it was not told about something. Without it, a gun that lost
six of ten rounds through another mod's action would still claim its five
handloaded rounds among the four that are left. With it, `reconcile()` sees
ten become four and takes the handloaded share down with the rest
(section 8).

Why this one:

- **It cannot be wrong in a way that helps the player.** Every repair
  moves the record toward "factory". A queue that has lost step has to be
  padded or cut, and both are guesses.
- **It is the same code for every firearm.** A revolver and a magazine
  rifle differ only in which item holds the two numbers.
- **It is small enough to verify offline.** The tally is pure arithmetic,
  testable exactly as `AC_CaseQuality` is, before any vanilla function is
  wrapped. That part is now done (section 8).
- **It fits what the mod records.** The only quality that exists is one
  number per case; there is nothing per round worth an ordered list.
- **Multiplayer has a path.** Two numbers ride on packets vanilla already
  sends, and every change happens where vanilla's own change happens
  (`not isClient()`).

What it gives up: a single fine round is averaged with the rest of the
magazine. If per-shot identity ever matters, the queue can be added on top
with the aggregate as its repair rule.

Rules a future implementation must keep:

1. `0 <= handloaded <= count` and `handloaded <= qualitySum <= handloaded *
   100` after every operation; a record that breaks them is read as all
   factory, never trusted and never clamped into something plausible (the
   save-data rules of `DEVELOPMENT.md`).
2. The tally is written only where vanilla writes the count, and only
   after vanilla's own change has happened.
3. Unloading hands back round items whose casing quality is the mean, and
   only for the handloaded share; the rest are plain factory rounds.
4. A wrapped vanilla function calls the original first and never changes
   its arguments or result. If the original's shape is not what was
   expected, the wrapper does nothing and the game-start check says so.
5. No effect on firing is attached until the tally has been seen to stay
   in step in game, across save and load, for one gun of each class.

## 5. What an effect would build on, later

Not designed here, recorded so the carrier is not chosen in the dark:
vanilla already has a jam mechanic (JAR `HandWeapon.checkJam`: a chance from
the script's `JamGunChance`, the sandbox multiplier, condition and skill;
`isJammed` is saved and networked; `ISRackFirearm` clears it). A quality
effect would most plausibly raise that chance for a low mean quality, at the
shot, rather than add a mechanic of its own. That is a later stage and a
gameplay decision.

## 6. REQUIRES FUTURE IN-GAME VERIFICATION

- That ModData written on a firearm survives save and load and reaches the
  client on a server, as the bytecode says.
- That the seven functions can be wrapped by table-field replacement from a
  mod (they are plain fields of global tables in shared Lua).
- The order in which a magazine, a revolver and a tube hand rounds back, if
  a queue is ever wanted.
- That no vanilla path changes `currentAmmoCount` outside the functions
  listed in section 1.
- That every path which changes `currentAmmoCount` is one the wrapped
  functions see. `AC_QualityTally.reconcile` makes a missed path harmless
  (the record follows the count and loses handloaded rounds, never gains
  them), but how often it has to act can only be seen in game.

## 7. Mixed ammunition: which round is next?

A magazine can hold factory rounds, handloaded rounds, and handloaded
rounds of different quality. A tally knows the mix and not the order, so
"is the round being fired a handloaded one, and how good" has no true
answer. Five ways to give one:

| | 1. Probability | 2. FIFO queue | 3. Deterministic proportion | 4. Factory first | 5. Effect from the mix |
|---|---|---|---|---|---|
| Rule | each shot is handloaded with chance `handloaded / count` | the record is an ordered list; the shot pops it | the kinds leave evenly spread: a running fraction (the phase) gains the handloaded share with every round, and a handloaded round leaves each time it reaches 1 | factory rounds leave until only handloaded ones are left | a shot has no kind: an effect is computed from the whole load's mean |
| State | the tally | one entry per round | the tally, and one fraction | the tally | the tally |
| Random numbers | one per shot; client and server must draw the same, or only the server draws | none | none | none | none (the effect may still roll) |
| Exact over a whole magazine | only on average: ten shots from a half-and-half magazine can remove seven handloaded rounds from the record | yes | yes: firing every round removes exactly the handloaded rounds and exactly the quality sum | yes | nothing is removed by kind, so the tally needs rule 3 or 4 for its counts anyway |
| A path the mod missed | tally repairs by clamping | **list and count disagree**; padding it invents rounds, cutting it guesses | tally repairs toward factory | the same | the same |
| Partial unload | a draw per round | must decide which entries leave | the mix, evenly | hands out every factory round first: a magazine can be stripped down to "pure handloaded" for free | as rule 3 |
| What the player can exploit | unload and reload until the draw suits, if the kind is ever visible | nothing | nothing: there is no choice to make | ordering: top a magazine up with one factory round and the next shot is always that one | nothing |
| Complexity | low, plus a synchronised random source | high (seven wrapped functions, each keeping an order right) | low | lowest | low |

**Chosen: 3 for the record, 5 for any future effect.**

- The record changes by **deterministic proportion** (`AC_QualityTally
  .split`). Of a magazine that is a third handloaded, every third round
  that leaves is handloaded; one handloaded round among nine factory rounds
  leaves fifth. At every point of every magazine up to thirty rounds the
  handloaded rounds handed out are within one of their fair share (tested).
  No random number, so two machines holding the same record always agree,
  and no order, so nothing can get an order wrong.
- That takes one more number than the counts, the **phase**. A rule that
  looked only at `handloaded` and `count` cannot spread anything: it has to
  hand out the majority kind every time until the mix is half and half,
  because it cannot remember what it handed out last. The first version of
  the module did exactly that (ten handloaded rounds among thirty came out
  after eleven factory rounds) while this document said "evenly"; an
  independent review of the code found the difference. The phase is
  bookkeeping: damage to it loses the record like damage to any field, but
  it carries no quality and no provenance.
- Rounds leave one at a time inside `split`, so taking five rounds at once
  and taking one round five times are the same thing in every number
  (tested for every mix and every size up to twenty-four rounds).
- A future effect should read **the mix** (the mean quality and the
  handloaded share of what is loaded), not the identity of one round. The
  record's notion of "this round was a handloaded one" is bookkeeping, not
  a fact about the round in the chamber.
- A queue stays possible later, on top: the tally is then its repair rule.

### 7.1 What averaging costs, and the rule it puts on effects

A round that leaves the record takes the **mean** quality. Two handloaded
rounds of 90 and 10, loaded and unloaded again, come back as two rounds of
50. The sum is conserved, the individual rounds are not.

That is harmless for an effect that is **linear in quality**: the total
effect over the load depends only on `qualitySum` and `handloaded`, which
loading and unloading never change. It is an exploit for an effect with a
threshold, or any curve that punishes a bad round more than it rewards a
good one ("a misfire below 30"): one loads the bad round together with good
ones, unloads, and the bad round is gone.

**Rule for any future effect: it must be a linear function of quality, or
be computed from the load's mean for every shot of that load.** Then
averaging is neutral, and there is nothing to gain by mixing and unmixing.
If per-round identity ever has to matter (a dud that is a property of one
cartridge), the aggregate is the wrong carrier and the queue of section 2
is needed.

Factory rounds are not averaged into anything: a handloaded round stays a
handloaded round, a factory round stays a factory round, and only the
counts and the one sum move.

### 7.2 Doubt resolves toward factory

Whenever the record and the game disagree, or the record contradicts
itself, the answer moves toward "factory, no effect":

| Situation | Result |
|---|---|
| The record is damaged (a word, NaN, more handloaded rounds than rounds, a quality sum the rounds cannot hold) | all factory; the count is kept if it is usable |
| A round with no usable quality is loaded | a factory round |
| The game holds fewer rounds than the record | the handloaded share shrinks in proportion, rounded **down**, and the quality sum with it (the mean never rises) |
| The game holds more rounds than the record | the extra rounds are factory rounds |
| The record was written by a later release (`version` higher) | read as "nothing known" and reported as `newer`; every function that would return a record hands that record back **as it is**, never a record of this layout made from it, so a caller that stores what it gets back overwrites nothing |
| The version is a broken number (1e300) | damage, not a later release: all factory |

A damaged 900 on five rounds is not clamped to 500. A record that is wrong
in one field is not evidence for the others, and clamping would hand out
the best possible ammunition for damaged data.

## 8. What is implemented: `AC_QualityTally.lua`

Pure functions on plain tables. Each returns new records and changes none
of its arguments.

| Function | What it is for |
|---|---|
| `empty(count)` | a record of factory rounds |
| `check(value)` | the list of what is wrong with a record; read only |
| `repair(value)` | any value to a sound record, and `ok` / `repaired` / `newer` |
| `reconcile(value, actualCount)` | the record brought into step with the game's own count |
| `addFactory(value, rounds)`, `addHandloaded(value, quality)` | a round is loaded |
| `split(value, rounds)` | rounds leave: what left, and what stayed |
| `merge(a, b)` | a magazine into a gun with a round chambered |
| `transfer(from, to, rounds)` | split and merge, for insert and eject |
| `consume(value)` | one shot: what stayed, and what the round was |
| `unload(value, rounds)`, `qualities(value)` | rounds back to loose items: how many factory rounds, and a quality for each handloaded one, adding up to the sum exactly |
| `getFactory`, `getMeanQuality`, `getHandloadedShare` | derived values |

How the touch points of section 1 map onto them (the wiring is section 9;
it reaches the same results by observing counts instead of naming the
step):

| Vanilla step | Tally |
|---|---|
| a round into a magazine or gun | `addHandloaded(record, AC_CaseQuality.getRoundQuality(round))` |
| a magazine into a gun | `merge(gun, magazine)` |
| a magazine out of a gun | `transfer(gun, nil, the magazine's count)`; the chambered round stays |
| rounds unloaded, or racked out | `unload(record, n)`, then `AC_CaseQuality` writes each quality on a new round item |
| a shot | `consume(record)` |
| before any of them | `reconcile(record, live rounds)` |

"Live rounds" is `getCurrentAmmoCount()` plus one when `isRoundChambered()`:
what the gun holds. The bare count falls when a round is chambered, not
when one is fired, so it is the wrong number to follow for any gun with a
chamber (`SPENT_CASE_RESEARCH.md` 1.6). A magazine item has no chamber; its
count is its live rounds.

The suite proves, without the game:

- every result obeys the rules of section 4, for sound and for damaged
  input (each field damaged fifteen ways, through every function);
- `split` then `merge`, and `transfer`, conserve rounds, handloaded rounds
  and quality **exactly**; firing a load one round at a time hands out
  exactly its rounds, its handloaded rounds and its quality sum, for every
  mix of up to thirty rounds;
- 16,000 random operations over three records and a pool of loose rounds,
  including counts that move unseen and fields that are overwritten: one
  ledger over everything that exists and everything that was fired, in
  which only loading a round may add;
- `reconcile` and `repair` never increase the handloaded count, the
  quality sum or the mean;
- the rounds leave evenly (within one of the fair share at every point),
  and one at a time or several at once take the same rounds;
- a later release's record comes back untouched from every function, and
  a record transferred into itself is unchanged;
- the file registers no event and touches no ModData and no engine
  object. Only `AC_QualityCarrier.lua` refers to it, and only behind the
  feature switch; a test fails if any other file does.

What it does not prove is everything in section 6.

## 9. What is implemented: the wiring (`AC_QualityCarrier.lua`)

Feature `qualityTracking` of `AC_Features.lua`: experimental, a sandbox
option of the save, false by default, refused in multiplayer. Installed at
`OnGameStart` and only when the feature is on.

### 9.1 Carrier and rule

Carrier D of section 2: one aggregate record (`count`, `handloaded`,
`qualitySum`, a version) in the ModData key `AmmoMakingTally` of each loose
magazine and each firearm, declared in `AC_SaveData.SCHEMA`. A record with
no handloaded round is not stored at all: a gun that has only ever held
factory rounds carries no data of the mod.

The wrappers do **not** re-implement vanilla's steps and do not trust
their own idea of them. Each one observes:

| When | What |
|---|---|
| before | the live rounds of the magazine or gun (vanilla's count, plus the chambered round); the loose rounds of that calibre the character carries, with their qualities |
| call | vanilla's function, once, with the arguments it was given; its result is handed on |
| after | the same two observations |

and the record follows the difference:

| Difference | Meaning | Record |
|---|---|---|
| the container holds more | rounds went in | as many as left the inventory carrying a quality are handloaded, with those qualities; the rest are factory |
| the container holds fewer, loose rounds appeared | unloaded | the record hands out its mix (`AC_QualityTally.unload`); the new loose rounds are given the qualities |
| the container holds fewer, nothing appeared | fired, or lost | the record gives up that many at its mix |

So the record cannot get ahead of vanilla: it only describes rounds
vanilla says are there. A count that moved unseen (another mod's reload
action, a debug command) is found the next time the item is looked at and
resolved toward factory (`reconcile`). No path creates a round, a
handloaded round or quality.

### 9.2 The seven functions and the shot

| Vanilla function | Step |
|---|---|
| `ISLoadBulletsInMagazine:animEvent` | a round into a loose magazine |
| `ISUnloadBulletsFromMagazine:animEvent` | a round out of a loose magazine |
| `ISInsertMagazine:loadAmmo` | magazine into the gun: the item is destroyed, its record merges into the gun's |
| `ISEjectMagazine:unloadAmmo` | magazine out: a new item, the record is split off; a chambered round stays |
| `ISReloadWeaponAction:loadAmmo` | a round into a gun without a magazine |
| `ISUnloadBulletsFromFirearm:animEvent` | rounds out of such a gun |
| `ISRackFirearm:removeBullet` | a live round racked out |

Each is replaced by a wrapper stored in the same table field; the original
is kept and called. The shot is a listener on `OnWeaponSwingHitPoint`,
which runs after vanilla's own handler has taken the round.
`tools/pz_compat.py` keeps a digest of each function's body: a game update
that rewrites one is reported before the mod is trusted on it.

Every step of the mod's own is `pcall`-guarded and logs once; a failure
leaves vanilla's action exactly as it was and the record to be reconciled
later.

### 9.3 What the suite proves, and what it cannot

Against a model of vanilla's firearm Lua (`tests/firearm_model.lua`: seven
firearms covering magazine-fed, chambered, revolver, break-action, pump,
bolt and lever guns, checked against vanilla's scripts by the drift tool):

- loading, inserting, racking, firing, ejecting and unloading keep rounds,
  handloaded rounds and the quality sum exactly, for each firearm;
- 14,000 random operations (four seeds, seven firearms, 500 steps each)
  with one ledger over everything that exists and everything fired: no
  operation gains a handloaded round or quality;
- a count changed behind the wrappers resolves toward factory;
- a wrapper whose own step raises still performs vanilla's action and
  returns vanilla's result;
- with the option off, or on a multiplayer client, no function is replaced
  and no listener added.

The model is the mod's reading of vanilla's Lua, not the game. Section 6
stays open in full, and `docs/INGAME_VALIDATION.md` 20 and 21 are the
session that closes it.

### 9.4 The effect, locked: `AC_QualityEffects.lua`

Feature `qualityEffects`: **disabled**. It has no sandbox option and no
add-on; `AC_Features` answers "locked" whatever is set, and `afterShot`
returns before it looks at anything.

What is written, for the day tracking has been seen to stay in step and a
decision is made that quality should matter:

```text
extra jam % = maximumExtraJamPercent * (handloaded * 100 - qualitySum) / (99 * rounds in the load)
```

Linear in the quality sum, as 7.1 requires: mixing and unmixing rounds
changes nothing in total. Factory rounds and quality-100 handloads add
nothing; a load of quality-1 handloads adds the maximum (4 percentage
points, a tunable). It sets vanilla's own jam state
(`HandWeapon:setJammed(true)`), never applies to a firearm whose
`JamGunChance` is 0, and touches no damage, range or accuracy. Unlocking it
is one word in `AC_Features.DEFINITIONS`; that it behaves like vanilla's
own jam is **REQUIRES FUTURE IN-GAME VERIFICATION**.

### 9.5 Inspection

*Inspect Loaded Ammunition* on a magazine or firearm reads the record
(never writes it): how many rounds, how many handloaded, their mean
quality as a word, and the figure itself at a high enough level. Without
tracking it says only what vanilla knows: the count.
