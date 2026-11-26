# Sky Defense

A 3D hybrid tower defense and RTS game set among dieselpunk sky cities. Claim floating platforms, link them with metal walkways and airship ferries, and hold the sky against rival corporations.

Built with [Godot 4.3](https://godotengine.org/download/archive/4.3-stable/) (standard build, GDScript).

## Running it

1. Install Godot 4.3 (standard, not .NET).
2. In the Project Manager, choose **Import** and pick `project.godot` in this folder.
3. Press **F5** to play.

The current build is a placeholder sky region on hexagonal tiles: your Hub, a generated ring of neutral platforms, the rival HQs, unconnected islands you link with walkways, a ferry route, storm clouds and rival air lanes. A legend in the top right explains the tile colours. Your Commander (gold) and a squad of four Riveteers start on the Hub and can be selected and sent across walkways. You start with 250 scrap and one Dynamo Generator on the Hub, and can build there; a tower the grid can't power shows a NO POWER (or LOW POWER) sign over it; the top bar shows scrap and the power grid, and each platform's label shows its load.

Weight matters: buildings and units both add to a platform's load. Over capacity a platform sways (over 100%), sags and slows units (over 115%), then fails (over 130%), dropping its newest building every few seconds. If towers draw more power than generators and harvesters supply, the grid browns out and towers run at reduced efficiency. Units count for half their weight, so a squad can stand on a small island. A Lift Engine (Economy, E) lets its platform carry 10 more and weighs nothing itself. Income pays out at the end of each wave: every platform you hold besides the Hub pays 10 scrap, every scrap heap on a platform you own pays 50 scrap and every Cloud Harvester pays 6 crystals, shown as +N in the top bar and in a popup when the wave is cleared. Kills still pay scrap on the spot.

Park units on a neutral platform to claim it (it's contested while both sides have units there), then build on it. Ironbell raiding parties march along walkways, claim platforms on the way, and attack whatever they meet. If you wall off a walkway with buildings they smash through the wall instead of stopping.

The game runs in waves. You get 45 seconds to build before wave 1 (25 seconds before later waves), then Ironbell sends a growing party of walkers; clear it to start the next build phase. Turrets, units and both headquarters shoot automatically, and each kill pays 15 scrap. You lose if your Hub headquarters falls and win once both rival headquarters are destroyed; press Enter on the end screen to play again. Use the Army tab to train more units at the Hub (see Ground units below). If your Commander falls, they return to the Hub after 15 seconds. A how-to-play panel is shown until the first wave starts.

There are two rival corporations. Ironbell Consolidated walks: its crews bridge toward your Hub and its walkers come down that bridge. Vesper Aeronautics flies: from wave 3 its bomber airships leave the Vesper Aerodrome (far east), fly the red air lanes, and bomb your buildings or your Hub. Bombers ignore your units, and only anti-air weapons can hit them. Flak towers and hangar drones are built for this, and the Commander and headquarters guns can shoot them too. Ground defenses and Riveteers can't. Ironbell troop carriers join from wave 5 and Vesper gunships from wave 7. Reach the Aerodrome on foot by building walkways out to it. When one rival's headquarters falls, that rival stops attacking.

Defenses come in three roles (`scripts/buildings/building_catalog.gd`, run by `scripts/combat/combat_system.gd` and `scripts/combat/defense_system.gd`):

- **Ground defenses** (Rivet Turret, Arc Coil, Rally Horn, Mending Post) can't hit aircraft. Most have modest guns but strengthen your ground units nearby: the Rivet Turret gives cover (armor), the Rally Horn adds damage and fire rate, and the Mending Post heals. Bonuses from different buildings don't stack, so each unit gets the best of each kind, and they work on every unit type.
- **Flak** (Flak Battery, Skyhook Gun) shoots only aircraft and airships and ignores everything on the ground.
- **Hangars** (Drone Hangar) keep 3 drones in the air. Drones chase anything that comes near the hangar, air or ground, then return; lost drones are rebuilt every 8 seconds, and they go down with their hangar.

Storm clouds are worth fighting over. Each Cloud Harvester taps the storm its anchor faces, and whoever has more harvesters on a storm controls it. Your storms add 15 power to the grid. Ironbell builds harvesters on anchors of platforms it holds, and a storm it controls throws lightning at your nearby units and buildings and makes its walkers tougher. Destroy Ironbell's harvesters (they're tinted red) to break its hold.

The Crystal Spire has no walkway at the start. Right click it and your units walk to the Hub's ferry dock, board the airship when it's in, and walk on from the far dock. The ferry crosses every few seconds in both directions.

Some maps have one or two balloon platforms (the Zephyr Barge and the Gasbag Wharf): small islands on gas bags that drift between two moorings along a faint dotted track, one whole hex at a time, so they always stay on the hex grid. While moored, a short walkway joins a balloon to the platform beside it. Before it casts off it gives 6 seconds of warning: the walkway flashes amber, a sign over the balloon counts down, every unit on the walkway gets an amber caution triangle over its head, and a klaxon (then a beep each second) sounds while any of your units are still on it. Then the walkway breaks away. **Units still on the walkway fall and are lost** (the Commander comes back at the Hub as usual); units on the balloon itself are safe and ride along. When the balloon reaches the far mooring, a new walkway reaches out and it can be boarded again. Use them to carry a squad (or a turret you built on one) to another part of the map. You can't build walkways across a balloon's track. The code is in `scripts/world/drift_system.gd`.

All art is placeholder geometry built in code: brass-trimmed decks with lamp posts, lift engines under each platform, a clock-tower headquarters, helmeted Riveteers, a top-hatted Commander, boxy Ironbell walkers and Vesper blimps. Below the city a stormy sea of cloud drifts past, with lightning flickering through it (`scripts/world/sky_backdrop.gd` and `shaders/cloud_sea.gdshader`).

The map is generated each game from a seed (`scripts/world/level_layout.gd`). Your Hub is in the middle. Each rival headquarters sits in its own compass direction (one of the 8, at least 90 degrees apart), with a chain of 4 to 9 platforms between it and the Hub, plus a few side platforms. The Foundry, Generator Rig and ferry-only Crystal Spire sit near the Hub, and a storm cloud hangs beside the middle of each rival's chain. The generator already handles up to 4 rivals for future factions. Islands have their own outlines by type, so no two look alike and they don't sit in neat rows: turbine islands (with generator sockets) are a round hub with three bent blades and lift engines underneath, crystal islands are long jagged shards, and everything else is a lumpy natural rock. Crystal islands come in two kinds: grassy green ones (ground the crystals lifted into the sky, trailing roots) and overcharged violet ones bristling with glowing shards (storm effects to come). The Hub and rival HQs stay full hexagons. An island's weight capacity follows its real size. Islands start unconnected: the walkways in the layout are only planned routes. You expand by building walkways (Economy tab) from platforms you own, so where you go first is your call. A new walkway goes up the company way: two harpoons fire from your island trailing cables and bite into the far one, then the walkway is laid along the cables one tile at a time (`scripts/world/walkway_crew.gd`). Units can use each tile as soon as it's down. Ironbell's bridges go up the same way, a little slower. Ironbell's bridge crews build its planned chain one span at a time from its HQ toward your Hub (a span every 30 seconds, `scripts/rivals/rival_bridges.gd`). Until it reaches you, its walkers camp at the end of the bridge: a camp doesn't hold up the wave, it joins the next one, and Ironbell only tops the camp up to that wave's size. You can cut a span: park any of your units on a platform tile right beside it, with no enemy close by, for 8 seconds, and the whole span falls (anything on it falls too). The crew then has to build it again. Ironbell's spans are tinted red-brown. Vesper doesn't bridge; its bombers fly. Every rival is a data entry in `scripts/rivals/rival_catalog.gd`: its headquarters, colours, whether it bridges or flies air lanes, and what it sends each wave. Waves, raids, bridges, airships, the top bar and the fog all read it. A map has 2 rivals by default; set `rival_count` (2 to 4) on the Region node in `scenes/main.tscn` to add Nimbus Weatherworks and Aurum Crystalworks. Those two are stand-ins for now: they bridge and walk like Ironbell with lighter or tougher troops, until their storms, buildings and boss ship are designed. To replay one map, set `map_seed` on the Region node in `scenes/main.tscn`. To compare maps, run `tools/map_preview.gd` (instructions at the top of the file).

## Ground units

Every faction fields the same base troops (stats live in `scripts/units/unit_catalog.gd`); Ironbell mixes Shieldbearers and Riflemen into raiding parties of 4 or more alongside its armored walkers.

| Unit | Cost | Role |
| --- | --- | --- |
| Riveteer | 30 | Cheap all-rounder. Claims platforms, fights at short range. |
| Shieldbearer | 45 | Riot shield. Tough melee fighter. Its shield stops 75% of any shot aimed at it and catches enemy shots that try to fly past it toward allies behind. |
| Rifleman | 40 | Bolt gun. Long range and hard-hitting, but fragile. |
| Sapper | 40 | Engineer. Repairs your damaged buildings nearby and does 4x damage to enemy buildings. |
| Lancer | 60 | Anti-armor. Slow, heavy shots that do 2.5x damage to armored walkers and partly pierce shields. |
| Medic | 40 | Doesn't fight. Heals the most wounded ally nearby. |

Melee hits, Arc Coil lightning and bombs from the air go around shields. Units can be buffed by anything in the game with `unit.add_buff(id, {"damage": 1.25, ...}, seconds)`, or by an aura with `Unit.buff_allies_near(...)`; the stats a buff can change are listed in `Unit.BUFF_STATS`. Clicking a unit shows its stats and any buffs on the info card.

## Controls

| Action | Default |
| --- | --- |
| Pan camera | Arrow keys, Shift + W A S D, or mouse at the screen edge |
| Rotate camera | Hold middle mouse and drag |
| Zoom | Scroll wheel |
| Jump to Hub | Home |
| Select | Left click, or drag a box; Shift adds to the selection |
| Move | Right click on a platform |
| Attack-move | Alt + right click |
| Select all units on screen | Ctrl + A |
| Select hero | H (double-tap to move the camera to them) |
| Control groups | Ctrl + 1 to 5 saves, 1 to 5 selects, double-tap to move the camera |
| Build menu | Bottom left: tabs (Army, Defense, Economy, Storm, Ships) over a 4 x 4 command grid. Tab cycles the tabs. The grid keys match their spots on the keyboard: Q W E R / A S D F / Z X C V / T G B N, and what each does depends on the tab |
| Build | Defense (one row per role): ground Q Rivet Turret, W Arc Coil, E Rally Horn, R Mending Post; flak A Flak Battery, S Skyhook Gun; hangars Z Drone Hangar. Economy: Q Dynamo Generator, W Walkway, E Lift Engine. Storm: Q Cloud Harvester |
| Company powers | Storm tab, paid in crystals: A Overcharge (15: your towers fire 40% faster for 20 s), S Emergency Lift (20: your platforms ignore overload for 30 s). Each recharges after use |
| While placing | Left click places, Shift keeps placing, R rotates, Esc or right click cancels |
| Demolish | Delete over a building (refunds 75%) |
| Build a walkway | Economy tab, W, then click a tile on your platform, then a tile on another platform (15 scrap per tile) |
| Train units | Army tab: Q Riveteer, W Shieldbearer, E Rifleman, R Sapper, A Lancer, S Medic |
| Start the next wave early | Space |
| Next waves | The top bar shows your resources and a card per rival with a countdown to its next wave; hover a card to see which units and how many it will send |
| What is this? | Left click anything (unit, building, platform, tile, storm cloud, ferry route, air lane) for a card in the bottom right that says what it is and does |
| Debug tools | Click Debug under the legend: fog of war on/off, +500 scrap, +50 crystals, start the next wave, destroy all attackers. New testing tools go here |
| Show or hide the legend | L, or click its title |
| Pause | P |
| Game speed | F1 normal, F2 double, F3 triple |

The full default key map (selection, control groups, build shortcuts, game speed) is defined in `tools/input_bindings.gd` and already written into `project.godot`. Those actions will be hooked up as each system is built.

Dark storm clouds hide every part of the sky you haven't scouted (`scripts/world/fog_system.gd`). Your units and the platforms you own clear the clouds around them, and scouted sky stays clear. Rival units only show while something of yours can see them. Some islands glow through the storm with a hint: crystal seams (cyan, "Crystal glow?"), generator sockets (gold, "Electric hum?") and rival headquarters (Ironbell's furnace red, Vesper's violet signal lamps). The fog is only visual: it doesn't change what anyone can attack.

## Project layout

| Path | What it holds |
| --- | --- |
| `scenes/` | Godot scenes; `main.tscn` is the entry point |
| `scripts/camera/` | The RTS camera |
| `scripts/ui/` | HUD pieces: the top bar, the Debug panel, the bottom-left build menu and the bottom-right info card |
| `scripts/world/` | Hex grid math, level layout data, the sky region builder with routing, claiming, platform load, the airship ferry, storm control and the fog of war |
| `scripts/units/` | Player units, the hero and recruiting |
| `scripts/selection/` | Selection, orders and control groups |
| `scripts/buildings/` | Building catalog (costs, power, weight), placed buildings and build mode |
| `scripts/economy/` | The player's scrap and crystals, income and the power grid |
| `scripts/rivals/` | Ironbell raiding parties and bridge crews, and Vesper bomber flights |
| `scripts/combat/` | Health bars, headquarters, targeting and damage, and the wave timer |
| `tools/` | Developer scripts: input map generator and the smoke test |

## Developer tools

Change default keys in `tools/input_bindings.gd`, then regenerate the input map:

```sh
godot --headless --path . --script res://tools/generate_input_map.gd
```

Render screenshots of the level (needs a display; on a server use `xvfb-run`):

```sh
godot --path . --rendering-method gl_compatibility --script res://tools/screenshot.gd -- /path/to/output
```

Run the headless smoke test (exits non-zero on failure). GitHub runs it automatically on every pull request (`.github/workflows/smoke-test.yml`); a red X on a pull request means a check failed, and its Details link shows which one:

```sh
godot --headless --path . --script res://tools/smoke_test.gd
```
