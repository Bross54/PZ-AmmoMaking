# Multiplayer: authority map and design

Status: **DESIGN ONLY. No networking code exists in the mod**: no
`sendClientCommand`, no `OnClientCommand`, no `ModData.transmit`. The mod is
single player. This document says where each system's state lives today,
who would have to own it on a server, and how each known duplication would
be closed. The mining part is worked out further in
`MULTIPLAYER_MINING.md`.

Nothing here has been run on a server. Vanilla facts are marked **FILE**
(installed 42.20.4 Lua), **JAR** or **INFERRED**.

## 1. How vanilla splits the work

- FILE `shared/Entity/TimedActions/ISHandcraftAction.lua:173-219`: a timed
  action's `perform()` runs on the client and in single player and does the
  work only when `not isClient()`; its `complete()` does the work when
  `isServer()`. The server performs the recipe, the client only shows it.
- FILE `shared/TimedActions/ISReloadWeaponAction.lua:514-516`: the round
  count is lowered only where `not isClient()`, then
  `syncHandWeaponFields(player, weapon)` sends the weapon's fields and its
  ModData to the owning client (JAR `SyncHandWeaponFieldsPacket`).
- FILE `server/ClientCommands.lua`: vanilla's own client requests arrive in
  `OnClientCommand` handlers, which change the world and call
  `object:transmitModData()`.
- Lua on the server is single threaded: a handler that checks and writes
  without yielding cannot be interleaved with another request (INFERRED;
  it is what makes vanilla's own handlers safe).

The rule that follows, for every system below: **the machine that decides
is the machine that changes the state, and that machine is the server.** A
client asks, shows, and never writes.

## 2. Authority map

Classes: **VANILLA** the engine already owns it on a server ·
**CLIENT-ONLY** it happens on the player's machine and concerns nobody else
· **WORLD MODDATA** shared state stored in the save · **NEEDS SERVER** it
changes shared or duplicable state on the client today · **UNKNOWN** the
files do not settle it.

| System | State it changes | Where that happens today | Class | On a server it must |
|---|---|---|---|---|
| Geology (concentrations, grades) | none: computed from the save's identity | each machine | **CLIENT-ONLY**, if every machine derives the same seed | use the server's world identity on every client (**UNKNOWN** whether a client sees the same identity; `AC_WorldData`) |
| Digging a sample | a new item with hidden geology in its ModData; shovel wear | the acting client (`AddItem`) | **NEEDS SERVER** | create the item on the server (`complete()`), which sends it to the client |
| Field and advanced assay | kit uses, the sample's ModData, XP | the acting client | **NEEDS SERVER** | a server command; uses and result decided there |
| Laboratory analyzer: place, pick up | a world object, an inventory item | disabled for clients | **NEEDS SERVER** | vanilla's build path already creates on the server (`ISBuildAction`); pickup needs a `complete()` |
| Laboratory analyzer: start, cancel, collect | object ModData, a sample removed and re-created, XP | whichever client opens the menu | **NEEDS SERVER** + **WORLD MODDATA** | server commands; `transmitModData()` after each change |
| Laboratory analyzer: time accounting | hours credited lazily, on interaction | whichever client looks | **NEEDS SERVER** | credit on the server only; a client reads |
| Mining | the depletion store, an ore item, XP, pickaxe wear | disabled for clients | **NEEDS SERVER** + **WORLD MODDATA** | `MULTIPLAYER_MINING.md` |
| Depletion store | global ModData | the machine that mines | **WORLD MODDATA** | exist on the server only; clients get a copy for their menus |
| Metallurgy, case stock, components, assembly | items in and out | vanilla `craftRecipe` | **VANILLA** | nothing: the server performs the recipe |
| Recipe XP (`OnCreate`) | perk XP | wherever `OnCreate` runs: the server | **UNKNOWN** | grant with the engine's `addXp(player, perk, amount)`, as vanilla's server Lua does (`ISBuildUtil.lua:107`); the single-player call is used today |
| Recipe level requirement | recipe scripts in memory | every machine, at boot and game start | **CLIENT-ONLY** per machine | run on the server and on every client (it already runs on both events) |
| Case and round quality | item ModData written in `OnCreate` | the server | **UNKNOWN** | reach the client: whether ModData set in `OnCreate` is sent with the new item is not established |
| Inspection | none: reads | the client | **CLIENT-ONLY** | nothing |
| Die-set loot | the loot tables in memory | every machine at world load | **VANILLA** once the server's tables hold the entries | nothing; on a client the tables are never rolled from |
| Brass recycling | items in and out, no XP | vanilla `craftRecipe` | **VANILLA** | nothing |
| Ammo boxes | – | vanilla's recipe | **VANILLA** | nothing |
| Save-data repairs | whatever the owning system stores | where that system reads | as the owner | only write on the server |
| Debug tools | anything | the client, `-debug` | **CLIENT-ONLY**, and unsafe on a server | be refused on a client, or be admin commands |
| *Reloading press (not built)* | a placed entity | – | **VANILLA** | nothing: a `CraftBench` entity is built, saved and synced by the engine |
| *Quality tally (not wired)* | ModData on a weapon or magazine | – | **NEEDS SERVER** | change only where vanilla changes the count (`not isClient()`); it then rides on `syncHandWeaponFields` |
| *Spent cases (not built)* | new items at the shot or the rack | – | **NEEDS SERVER** | spawn on the server only, once per shot id |

Six of the present systems are vanilla's and need nothing. Everything that
is the mod's own (sampling, assays, the analyzer, mining) needs the server.

## 3. The duplications, one by one

### 3.1 Two players mine the same reserve

Each client holds its own copy of the depletion store, so each gets the
whole reserve. **Closed by**: the store lives on the server; `mine` is a
request; the handler checks the remaining reserve and records the
extraction in one uninterrupted call; the reply carries the server's
remaining count. Two requests for the last unit: the first gets the ore,
the second gets `no_ore`. Never decrement on the client and reconcile
later. (`MULTIPLAYER_MINING.md`, worked through.)

### 3.2 Two players collect one analyzer's sample

Collect is a menu click that creates a sample item and clears the
analyzer's stored sample. On two clients both clicks see `ready` and both
create a sample. **Closed by**: `collect` is a request; the handler reads
`storedSample` from the object's server-side ModData, clears it, creates
the item for the requester and calls `transmitModData()`, all in one call.
The second request finds the analyzer empty and is refused with the
existing `empty` reason. The same shape closes **start** (two samples into
one analyzer: the second is refused `busy`, and its sample is never
removed) and **cancel** against **collect** (whichever arrives first wins;
the other finds the state changed).

XP for the collection is granted in the same handler, to the requester,
once.

### 3.3 One player, two analyzers' worth of time

Time is credited when someone looks. With two clients looking, each
credits the hours since *its own* last look. **Closed by**: only the server
credits, with the server's clock; the stored `labLastUpdateAt` is the
server's. A client's menu shows what the server last transmitted.

### 3.4 A sample dug twice, or assayed for free

A client that creates the sample itself can create it without the dig, and
a client that decrements its own kit can decline to. **Closed by**: the dig
action's `complete()` creates the sample on the server from the server's
geology; an assay is a request that names the sample and the kit by item
id, and the server checks both are in the requester's inventory, takes the
use and writes the result.

### 3.5 Duplicate spent cases

`OnWeaponSwingHitPoint` reaches the shooter's client and, for aimed
firearms, the server (JAR `PlayerHit.attack`, once per shot id). A listener
that spawns a case wherever it runs spawns two. **Closed by**: spawn only
where `not isClient()`, exactly where vanilla lowers the round count. The
revolver's cases come out of `ejectSpentRounds`, which both actions call
from `start()` and `serverStart()`: the wrapper acts in the server call
only. How often the event fires per round in automatic fire is not known
(`SPENT_CASE_RESEARCH.md` 6); the tally's own count is the guard, because
it yields exactly as many handloaded cases as handloaded rounds were
loaded, however often the event fires.

### 3.6 The quality tally out of step between machines

If a client changes its copy of the record, the next sync overwrites it or,
worse, does not. **Closed by**: the record is written only on the server,
beside vanilla's own count, and travels in the weapon's ModData on the
packet vanilla already sends. `consume` uses no random number, so even a
client that predicts the result predicts the same one.

### 3.7 Press placement

Nothing to close. Building, picking up and using a `CraftBench` entity are
vanilla actions with vanilla authority; the press adds a tag and recipes.
The one mod-specific point is the XP grant in `OnCreate` (3.8).

### 3.8 XP granted twice, or not at all

`OnCreate` runs where the recipe is performed: the server. The mod grants
XP there with the single-player call. Whether that reaches the client's
character is **UNKNOWN**; if `OnCreate` also ran on the client the grant
would double. **Closed by**: grant only where `not isClient()`, with
vanilla's server-side helper.

### 3.9 World ModData that never arrives

A client that never receives the depletion store shows every tile as
untouched (a display fault, not a duplication, once extraction is the
server's). **Closed by**: `ModData.transmit(key)` from the server after a
change, and a request for it when a client joins (`OnInitGlobalModData` on
the client, `ModData.request`; both are in the jar, and vanilla's foraging
server calls `ModData.transmit`).

## 4. Order of work, when multiplayer is taken up

1. Seeds: confirm every machine derives the server's geology (one test on
   a server; everything else depends on it).
2. Mining, as designed: one command, one handler, one transmit.
3. The analyzer: three commands (start, cancel, collect) and server-side
   time.
4. Sampling and assays: `complete()` on the dig action, one command per
   assay.
5. `OnCreate`: server-side XP, and whether quality ModData reaches the
   client.
6. Only then anything on firearms.

Each step is small because each system already has one function that
changes state (`AC_Mining.extract`, `AC_LaboratoryAnalyzer.startAssay` /
`cancelAssay` / `collectSample`, `AC_GeologySampling.createSample` /
`analyzeSample`), called from menus and actions that only ask. Moving the
call to the server and replacing it with a request is the whole change.

## 5. REQUIRES FUTURE IN-GAME VERIFICATION (on a server)

- That a client and the server derive the same save identity and so the
  same geology.
- Where `OnCreate` runs, and whether XP and item ModData set there reach
  the client.
- That `OnPreDistributionMerge` runs on a dedicated server before its loot
  tables are parsed.
- That sampling and assays, which are **not** switched off for clients
  today, do something sensible on one. They create and change items on the
  client; until step 4 they should be considered broken in multiplayer.
  Mining and analyzer placement are switched off there.
