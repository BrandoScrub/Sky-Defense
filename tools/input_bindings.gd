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
		# Arrow keys always pan. W A S D are build-grid keys, so they pan only
		# while Shift is held (the camera checks Shift itself).
		"camera_pan_up": [[KEY, KEY_UP, []]],
		"camera_pan_down": [[KEY, KEY_DOWN, []]],
		"camera_pan_left": [[KEY, KEY_LEFT, []]],
		"camera_pan_right": [[KEY, KEY_RIGHT, []]],
		"camera_shift_pan_up": [[KEY, KEY_W, []]],
		"camera_shift_pan_down": [[KEY, KEY_S, []]],
		"camera_shift_pan_left": [[KEY, KEY_A, []]],
		"camera_shift_pan_right": [[KEY, KEY_D, []]],
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
		"select_units_on_screen": [[KEY, KEY_A, ["ctrl"]]],
		"select_hero": [[KEY, KEY_H, []]],

		# Control groups (Ctrl + number assigns, number selects)
		"control_group_assign": [[KEY, KEY_CTRL, []]],
		"control_group_1": [[KEY, KEY_1, []]],
		"control_group_2": [[KEY, KEY_2, []]],
		"control_group_3": [[KEY, KEY_3, []]],
		"control_group_4": [[KEY, KEY_4, []]],
		"control_group_5": [[KEY, KEY_5, []]],

		# Building
		# Build command grid, 4 x 4, read left to right and top to bottom:
		#   Q W E R / A S D F / Z X C V / T G B N
		# What each slot does depends on the build menu's tab.
		"grid_slot_1": [[KEY, KEY_Q, []]],
		"grid_slot_2": [[KEY, KEY_W, []]],
		"grid_slot_3": [[KEY, KEY_E, []]],
		"grid_slot_4": [[KEY, KEY_R, []]],
		"grid_slot_5": [[KEY, KEY_A, []]],
		"grid_slot_6": [[KEY, KEY_S, []]],
		"grid_slot_7": [[KEY, KEY_D, []]],
		"grid_slot_8": [[KEY, KEY_F, []]],
		"grid_slot_9": [[KEY, KEY_Z, []]],
		"grid_slot_10": [[KEY, KEY_X, []]],
		"grid_slot_11": [[KEY, KEY_C, []]],
		"grid_slot_12": [[KEY, KEY_V, []]],
		"grid_slot_13": [[KEY, KEY_T, []]],
		"grid_slot_14": [[KEY, KEY_G, []]],
		"grid_slot_15": [[KEY, KEY_B, []]],
		"grid_slot_16": [[KEY, KEY_N, []]],
		"building_rotate": [[KEY, KEY_R, []]],
		"building_cancel": [[KEY, KEY_ESCAPE, []]],
		"demolish": [[KEY, KEY_DELETE, []]],
		"build_menu_next_tab": [[KEY, KEY_TAB, []]],
		"toggle_legend": [[KEY, KEY_L, []]],

		# Game flow
		"start_wave_early": [[KEY, KEY_SPACE, []]],
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
