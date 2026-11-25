# Sky Defense

A 3D hybrid tower defense and RTS game set among dieselpunk sky cities. Claim floating platforms, link them with metal walkways and airship ferries, and hold the sky against rival corporations.

Built with [Godot 4.3](https://godotengine.org/download/archive/4.3-stable/) (standard build, GDScript).

## Running it

1. Install Godot 4.3 (standard, not .NET).
2. In the Project Manager, choose **Import** and pick `project.godot` in this folder.
3. Press **F5** to play.

The current build is a placeholder sky region on hexagonal tiles: your Hub, five neutral platforms, the rival Ironbell HQ, walkways, a ferry route, two storm clouds and a rival air lane. A legend in the top right explains the tile colours. Your Commander (gold) and a squad of four Riveteers start on the Hub and can be selected and sent across walkways. You start with 200 scrap and can build on the Hub; the top bar shows scrap and the power grid, and each platform's label shows its load.

Weight matters: buildings and units both add to a platform's load. Over capacity a platform sways (over 100%), sags and slows units (over 115%), then fails (over 130%), dropping its newest building every few seconds. If towers draw more power than generators and harvesters supply, the grid browns out and towers run at reduced efficiency. Scrap heaps on platforms you own produce scrap, and Cloud Harvesters slowly form crystals.

Park units on a neutral platform to claim it (it's contested while both sides have units there), then build on it. Ironbell raiding parties march along walkways, claim platforms on the way, and gather at your Hub; there's no combat yet.

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
| Send an Ironbell raid | G (for testing until timed waves arrive) |

The full default key map (selection, control groups, build shortcuts, game speed) is defined in `tools/input_bindings.gd` and already written into `project.godot`. Those actions will be hooked up as each system is built.

## Project layout

| Path | What it holds |
| --- | --- |
| `scenes/` | Godot scenes; `main.tscn` is the entry point |
| `scripts/camera/` | The RTS camera |
| `scripts/world/` | Hex grid math, level layout data, the sky region builder with routing, claiming, and platform load |
| `scripts/units/` | Player units and the hero |
| `scripts/selection/` | Selection, orders and control groups |
| `scripts/buildings/` | Building catalog (costs, power, weight), placed buildings and build mode |
| `scripts/economy/` | The player's scrap and crystals, income and the power grid |
| `scripts/rivals/` | Ironbell raiding parties |
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
