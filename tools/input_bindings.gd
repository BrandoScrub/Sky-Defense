## Default key bindings for Sky Defense.
##
## This is the single source of truth for the input map. After changing it, run
##   godot --headless --path . --script res://tools/generate_input_map.gd
## to rewrite the [input] section of project.godot.
extends RefCounted

const KEY := "key"
const MOUSE := "mouse"

## Each action maps to a list of bindings: [type, code, modifiers].
## Modifiers is a list of "ctrl", "shift" and "alt".
static func bindings() -> Dictionary:
	return {
		# Camera
		"camera_pan_up": [[KEY, KEY_W, []], [KEY, KEY_UP, []]],
		"camera_pan_down": [[KEY, KEY_S, []], [KEY, KEY_DOWN, []]],
		"camera_pan_left": [[KEY, KEY_A, []], [KEY, KEY_LEFT, []]],
		"camera_pan_right": [[KEY, KEY_D, []], [KEY, KEY_RIGHT, []]],
		"camera_rotate": [[MOUSE, MOUSE_BUTTON_MIDDLE, []]],
		"camera_zoom_in": [[MOUSE, MOUSE_BUTTON_WHEEL_UP, []]],
		"camera_zoom_out": [[MOUSE, MOUSE_BUTTON_WHEEL_DOWN, []]],
		"camera_focus_hub": [[KEY, KEY_HOME, []]],
		"camera_free": [[KEY, KEY_F8, []]],

		# Selection and orders
		"select": [[MOUSE, MOUSE_BUTTON_LEFT, []]],
		"command": [[MOUSE, MOUSE_BUTTON_RIGHT, []]],
		"modifier_additive": [[KEY, KEY_SHIFT, []]],
		"modifier_attack_move": [[KEY, KEY_ALT, []]],
		"select_units_on_screen": [[KEY, KEY_Q, []]],
		"select_hero": [[KEY, KEY_H, []]],

		# Control groups (Ctrl + number assigns, number selects)
		"control_group_assign": [[KEY, KEY_CTRL, []]],
		"control_group_1": [[KEY, KEY_1, []]],
		"control_group_2": [[KEY, KEY_2, []]],
		"control_group_3": [[KEY, KEY_3, []]],
		"control_group_4": [[KEY, KEY_4, []]],
		"control_group_5": [[KEY, KEY_5, []]],

		# Building
		"context_hotkey_1": [[KEY, KEY_Z, []]],
		"context_hotkey_2": [[KEY, KEY_X, []]],
		"context_hotkey_3": [[KEY, KEY_C, []]],
		"context_hotkey_4": [[KEY, KEY_V, []]],
		"context_hotkey_5": [[KEY, KEY_B, []]],
		"building_rotate": [[KEY, KEY_R, []]],
		"building_cancel": [[KEY, KEY_ESCAPE, []]],
		"demolish": [[KEY, KEY_DELETE, []]],

		# Game flow
		"start_wave_early": [[KEY, KEY_G, []]],
		"time_pause": [[KEY, KEY_P, []]],
		"time_normal": [[KEY, KEY_F1, []]],
		"time_double": [[KEY, KEY_F2, []]],
		"time_triple": [[KEY, KEY_F3, []]],
		"pause_menu": [[KEY, KEY_ESCAPE, []]],
	}


static func make_event(binding: Array) -> InputEvent:
	var mods: Array = binding[2]
	var event: InputEventWithModifiers
	if binding[0] == KEY:
		event = InputEventKey.new()
		event.physical_keycode = binding[1]
	else:
		event = InputEventMouseButton.new()
		event.button_index = binding[1]
	event.ctrl_pressed = mods.has("ctrl")
	event.shift_pressed = mods.has("shift")
	event.alt_pressed = mods.has("alt")
	return event
