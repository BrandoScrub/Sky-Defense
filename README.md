# Sky Defense

A 3D hybrid tower defense and RTS game set among dieselpunk sky cities. Claim floating platforms, link them with metal walkways and airship ferries, and hold the sky against rival corporations.

Built with [Godot 4.3](https://godotengine.org/download/archive/4.3-stable/) (standard build, GDScript).

## Running it

1. Install Godot 4.3 (standard, not .NET).
2. In the Project Manager, choose **Import** and pick `project.godot` in this folder.
3. Press **F5** to play.

The current build is a placeholder sky region on hexagonal tiles: your Hub, a generated ring of neutral platforms, the rival HQs, unconnected islands you link with walkways, storm clouds and rival air lanes. A legend in the top right (folded at the start; L opens it) explains the tile colours. Your Commander (gold) and a squad of four Riveteers start on the Hub and can be selected and sent across walkways. You start with 300 scrap, 10 crystals and one Dynamo Generator on the Hub, and can build there; a tower the grid can't power shows a NO POWER (or LOW POWER) sign over it; the top bar shows scrap, the power grid and crystals.

Weight is a building limit: every island can lift so much, and a building that would go over it can't be placed (the build hint says which island is full). Units don't count. A Lift Engine (Industry, E) lets its platform carry 10 more and weighs nothing itself; you can build one per island. Power works the same way across your whole grid: a tower needs spare power to be built, so you can't build yourself into a shortage. The grid only browns out (towers fire slower, with a LOW POWER or NO POWER sign) when you lose a generator or a storm. Income pays out at the end of each wave: every platform you hold besides the Hub pays 20 scrap, every scrap heap on a platform you own pays 50 scrap, every crystal seam on one pays 5 crystals and every Cloud Harvester pays 6 crystals, shown as +N in the top bar and in a popup when the wave is cleared. Kills pay half the attacker's bounty on the spot (8 scrap for a walker), so most of your scrap comes from the islands you hold.

Every resource has a job, and they're meant to be scarce, so each purchase is a tradeoff:

- **Scrap** pays for everything. Plain islands pay only 20 a wave, so what's on an island (scrap heaps, crystal seams, generator sockets, harvester anchors) decides which ones are worth claiming. Selling a building refunds half its price.
- **Crystals** buy the advanced gear on top of its scrap price: Arc Coil 10, Skyhook Gun 10, Airship Hangar 15, Lancer 5, Gunboat 10, plus the Hum powers. You start with 10; Cloud Harvesters (6 a wave) and crystal seams (5 a wave each) pay more.
- **Power** is a budget. A Dynamo makes 8 on plain deck but 15 on a generator socket, and a Cloud Harvester makes 15. Every tower draws power (shown at the top right of its build button), and its button reads "needs power" until you have that much spare. The Hub has two sockets; more are out on the islands.
- **Weight** limits how much one island can carry (see above).

Park units on a neutral platform to claim it (it's contested while both sides have units there), then build on it. Rival raiding parties march along walkways, claim platforms on the way, and attack whatever they meet. If you wall off a walkway with buildings they smash through the wall instead of stopping.

The game runs in waves. You get 45 seconds to build before wave 1 (25 seconds before later waves); clear a wave to start the next build phase. Turrets, units and both headquarters shoot automatically. Pick Easy, Normal or Hard on the bar at the bottom before wave 1 starts (it scales how many attackers come, their health, and your starting scrap). The pressure starts in wave 1: Ironbell's troop carriers fly a squad straight at you every wave while its bridge creeps island by island. Every 3rd wave (when the wind turns) is a big push: every rival sends 40% more. Attackers get 8% more health each wave. The top bar shows your Hub's health (amber under 60%, red under 30%, blinking while it's hit) and how many rival HQs are down. The match lasts 10 waves: survive the last one and you win. Wrecking every rival headquarters wins sooner: that's the slow way out, island by island. You lose if your Hub headquarters falls; press Enter on the end screen to play again. Use the Army tab to train more units at the Hub (see Ground units below). If your Commander falls, they return to the Hub after 15 seconds. A short how-to-play tip card sits top left (/ shows or hides it).

There are two rival corporations by default. Ironbell Consolidated walks: its crews bridge toward your Hub and its walkers come down that bridge. Vesper Aeronautics flies: from wave 3 its bombers leave the Vesper Aerodrome and fly one red air lane to your richest outer island (the one with the most scrap sunk into buildings; the Hub when you have none), then bomb your buildings there. Vesper's card names the island before the wave, and the lane moves as you build, so flak has to be where your islands are. Bombers ignore your units, and only anti-air weapons can hit them: flak towers, hangar drones, Interceptors, the Commander, Riflemen and headquarters guns. Ironbell troop carriers fly in from wave 1 (two at once from wave 5) and land their squad on your platform nearest Ironbell, and Vesper gunships come from wave 7; gunships hunt your units and drones before they go for buildings. Reach the Aerodrome on foot by building walkways out to it. When one rival's headquarters falls, that rival stops attacking.

Defenses come in three roles (`scripts/buildings/building_catalog.gd`, run by `scripts/combat/combat_system.gd` and `scripts/combat/defense_system.gd`):

- **Ground defenses** (Rivet Turret, Arc Coil, Rally Horn) can't hit aircraft. Most have modest guns but strengthen your ground units nearby: the Rivet Turret gives cover (armor) and the Rally Horn adds damage and fire rate. Bonuses from different buildings don't stack, so each unit gets the best of each kind, and they work on every unit type. (Engineers do the healing.)
- **Flak** (Flak Battery, Skyhook Gun) shoots only aircraft and airships and ignores everything on the ground.
- **The Airship Hangar** keeps 2 drones in the air (they chase anything that comes near, then return; lost drones are rebuilt) and builds your patrol airships: Interceptors (air-to-air) and Gunboats (air-to-ground), trained from the Army tab. Their buttons are greyed until you have a Hangar. Ships patrol every Mooring Mast you build, nearest first, and only hunt within reach of a hangar or mast, so masts decide which part of the sky is covered.

Storm clouds are worth fighting over. Each Cloud Harvester taps the storm its anchor faces, and whoever has more harvesters on a storm controls it. Your storms add 15 power to the grid. A rival builds harvesters on anchors of platforms it holds, and a storm it controls throws lightning at your nearby units and buildings. Destroy its harvesters (they're tinted red) to break its hold.

The Crystal Spire hangs one walkway beyond the Foundry, and its crystal seams pay crystals once you claim it.

Some maps have one or two balloon platforms (the Zephyr Barge and the Gasbag Wharf): small islands on gas bags that drift between two moorings along a faint dotted track, one whole hex at a time, so they always stay on the hex grid. While moored, a short walkway joins a balloon to the platform beside it. Before it casts off it gives 6 seconds of warning: the walkway flashes amber, a sign over the balloon counts down, every unit on the walkway gets an amber caution triangle over its head, and a klaxon (then a beep each second) sounds while any of your units are still on it. Then the walkway breaks away. **Units still on the walkway fall and are lost** (the Commander comes back at the Hub as usual); units on the balloon itself are safe and ride along. When the balloon reaches the far mooring, a new walkway reaches out and it can be boarded again. Use them to carry a squad (or a turret you built on one) to another part of the map. You can't build walkways across a balloon's track. The code is in `scripts/world/drift_system.gd`.

All art is basic geometry built in code. Every building, troop, airship, drone and headquarters is assembled from one shared parts kit (`scripts/art/model_kit.gd`: riveted bedplates, brass trim, copper pipes, smokestacks, lamps, gas bags, propellers, gun barrels), so they all look like they came from the same foundry. The models are in `scripts/art/building_models.gd`, `unit_models.gd` and `hq_models.gd`; change a colour or part in the kit and everything follows. Your side has brass trim and warm lamps; rivals have red-oxide trim, dark plate and lamps in their own colour, and each rival headquarters has its own building (Ironbell a blast furnace and bell, Vesper an aerodrome tower, Nimbus a storm dome, Aurum a crystal-topped vault). To see every model lined up and labelled, run `tools/model_sheet.gd` (instructions at the top of the file). Below the city a stormy sea of cloud drifts past, with lightning flickering through it (`scripts/world/sky_backdrop.gd` and `shaders/cloud_sea.gdshader`). The scene is lit like a late afternoon: a low warm sun, a cool fill light, glow on lamps and crystals, and haze that thickens below the decks (the WorldEnvironment and lights in `scenes/main.tscn`). Deck tiles get a pattern by island type, drawn in `shaders/deck.gdshader` over the ownership colour: riveted plates on city platforms, tread plate on turbines, flagstones on rock, grass on grassy crystal islands and slate with glowing veins on overcharged ones; walkways are iron grating. To review the art, run `tools/art_shots.gd` (instructions at the top of the file).

The map is generated each game from a seed (`scripts/world/level_layout.gd`). Your Hub is in the middle. Each rival headquarters sits in its own compass direction (one of the 8, at least 90 degrees apart), with a chain of 4 to 9 platforms between it and the Hub, plus a few side platforms. The Foundry and Generator Rig sit near the Hub, with the Crystal Spire a walkway beyond the Foundry, and a storm cloud hangs beside the middle of each rival's chain. The generator already handles up to 4 rivals for future factions. Islands have their own outlines by type, so no two look alike and they don't sit in neat rows: turbine islands (with generator sockets) are a round hub with three bent blades and lift engines underneath, crystal islands are long jagged shards, and everything else is a lumpy natural rock. Crystal islands come in two kinds: grassy green ones (ground the crystals lifted into the sky, trailing roots) and overcharged violet ones bristling with glowing shards (storm effects to come). The Hub and rival HQs stay full hexagons. An island's weight capacity follows its real size. Islands start unconnected: the walkways in the layout are only planned routes. You expand by building walkways (Industry tab) from platforms you own, so where you go first is your call. A new walkway goes up the company way: two harpoons fire from your island trailing cables and bite into the far one, then the walkway is laid along the cables one tile at a time (`scripts/world/walkway_crew.gd`). Units can use each tile as soon as it's down. Ironbell's bridges go up the same way, a little slower. Ironbell's bridge crews build its planned chain one span at a time from its HQ toward your Hub (a span every 30 seconds, `scripts/rivals/rival_bridges.gd`). Its walkers creep along it, claiming each island they reach. When a rival takes one of your islands, everything you built there is wrecked. Until the bridge reaches you, the walkers camp at its end: a camp doesn't hold up the wave, it joins the next one, and Ironbell only tops the camp up to that wave's size. Rival troops holding an island they took with nowhere to go (for example, dropped on an island cut off from your Hub) don't hold up the wave either; send troops to win it back. You can cut a span: park any of your units on a platform tile right beside it, with no enemy close by, for 8 seconds, and the whole span falls (anything on it falls too). The crew then has to build it again. Ironbell's spans are tinted red-brown. Vesper doesn't bridge; its bombers fly. Every rival is a data entry in `scripts/rivals/rival_catalog.gd`: its headquarters, colours, whether it bridges or flies air lanes, and what it sends each wave. Waves, raids, bridges, airships, the top bar and the fog all read it. A map has 2 rivals by default; set `rival_count` (2 to 4) on the Region node in `scenes/main.tscn` to add Nimbus Weatherworks and Aurum Crystalworks. Those two are stand-ins for now: they bridge and walk like Ironbell with lighter or tougher troops, until their storms, buildings and boss ship are designed. To replay one map, set `map_seed` on the Region node in `scenes/main.tscn`. To compare maps, run `tools/map_preview.gd` (instructions at the top of the file).

## Ground units

Every faction fields the same base troops (stats live in `scripts/units/unit_catalog.gd`); Ironbell mixes Shieldbearers and Riflemen into raiding parties of 4 or more alongside its armored walkers.

| Unit | Cost | Role |
| --- | --- | --- |
| Riveteer | 30 | Cheap all-rounder. Claims platforms, fights at short range. |
| Shieldbearer | 50 | Riot shield. Tough melee fighter. Its shield stops 75% of any shot aimed at it and catches enemy shots that try to fly past it toward allies behind. |
| Rifleman | 40 | Bolt gun. Long range and hard-hitting, and the only ground troop that can shoot at airships, but fragile. |
| Lancer | 60 + 5 crystals | Anti-armor. Slow, heavy shots that do 2.5x damage to armored walkers and partly pierce shields. |
| Engineer | 40 | Support. Heals the most wounded ally nearby first, repairs your damaged buildings (and, slowly, your Hub) when nobody needs patching, and does 4x damage to enemy buildings. |

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
| Build menu | Bottom left: tabs (Army, Defense, Industry, Hum) over a 4 x 4 command grid. Tab cycles the tabs. The grid keys match their spots on the keyboard: Q W E R / A S D F / Z X C V / T G B N, and what each does depends on the tab |
| Build | Defense (one row per role): ground Q Rivet Turret (50 scrap), W Arc Coil, E Rally Horn; flak A Flak Battery, S Skyhook Gun; air Z Airship Hangar, X Mooring Mast. Industry: Q Dynamo Generator, W Walkway, E Lift Engine, R Cloud Harvester |
| Company powers | Hum tab, paid in crystals: Q Overcharge (15: your towers fire 40% faster for 20 s). It recharges after use |
| While placing | Left click places, Shift keeps placing, R rotates, Esc or right click cancels |
| Demolish | Delete over a building (refunds 50%) |
| Build a walkway | Industry tab, W, then click a tile on your platform, then a tile on another platform (15 scrap per tile) |
| Train units | Army tab: Q Riveteer, W Shieldbearer, E Rifleman, R Lancer, A Engineer; with a Hangar, Z Interceptor, X Gunboat |
| Start the next wave early | Space |
| Next waves | The top bar shows your resources and a card per rival: its bridge progress until it reaches you, then a countdown to its next wave (and, for Vesper, the island its bombers will hit); hover a card to see which units and how many it will send |
| What is this? | Left click anything (unit, building, platform, tile, storm cloud, air lane) for a card in the bottom right that says what it is and does |
| Debug tools | Click Debug under the legend: fog of war on/off, +500 scrap, +50 crystals, start the next wave, destroy all attackers. New testing tools go here |
| Show or hide the legend | L, or click its title |
| Pause | P |
| Game speed | F1 normal, F2 double, F3 triple |

The full default key map (selection, control groups, build shortcuts, game speed) is defined in `tools/input_bindings.gd` and already written into `project.godot`. Those actions will be hooked up as each system is built.

Dark storm clouds hide every part of the sky you haven't scouted (`scripts/world/fog_system.gd`). Your units and the platforms you own clear the clouds around them, and scouted sky stays clear. Islands one walkway from land you own are always shown, and the label of an island you don't own says what it holds (scrap heaps, generator sockets, crystal seams, storm anchors), so you can pick your next expansion off the screen. Rival units only show while something of yours can see them. Some islands glow through the storm with a hint: crystal seams (cyan, "Crystal glow?"), generator sockets (gold, "Electric hum?") and rival headquarters (Ironbell's furnace red, Vesper's violet signal lamps). The fog is only visual: it doesn't change what anyone can attack.

## Project layout

| Path | What it holds |
| --- | --- |
| `scenes/` | Godot scenes; `main.tscn` is the entry point |
| `scripts/art/` | The shared model parts kit and the models for buildings, units and headquarters |
| `scripts/camera/` | The RTS camera |
| `scripts/ui/` | HUD pieces: the top bar, the Debug panel, the bottom-left build menu and the bottom-right info card |
| `scripts/world/` | Hex grid math, level layout data, the sky region builder with routing, claiming, platform load, storm control and the fog of war |
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
