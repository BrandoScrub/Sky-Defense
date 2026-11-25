## Writes the default bindings from input_bindings.gd into project.godot.
## Run: godot --headless --path . --script res://tools/generate_input_map.gd
extends SceneTree

const Bindings = preload("res://tools/input_bindings.gd")


func _init() -> void:
	# Drop actions that are no longer defined.
	for prop in ProjectSettings.get_property_list():
		var setting: String = prop.name
		if setting.begins_with("input/") and not setting.begins_with("input/ui_"):
			ProjectSettings.clear(setting)

	var all: Dictionary = Bindings.bindings()
	for action in all:
		var events: Array = []
		for binding in all[action]:
			events.append(Bindings.make_event(binding))
		ProjectSettings.set_setting("input/" + action, {"deadzone": 0.5, "events": events})

	var err := ProjectSettings.save()
	if err != OK:
		push_error("Could not save project.godot: %s" % error_string(err))
		quit(1)
		return
	print("Wrote %d input actions to project.godot" % all.size())
	quit(0)
