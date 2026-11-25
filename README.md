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

The game runs in waves. You get 45 seconds to build before wave 1 (25 seconds before later waves), then Ironbell sends a growing party of walkers; clear it to start the next build phase. Turrets, units and both headquarters shoot automatically, and each kill pays 15 scrap. You lose if your Hub headquarters falls and win once both rival headquarters are destroyed; press Enter on the end screen to play again. Press Y to train more Riveteers at the Hub (30 scrap each). If your Commander falls, they return to the Hub after 15 seconds. A how-to-play panel is shown until the first wave starts.

There are two rival corporations. Ironbell Consolidated walks: its walkers come down the walkway from Midway. Vesper Aeronautics flies: from wave 2 its bomber airships leave the Vesper Aerodrome (far east), fly the red air lanes, and bomb your buildings or your Hub. Bombers ignore your units, and only anti-air weapons can hit them. Flak Batteries are built for this, Rivet Turrets only scratch them, and the Commander and headquarters guns can shoot them too. Arc Coils and Riveteers can't. Reach the Aerodrome on foot over the long walkway from the Outpost. When one rival's headquarters falls, that rival stops attacking.

Storm clouds are worth fighting over. Each Cloud Harvester taps the storm its anchor faces, and whoever has more harvesters on a storm controls it. Your storms add 15 power to the grid. Ironbell builds harvesters on anchors of platforms it holds, and a storm it controls throws lightning at your nearby units and buildings and makes its walkers tougher. Destroy Ironbell's harvesters (they're tinted red) to break its hold.

The Crystal Spire has no walkway at the start. Right click it and your units walk to the Hub's ferry dock, board the airship when it's in, and walk on from the far dock. The ferry crosses every few seconds in both directions.

To change the map, edit `scripts/world/level_layout.gd`: platforms, features, walkways, ferry routes, clouds and air lanes are all plain tables there.

## Controls

| Action | Default |
| --- | --- |
| Pan camera | WASD, arrow keys, or mouse at the screen edge |
| Rotate camera | Hold middle mouse and drag |
| Zoom | Scroll wheel |
| Jump to Hub | Home |
| Select | Left click, or drag a box; Shift adds to the selection |
| Move | Right click on a platform |
| Attack-move | Alt + right click |
| Select all units on screen | Q |
| Select hero | H (double-tap to move the camera to them) |
| Control groups | Ctrl + 1 to 5 saves, 1 to 5 selects, double-tap to move the camera |
| Build | Z Dynamo Generator, X Cloud Harvester, C Rivet Turret, V Flak Battery, B Arc Coil |
| While placing | Left click places, Shift keeps placing, R rotates, Esc or right click cancels |
| Demolish | Delete over a building (refunds 75%) |
| Build a walkway | T, click a tile on your platform, then a tile on another platform (15 scrap per tile) |
| Train a Riveteer | Y (30 scrap, 5 seconds) |
| Start the next wave early | G |
| Pause | P |
| Game speed | F1 normal, F2 double, F3 triple |

The full default key map (selection, control groups, build shortcuts, game speed) is defined in `tools/input_bindings.gd` and already written into `project.godot`. Those actions will be hooked up as each system is built.

## Project layout

| Path | What it holds |
| --- | --- |
| `scenes/` | Godot scenes; `main.tscn` is the entry point |
| `scripts/camera/` | The RTS camera |
| `scripts/world/` | Hex grid math, level layout data, the sky region builder with routing, claiming, platform load, the airship ferry and storm control |
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
