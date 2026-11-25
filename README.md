# Sky Defense

A 3D hybrid tower defense and RTS game set among dieselpunk sky cities. Claim floating platforms, link them with metal walkways and airship ferries, and hold the sky against rival corporations.

Built with [Godot 4.3](https://godotengine.org/download/archive/4.3-stable/) (standard build, GDScript).

## Running it

1. Install Godot 4.3 (standard, not .NET).
2. In the Project Manager, choose **Import** and pick `project.godot` in this folder.
3. Press **F5** to play.

The current build is a placeholder sky region on hexagonal tiles: your Hub, five neutral platforms, the rival Ironbell HQ, walkways, a ferry route, two storm clouds and a rival air lane. A legend in the top right explains the tile colours. Your Commander (gold) and a squad of four Riveteers start on the Hub and can be selected and sent across walkways. You start with 250 scrap and can build on the Hub; the top bar shows scrap and the power grid, and each platform's label shows its load.

Weight matters: buildings and units both add to a platform's load. Over capacity a platform sways (over 100%), sags and slows units (over 115%), then fails (over 130%), dropping its newest building every few seconds. If towers draw more power than generators and harvesters supply, the grid browns out and towers run at reduced efficiency. Scrap heaps on platforms you own produce scrap, and Cloud Harvesters slowly form crystals.

Park units on a neutral platform to claim it (it's contested while both sides have units there), then build on it. Ironbell raiding parties march along walkways, claim platforms on the way, and attack whatever they meet. If you wall off a walkway with buildings they smash through the wall instead of stopping.

The game runs in waves. You get 45 seconds to build before wave 1 (25 seconds before later waves), then Ironbell sends a growing party of walkers; clear it to start the next build phase. Turrets, units and both headquarters shoot automatically, and each kill pays 15 scrap. You lose if your Hub headquarters falls and win once both rival headquarters are destroyed; press Enter on the end screen to play again. Use the Army tab (Q) to train more Riveteers at the Hub (30 scrap each). If your Commander falls, they return to the Hub after 15 seconds. A how-to-play panel is shown until the first wave starts.

There are two rival corporations. Ironbell Consolidated walks: its walkers come down the walkway from Midway. Vesper Aeronautics flies: from wave 2 its bomber airships leave the Vesper Aerodrome (far east), fly the red air lanes, and bomb your buildings or your Hub. Bombers ignore your units, and only anti-air weapons can hit them. Flak towers and hangar drones are built for this, and the Commander and headquarters guns can shoot them too. Ground defenses and Riveteers can't. Reach the Aerodrome on foot over the long walkway from the Outpost. When one rival's headquarters falls, that rival stops attacking.

Defenses come in three roles (`scripts/buildings/building_catalog.gd`, run by `scripts/combat/combat_system.gd` and `scripts/combat/defense_system.gd`):

- **Ground defenses** (Rivet Turret, Arc Coil, Rally Horn, Mending Post) can't hit aircraft. Most have modest guns but strengthen your ground units nearby: the Rivet Turret gives cover (armor), the Rally Horn adds damage and fire rate, and the Mending Post heals. Bonuses from different buildings don't stack, so each unit gets the best of each kind, and they work on every unit type.
- **Flak** (Flak Battery, Skyhook Gun) shoots only aircraft and airships and ignores everything on the ground.
- **Hangars** (Drone Hangar) keep 3 drones in the air. Drones chase anything that comes near the hangar, air or ground, then return; lost drones are rebuilt every 8 seconds, and they go down with their hangar.

Storm clouds are worth fighting over. Each Cloud Harvester taps the storm its anchor faces, and whoever has more harvesters on a storm controls it. Your storms add 15 power to the grid. Ironbell builds harvesters on anchors of platforms it holds, and a storm it controls throws lightning at your nearby units and buildings and makes its walkers tougher. Destroy Ironbell's harvesters (they're tinted red) to break its hold.

The Crystal Spire has no walkway at the start. Right click it and your units walk to the Hub's ferry dock, board the airship when it's in, and walk on from the far dock. The ferry crosses every few seconds in both directions.

All art is placeholder geometry built in code: brass-trimmed decks with lamp posts, lift engines under each platform, a clock-tower headquarters, helmeted Riveteers, a top-hatted Commander, boxy Ironbell walkers and Vesper blimps. Below the city a stormy sea of cloud drifts past, with lightning flickering through it (`scripts/world/sky_backdrop.gd` and `shaders/cloud_sea.gdshader`).

The map is generated each game from a seed (`scripts/world/level_layout.gd`). Your Hub is in the middle. Each rival headquarters sits in its own compass direction (one of the 8, at least 90 degrees apart), with a chain of 4 to 9 platforms between it and the Hub, plus a few side platforms. The Foundry, Generator Rig and ferry-only Crystal Spire sit near the Hub, and a storm cloud hangs beside the middle of each rival's chain. The generator already handles up to 4 rivals for future factions. To replay one map, set `map_seed` on the Region node in `scenes/main.tscn`. To compare maps, run `tools/map_preview.gd` (instructions at the top of the file).

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
| Build | Defense (one row per role): ground Q Rivet Turret, W Arc Coil, E Rally Horn, R Mending Post; flak A Flak Battery, S Skyhook Gun; hangars Z Drone Hangar. Economy: Q Dynamo Generator, W Walkway. Storm: Q Cloud Harvester |
| While placing | Left click places, Shift keeps placing, R rotates, Esc or right click cancels |
| Demolish | Delete over a building (refunds 75%) |
| Build a walkway | Economy tab, W, then click a tile on your platform, then a tile on another platform (15 scrap per tile) |
| Train a Riveteer | Army tab, Q (30 scrap, 5 seconds) |
| Start the next wave early | Space |
| What is this? | Left click anything (unit, building, platform, tile, storm cloud, ferry route, air lane) for a card in the bottom right that says what it is and does |
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
| `scripts/ui/` | HUD pieces: the bottom-left build menu and the bottom-right info card |
| `scripts/world/` | Hex grid math, level layout data, the sky region builder with routing, claiming, platform load, the airship ferry, storm control and the fog of war |
| `scripts/units/` | Player units, the hero and recruiting |
| `scripts/selection/` | Selection, orders and control groups |
| `scripts/buildings/` | Building catalog (costs, power, weight), placed buildings and build mode |
| `scripts/economy/` | The player's scrap and crystals, income and the power grid |
| `scripts/rivals/` | Ironbell raiding parties and Vesper bomber flights |
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

Run the headless smoke test (exits non-zero on failure):

```sh
godot --headless --path . --script res://tools/smoke_test.gd
```
