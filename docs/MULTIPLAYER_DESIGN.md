# Multiplayer: authority map and design

Status: **BUILT, EXPERIMENTAL, OFF BY DEFAULT. Never run on a server.**
Since 0.11.0 the server authority of section 6 exists
(`shared/AC_Authority.lua`, `client/AC_AuthorityClient.lua`) behind the
feature `serverAuthority`, a sandbox option of the save
(`AmmoMaking.ServerAuthority`, default off). Off, everything is as it was:
every system that changes items or world state from Lua is **refused on a
multiplayer client** (section 2.1), so nothing happens there by accident.
On, a client asks and the server checks and performs: digging a sample,
the field and advanced assays, the laboratory analyzer (place, start,
cancel, collect, pick up) and mining. **Single player is not touched**
either way (section 6.4). This document says where each system's state
lives, who owns it on a server, and how each known duplication is closed.
The mining part is worked out further in `MULTIPLAYER_MINING.md`.

Nothing here has been run on a server. Vanilla facts are marked **FILE**
(installed 42.20.4 Lua), **JAR** or **INFERRED**.

## 1. How vanilla splits the work

- FILE `shared/Entity/TimedActions/ISHandcraftAction.lua:173-219`: a timed
  action's `perform()` runs on the client and in single player and does the
  work only when `not isClient()`; its `complete()` does the work when
  `isServer()`. The server performs the recipe, the client only shows it.
- JAR `LuaTimedActionNew.<init>`: a Lua timed action whose class has a
  `complete` is synchronised by the engine (`useCustomRemoteTimedActionSync`
  is false); its `start()` then calls `ActionManager.createNetTimedAction`.
  JAR `NetTimedAction.set`: what is sent is, for each parameter of the
  class's `new()` after `self`, the action's field **of that name**
  (`Prototype.locvars`), nil as `PZNetKahluaNull`. JAR `NetTimedAction.parse`:
  the server rebuilds the action with `<Type>.new(<Type>, those values...)`;
  `PZNetKahluaTableImpl` carries numbers, strings, booleans, tables,
  `IsoPlayer`, `InventoryItem`, `IsoObject` and `IsoGridSquare` (the square
  is looked up in `ServerMap`). JAR `NetTimedAction.perform`: when the
  action's duration (its own `getDuration()`, through `adjustMaxTime`) is
  over, the server calls `complete()`. JAR `NetTimedAction.isValid`
  returns false and names no Lua function: **the server never calls the
  action's `isValid()`**, so `complete()` must check everything itself.
- JAR `IsoGameCharacter` (action update): when an action finishes, the
  engine calls `perform()` and then, when it is not a client, `complete()`.
  **In single player both run, in that order.**
- FILE `shared/TimedActions/ISReloadWeaponAction.lua:514-516`: the round
  count is lowered only where `not isClient()`, then
  `syncHandWeaponFields(player, weapon)` sends the weapon's fields and its
  ModData to the owning client (JAR `SyncHandWeaponFieldsPacket`).
- FILE `server/ClientCommands.lua`: vanilla's own client requests arrive in
  `OnClientCommand(module, command, player, args)` handlers, which change
  the world and call `object:transmitModData()`. FILE
  `client/ServerCommands.lua`: answers arrive in
  `OnServerCommand(module, command, args)`. JAR `LuaManager.GlobalObject`:
  `sendClientCommand(IsoPlayer, String, String, KahluaTable)` (throws on a
  server; in single player it goes to the same machine's server Lua),
  `sendServerCommand(IsoPlayer, String, String, KahluaTable)` (does nothing
  except on a server).
- FILE `shared/TimedActions/*.lua` (`ISRemoveTrapAction`,
  `ISHutchGrabEgg`, `ISChangeFishingRodEquip` ...): a server-side
  `complete()` adds an item with `AddItem` then
  `sendAddItemToContainer(container, item)`, removes one with `Remove` and
  `sendRemoveItemFromContainer`, and after changing an item calls
  `syncItemModData(player, item)` / `syncItemFields(player, item)` (JAR
  `SyncItemFieldsPacket` carries condition, name, custom name and more).
  XP is `addXp(player, perk, amount)`: JAR, on a server
  `GameServer.addXp`, elsewhere the player's own `AddXP`.
- JAR `IsoGridSquare.AddWorldInventoryItem(InventoryItem, float, float,
  float)` passes `transmit = true`, and on a server sends the new world
  item to the clients (`transmitCompleteItemToClients`).
- JAR `GlobalModData.transmit` / `request` and `GlobalModDataPacket.parse`:
  `ModData.transmit(key)` sends the table, `ModData.request(key)` asks the
  server for it, and the receiving side only gets the event
  `OnReceiveGlobalModData(key, table or false)`: **the engine stores
  nothing**. A client keeps the table with `ModData.add(key, table)`; a
  server that does not listen to the event cannot be overwritten by a
  client that transmits.
- JAR `BuildAction.write` / `parse`, FILE `shared/ActionManager.lua`
  (`Actions.build`): a building object (the analyzer's placement cursor)
  travels the same way as a timed action, rebuilt from the fields named
  like its `new()`'s parameters; only for `TrapBO` is the argument
  `player` replaced with the `IsoPlayer`. The server then calls
  `create(x, y, z, north, sprite)`.
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

"With authority" is the switch `serverAuthority` on (section 6).

| System | State it changes | Where that happens | Class | On a server |
|---|---|---|---|---|
| Geology (concentrations, grades) | none: computed from the save's identity | each machine | **CLIENT-ONLY**, if every machine derives the same seed | with authority, every decision that reads geology (the sample's hidden values, the reserve) is taken on the server; a client's own seed only feeds its debug readouts (**UNKNOWN** whether a client sees the same identity; `AC_WorldData`) |
| Digging a sample | a new item with hidden geology in its ModData; shovel wear | single player; with authority the server, in the dig action's `complete()` | **NEEDS SERVER**: built | the server creates the item from its own geology, `sendAddItemToContainer`, shovel synced |
| Field and advanced assay | kit uses, the sample's ModData, XP | single player; with authority the command `assay` | **NEEDS SERVER**: built | the server checks both items are the requester's, takes the use, writes the result, grants XP, syncs both items |
| Laboratory analyzer: place, pick up | a world object, an inventory item | single player; with authority vanilla's build action (place) and the pickup action's `complete()` | **NEEDS SERVER**: built | placement: the server rebuilds the cursor and `create()` checks the switch and the distance; pickup: `complete()` |
| Laboratory analyzer: start, cancel, collect | object ModData, a sample removed and re-created, XP | single player; with authority the commands `labStart`, `labCancel`, `labCollect` | **NEEDS SERVER** + **WORLD MODDATA**: built | the server changes the placed object's ModData and calls `transmitModData()` after each change |
| Laboratory analyzer: time accounting | hours credited lazily, on interaction | whichever machine looks | **NEEDS SERVER**: built for the commands | the server credits at each command with its own clock; a client's *Check* credits its own copy only, which the next transmit replaces |
| Mining | the depletion store, an ore item, XP, pickaxe wear | single player; with authority the mining action's `complete()` | **NEEDS SERVER** + **WORLD MODDATA**: built | `MULTIPLAYER_MINING.md` |
| Depletion store | global ModData | the machine that mines | **WORLD MODDATA**: built | exists on the server; transmitted after every extraction; a client keeps the copy it receives for its menus |
| Metallurgy, case stock, components, assembly | items in and out | vanilla `craftRecipe` | **VANILLA** | nothing: the server performs the recipe |
| Recipe XP (`OnCreate`) | perk XP | wherever `OnCreate` runs: the server | **UNKNOWN** | with authority, `AmmoMakingSkill.addXP` grants through vanilla's `addXp` on a server; without it, the single-player call as before |
| Recipe level requirement | recipe scripts in memory | every machine, at boot and game start | **CLIENT-ONLY** per machine | run on the server and on every client (it already runs on both events) |
| Case and round quality | item ModData written in `OnCreate` | the server | **UNKNOWN** | reach the client: whether ModData set in `OnCreate` is sent with the new item is not established |
| Inspection | none: reads | the client | **CLIENT-ONLY** | nothing |
| Die-set loot | the loot tables in memory | every machine at world load | **VANILLA** once the server's tables hold the entries | nothing; on a client the tables are never rolled from |
| Brass recycling | items in and out, no XP | vanilla `craftRecipe` | **VANILLA** | nothing |
| Ammo boxes | – | vanilla's recipe | **VANILLA** | nothing |
| Save-data repairs | whatever the owning system stores | where that system reads | as the owner | only write on the server |
| Debug tools | anything | the client, `-debug` | **CLIENT-ONLY**, and unsafe on a server | be refused on a client, or be admin commands (not built) |
| Reloading press (add-on, experimental) | a placed entity; items in and out at its recipes | the engine | **VANILLA** | nothing: a `CraftBench` entity is built, saved and synced by the engine, and its recipes are vanilla `craftRecipe`s. The feature is not switched off in multiplayer |
| Quality tracking (sandbox option, experimental) | ModData on a weapon or magazine; quality on unloaded rounds | single player only: **the feature is off on a client and on a server** (`AC_Features`) | **NEEDS SERVER**, not built | change only where vanilla changes the count (`not isClient()`); the record then rides on `syncHandWeaponFields` and `syncItemFields`. The census of loose rounds must be the server's inventory |
| Quality firing effects (locked) | vanilla's jam state | nowhere: locked | **NEEDS SERVER**, not built | roll on the server only, once per shot id |
| Spent cases (add-on, experimental) | new items at the shot or the rack | single player only: **off on a client and on a server** | **NEEDS SERVER**, not built | spawn on the server only, once per shot id (`network.fields.hit.Player.attack` triggers the event there) |
| Component and die-set loot | the loot tables in memory | every machine at world load | **VANILLA** once the server's tables hold the entries | nothing |

Six of the present systems are vanilla's and need nothing. Everything that
is the mod's own and changes the world (sampling, assays, the analyzer,
mining) has a server path since 0.11.0, behind the switch. The firearm
features (spent cases, quality) do not: they stay single player.

### 2.1 The guards

Nothing below is networking; each is a refusal, so that a multiplayer
client does nothing rather than something local and wrong. All read the
engine's `isClient()` (and the features also `isServer()`). **They are
unchanged by the server authority**: a client still never extracts,
digs, assays or changes the analyzer itself. With the switch on, the
menus offer the options all the same (`AC_Authority.canRequest()`), and
what the click does is ask.

| System | Guard | What a client sees, switch off | Switch on |
|---|---|---|---|
| Mining | `AC_Mining.isAvailable()` in `extract()` and in the menu | a disabled option: "Ore extraction is not available in multiplayer yet" | the options; the action is completed on the server |
| Analyzer: place, pick up | `AC_LaboratoryAnalyzer.isPlacementAvailable()` | disabled options with the reason | the options; placement and pickup run on the server |
| Analyzer: start, cancel, collect | `AC_LaboratoryAnalyzer.isAvailable()` in the three functions and in the menu | disabled options with the reason; *Check* still works, it only reads | the options; each click is a request |
| Digging a sample | `AC_GeologySampling.isAvailable()` in `createSample()` and in the menu | a disabled option: "Geological sampling and assays are not available in multiplayer yet" | the option; the action is completed on the server |
| Field and advanced assay | the same, in `analyzeSample()` and in the menu | disabled options with the reason | the options; each click is a request |
| Spent cases, quality tracking, firing effects | `singlePlayerOnly` in `AC_Features`: off on a client **and** on a server | nothing: no hook is installed, no entry is added | unchanged: off |

What a client can do without the switch is what vanilla owns: every
recipe, the press, loot, boxes. What remains **UNKNOWN** there is
unchanged: whether the XP call of the recipes' `OnCreate` and the quality
written there behave on a server (rows above).

**The requests, as built:**

| Request (client to server) | How it travels | The server checks | The server does | It answers |
|---|---|---|---|---|
| dig (square, shovel) | `AC_DigGeologicalSampleAction`, `complete()` | switch, rate, the square loaded and within reach, the shovel the requester's own, a shovel, not broken; then `createSample` checks the ground | creates the sample with its hidden geology, `sendAddItemToContainer`, shovel synced | `dig`: ok, or the refusal |
| `assay` (sampleId, kitId) | client command | switch, rate, both ids whole numbers naming items of the requester's inventory (bags included), a sample and a kit; then `analyzeSample` checks rank, kit uses, laboratory state | spends a kit use, writes the result, grants XP (`addXp`), syncs both items | `assay`: ok and XP, or the refusal |
| `labStart` (x, y, z, sampleId) | client command | switch, rate, whole coordinates in range, the square loaded, within reach, a **placed** analyzer on it, the sample the requester's own; then `startAssay` checks power, state, sample | stores the sample's data in the object, removes the sample (`sendRemoveItemFromContainer`), `transmitModData()` | `labStart`: ok, or the refusal |
| `labCancel` (x, y, z) | client command | as above, without a sample; then `cancelAssay` | returns the sample (`sendAddItemToContainer`), `transmitModData()` | `labCancel` |
| `labCollect` (x, y, z) | client command | as above; then `collectSample` | creates the laboratory-tested sample, empties the analyzer, `transmitModData()`, grants XP once | `labCollect`: ok and XP, or the refusal |
| pick up (analyzer) | `AC_PickUpAnalyzerAction`, `complete()` | switch, rate, a placed analyzer, within reach; then `canPickUp` (idle and empty) | removes the object (`transmitRemoveItemFromSquare`), gives the item (`sendAddItemToContainer`) | `pickUp` |
| place (square, item) | vanilla `ISBuildAction` / `BuildAction` | `create()` on the server: switch and reach (`AC_Authority.mayPlace`), the item in the inventory | builds the object, removes the item (the existing `sendRemoveItemFromContainer`) | the engine's own build sync |
| mine (square, metal, pickaxe) | `AC_MineOreAction`, `complete()` | switch, rate, the square loaded and within reach, the pickaxe the requester's own and in a hand; then `extract` checks the metal (one of the two, before anything else), the ground, the pickaxe, the assayed sample in the server's inventory, and the reserve | drops the ore (engine-replicated), records the extraction, grants XP, wears the pickaxe (synced), `ModData.transmit` the store | `mine`: ok, remaining, XP, or the refusal |
| *(none for the press, the recipes, loot)* | vanilla | – | – | – |

## 3. The duplications, one by one

### 3.1 Two players mine the same reserve

Each client holds its own copy of the depletion store, so each gets the
whole reserve. **Closed by** (built): the store lives on the server;
mining is a request; the handler checks the remaining reserve and records
the extraction in one uninterrupted call; the reply carries the server's
remaining count. Two requests for the last unit: the first gets the ore,
the second gets `no_ore` (tested). Never decrement on the client and
reconcile later. (`MULTIPLAYER_MINING.md`, worked through.)

### 3.2 Two players collect one analyzer's sample

Collect is a menu click that creates a sample item and clears the
analyzer's stored sample. On two clients both clicks see `ready` and both
create a sample. **Closed by** (built): `labCollect` is a request; the
handler reads `storedSample` from the object's server-side ModData, clears
it, creates the item for the requester and calls `transmitModData()`, all
in one call. The second request finds the analyzer empty and is refused
with the existing `empty` reason (tested). The same shape closes **start**
(two samples into one analyzer: the second is refused `busy`, and its
sample is never removed) and **cancel** against **collect** (whichever
arrives first wins; the other finds the state changed).

XP for the collection is granted in the same handler, to the requester,
once.

### 3.3 One player, two analyzers' worth of time

Time is credited when someone looks. With two clients looking, each
credits the hours since *its own* last look. **Closed by** (built for the
commands): only the server's credit counts, with the server's clock, at
each command; the stored `labLastUpdateAt` is the server's. A client's
*Check* still credits its own copy for display (single-player code,
unchanged); that copy is replaced by the next `transmitModData()` and is
never sent.

### 3.4 A sample dug twice, or assayed for free

A client that creates the sample itself can create it without the dig, and
a client that decrements its own kit can decline to. **Closed by**
(built): the dig action's `complete()` creates the sample on the server
from the server's geology; an assay is a request that names the sample and
the kit by item id, and the server checks both are in the requester's
inventory, takes the use and writes the result. An id the client made up,
or another player's kit, finds nothing (tested).

### 3.5 Duplicate spent cases

`OnWeaponSwingHitPoint` reaches the shooter's client and, for aimed
firearms, the server (JAR `PlayerHit.attack`, once per shot id). A listener
that spawns a case wherever it runs spawns two. **To be closed by** (not
built; the feature is single player): spawn only where `not isClient()`,
exactly where vanilla lowers the round count. The revolver's cases come
out of `ejectSpentRounds`, which both actions call from `start()` and
`serverStart()`: the wrapper acts in the server call only. How often the
event fires per round in automatic fire is not known
(`SPENT_CASE_RESEARCH.md` 6); the tally's own count is the guard, because
it yields exactly as many handloaded cases as handloaded rounds were
loaded, however often the event fires.

### 3.6 The quality tally out of step between machines

If a client changes its copy of the record, the next sync overwrites it or,
worse, does not. **To be closed by** (not built): the record is written
only on the server, beside vanilla's own count, and travels in the
weapon's ModData on the packet vanilla already sends. `consume` uses no
random number, so even a client that predicts the result predicts the
same one.

### 3.7 Press placement

Nothing to close. Building, picking up and using a `CraftBench` entity are
vanilla actions with vanilla authority; the press adds a tag and recipes.
The one mod-specific point is the XP grant in `OnCreate` (3.8).

### 3.8 XP granted twice, or not at all

`OnCreate` runs where the recipe is performed: the server. Whether the
single-player call reaches the client's character is **UNKNOWN**; if
`OnCreate` also ran on the client the grant would double. **Closed by**
(built, with the switch): on a server with authority,
`AmmoMakingSkill.addXP` grants through vanilla's `addXp`
(`GameServer.addXp`). Without the switch, the single-player call as
before.

### 3.9 World ModData that never arrives

A client that never receives the depletion store shows every tile as
untouched (a display fault, not a duplication, once extraction is the
server's). **Closed by** (built): `ModData.transmit(key)` from the server
after every extraction (and after a tile found empty), a
`ModData.request(key)` when a client starts, and a client listener that
keeps what arrives (`ModData.add`). Only the depletion key is kept; the
server does not listen at all.

### 3.10 A client that lies

A request is only as honest as the client that sends it. **Closed by**
(built): the server never takes a decision from the request. It reads the
player's position, inventory and hands from its own copies, finds items by
id only in the requester's own inventory, accepts only whole coordinates
in range on a loaded square within reach, only the two metals, and only
one request of each kind per player and second; a flood is dropped
without an answer. Section 6.3 lists every refusal and the test that pins
it.

## 4. Order of work

1. Seeds: confirm every machine derives the server's geology. **Less
   urgent since the authority**: every decision that reads geology is the
   server's; a client's seed only feeds its debug readouts.
2. Mining: built (`complete()`, one transmit).
3. The analyzer: built (three commands, server-side time at each command,
   placement and pickup).
4. Sampling and assays: built (`complete()` on the dig action, one command
   per assay).
5. `OnCreate`: server-side XP built behind the switch; whether quality
   ModData reaches the client is still unknown.
6. Only then anything on firearms (spent cases, quality): not built.

## 5. REQUIRES FUTURE IN-GAME VERIFICATION (on a dedicated server, with a client)

- **All of section 6**: that the engine sends the three timed actions to
  the server and runs their `complete()` there; that the commands and
  answers arrive; that the items, item fields and ModData sent with
  `sendAddItemToContainer`, `sendRemoveItemFromContainer`,
  `syncItemFields`, `syncItemModData` and `transmitModData()` reach the
  client, and in which order relative to the answer; that `addXp` on the
  server raises the client's skill; that `ModData.transmit` / `request`
  bring the depletion store to the client.
- That the server's sandbox options are in `SandboxVars` when
  `OnServerStarted` fires, and a client's when `OnGameStart` fires (both
  read the switch then).
- That vanilla's build action rebuilds the analyzer's placement cursor on
  the server from `character` and `sourceItem`, and that `create()` runs
  there.
- That `Action.isConsistent` (JAR `PlayerID.isConsistent`) ties a timed
  action to the connection that sent it, so a client cannot act for
  another player's character (the mod's checks assume the character the
  engine hands over is the requester).
- That a client and the server derive the same save identity and so the
  same geology (now only the client's debug readouts depend on it).
- Where `OnCreate` runs, and whether XP and item ModData set there reach
  the client.
- That `OnPreDistributionMerge` runs on a dedicated server before its loot
  tables are parsed.
- That the disabled options and refusals of section 2.1 are what a client
  actually sees with the switch off.

## 6. As built (0.11.0, experimental)

### 6.1 The switch

`AC_Features` definition `serverAuthority` ("Multiplayer Server
Authority"), **experimental**, sandbox option
`AmmoMaking.ServerAuthority`, **default off**, `singlePlayerOnly = false`.
It is read at two moments only: when a dedicated server has loaded its Lua
(`OnServerStarted`: the server then listens to `OnClientCommand`) and when
a client starts a game (`OnGameStart`: it then listens to
`OnServerCommand` and `OnReceiveGlobalModData`, and requests the depletion
store). Off, nothing is listened to. The timed actions' `complete()` and
the analyzer's `create()` read it again on the server at every request.

| Machine | `isClient()` | `isServer()` | switch | `canRequest()` | `decides()` |
|---|---|---|---|---|---|
| single player | false | false | any | false | false |
| multiplayer client | true | false | off / on | false / **true** | false |
| server | false | true | off / on | false | false / **true** |

### 6.2 Files

| File | What it holds |
|---|---|
| `shared/AC_Authority.lua` | the switch, the checks (`readSquare`, `isWithinReach`, `findOwnItem`, `ownsItem`, `holds`, `allow`), the server operations `serverDig`, `serverMine`, `serverPickUp`, `mayPlace`, the commands `assay`, `labStart`, `labCancel`, `labCollect`, the dispatcher `onClientCommand`, and `request` |
| `client/AC_AuthorityClient.lua` | the answer's message (the single-player menus' own texts), the store listener, the two request helpers |
| `shared/AC_DigGeologicalSampleAction.lua`, `shared/AC_MineOreAction.lua`, `shared/AC_PickUpAnalyzerAction.lua` | moved from `client/`: a dedicated server loads `shared/` and `server/`, never `client/`. Each has a `complete()` and keeps every parameter of `new()` as a field of the same name |
| `server/BuildingObjects/AC_LaboratoryAnalyzerObject.lua` | `new(character, sourceItem)`: the first parameter was called `player`, the name of the field that holds the player **number**, which the server could not call a method on; `create()` checks `mayPlace` on a server |
| `shared/AC_AmmoMakingSkill.lua` | `addXP` grants through `addXp` on a server with the switch on |

Numbers: reach **2 tiles** from the tile's centre on each axis, same
level (vanilla's own pickaxe action allows 1.6; the menus walk the player
next to the tile first). Rate **one request of each kind per player and
second** (a legitimate dig or extraction lasts several seconds; the
engine itself only starts one timed action per player at a time, JAR
`NetTimedActionPacket.processServer` stops the player's others).
Coordinates: whole numbers, 0 to 100000, level -32 to 32. Item ids: whole
numbers in the int range, looked up with `getItemWithIDRecursiv` in the
requester's inventory only.

### 6.3 Refusals

| Code | When | Pinned by (`tests/suite_authority.lua`) |
|---|---|---|
| `multiplayer_unsupported` | the switch is off on the server, or a server function is called on a client | "switch off on the server", "called on a client" |
| `rate_limited` | a second timed action of the same kind within a second (a command flood is dropped unanswered) | "Flooding" |
| `bad_request` | coordinates missing, fractional, text, NaN, negative, beyond the map, an unknown level; arguments that are not a table | "malformed values" |
| `no_square` | a square the server does not have loaded | "a square the server does not have" |
| `too_far` | the player more than 2 tiles from the tile, or on another level | "ten steps away", "one level up" |
| `invalid_metal` | a metal other than `copper` and `zinc`, spelled otherwise, or none | "a metal that does not exist" |
| `no_pickaxe`, `no_shovel` | the tool is another player's, not in a hand (pickaxe), the wrong tool, or broken | "another player's pickaxe", "a pickaxe in the bag" |
| `invalid_sample`, `invalid_kit` | an id that names nothing in the requester's inventory, another player's item, or the wrong kind of item | "another player's kit", "a made-up sample id" |
| `invalid_analyzer` | no placed analyzer on the square (a dropped analyzer item is single player only) | "a dropped analyzer item" |
| `server_error` | a handler raised an error (answered, logged) | "A handler that fails" |
| the single-player codes | everything `extract`, `createSample`, `analyzeSample`, `startAssay`, `cancelAssay`, `collectSample`, `canPickUp` already refuse | the existing sections |

### 6.4 Single player is unchanged

In single player `isClient()` and `isServer()` are both false, so
`canRequest()` and `decides()` are false whatever the switch says. Every
change to a single-player file is one of:

- a branch taken only when `AC_Authority.canRequest()` (the menus'
  handlers, the actions' `perform()`), placed before the single-player
  code, which follows unchanged;
- an availability written `isAvailable() or AC_Authority.canRequest()`,
  where the first term is true in single player;
- `complete()`, which the engine calls after `perform()` in single
  player, and which returns `true` at once unless `isServer()`;
- a field kept under a second name (`o.pickaxe`, `o.shovel`), and a
  constructor parameter renamed (`character`);
- `if isServer()` in `create()` and `decides()` in `addXP`.

`tests/suite_authority.lua` proves it against the code as it was:
`tests/sp_reference/` holds the seven touched files byte for byte as in
commit `eaa7a3e` (the state seen working in game). One session is played
through the menus and timed actions, dig, field and advanced assays,
mining to exhaustion and on barren ground, placing the analyzer, an assay
collected, one cancelled, the pickup, once with those files and once with
the current ones, with the switch off and on. Every message, item and its
ModData, XP grant, world item, depletion record, analyzer state and
console line is compared line by line; they are equal, and nothing is
sent over the network. The mutants of `tests/run_mutants.py` that remove
a single-player guard are killed by this comparison.
