# Sky Defense

A 3D hybrid tower defense and RTS game set among dieselpunk sky cities. Claim floating platforms, link them with metal walkways and airship ferries, and hold the sky against rival corporations.

Built with [Godot 4.3](https://godotengine.org/download/archive/4.3-stable/) (standard build, GDScript).

## Running it

1. Install Godot 4.3 (standard, not .NET).
2. In the Project Manager, choose **Import** and pick `project.godot` in this folder.
3. Press **F5** to play.

The current build is a gray-box sky region: the Hub (gold), four neutral platforms (gray), a rival HQ (red), walkways and a storm cloud (blue). Only the camera works so far.

## Controls

| Action | Default |
| --- | --- |
| Pan camera | WASD, arrow keys, or mouse at the screen edge |
| Rotate camera | Hold middle mouse and drag |
| Zoom | Scroll wheel |
| Jump to Hub | Home |

The full default key map (selection, control groups, build shortcuts, game speed) is defined in `tools/input_bindings.gd` and already written into `project.godot`. Those actions will be hooked up as each system is built.

## Project layout

| Path | What it holds |
| --- | --- |
| `scenes/` | Godot scenes; `main.tscn` is the entry point |
| `scripts/camera/` | The RTS camera |
| `scripts/world/` | Sky region, platforms and connections |
| `tools/` | Developer scripts: input map generator and the smoke test |

## Developer tools

Change default keys in `tools/input_bindings.gd`, then regenerate the input map:

```sh
godot --headless --path . --script res://tools/generate_input_map.gd
```

Run the headless smoke test (exits non-zero on failure):

```sh
godot --headless --path . --script res://tools/smoke_test.gd
```
