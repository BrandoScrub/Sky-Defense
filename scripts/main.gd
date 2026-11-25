## Root of the prototype scene. Spawns the starting units on the Hub, sets up
## selection, and wires global hotkeys to the camera.
extends Node3D

const SQUAD_SIZE := 4

@onready var camera: RtsCamera = $RtsCamera
@onready var region: SkyRegion = $Region

var selection: SelectionController
var _status: Label


func _ready() -> void:
	camera.bounds = region.get_bounds()
	camera.position = region.get_platform_position("Hub")
	_spawn_starting_units()

	selection = SelectionController.new()
	selection.name = "SelectionController"
	selection.camera = camera
	selection.region = region
	add_child(selection)

	_build_hud()
	selection.selection_changed.connect(_on_selection_changed)
	_on_selection_changed(selection.selected)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_focus_hub"):
		camera.focus_on(region.get_platform_position("Hub"))
		get_viewport().set_input_as_handled()


func _spawn_starting_units() -> void:
	var units := Node3D.new()
	units.name = "Units"
	add_child(units)
	var hub: Vector3 = region.get_platform_position("Hub")

	var hero := Unit.new()
	hero.name = "Commander"
	hero.display_name = "Commander"
	hero.is_hero = true
	hero.move_speed = 7.0
	hero.body_color = Color(0.85, 0.65, 0.3)
	# Start just south of the Hub's core, on open deck tiles.
	var hub_hex := region.hex_at(hub)
	hero.position = region.hex_center(hub_hex + Vector2i(0, 1))
	units.add_child(hero)

	var spots: Array[Vector2i] = [Vector2i(-1, 2), Vector2i(0, 2), Vector2i(1, 1), Vector2i(-1, 1)]
	for i in SQUAD_SIZE:
		var r := Unit.new()
		r.name = "Riveteer%d" % (i + 1)
		r.position = region.hex_center(hub_hex + spots[i % spots.size()])
		units.add_child(r)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Hud"
	add_child(layer)
	_status = Label.new()
	_status.name = "Status"
	_status.position = Vector2(16, 16)
	_status.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_status.add_theme_constant_override("shadow_offset_x", 1)
	_status.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(_status)
	layer.add_child(_build_legend())


## Colour key for the placeholder tiles, top right.
func _build_legend() -> Control:
	var panel := PanelContainer.new()
	panel.name = "Legend"
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-16, 16)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var box := VBoxContainer.new()
	panel.add_child(box)
	for entry in SkyRegion.LEGEND:
		var row := HBoxContainer.new()
		var swatch := ColorRect.new()
		var c: Color = SkyRegion.COLORS[entry[0]]
		swatch.color = Color(c.r, c.g, c.b)
		swatch.custom_minimum_size = Vector2(14, 14)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(swatch)
		var label := Label.new()
		label.text = entry[1]
		row.add_child(label)
		box.add_child(row)
	return panel


func _on_selection_changed(units: Array[Unit]) -> void:
	var help := "Left click or drag to select, right click to move, Alt + right click to attack-move.\nQ: all on screen   H: hero   Ctrl + 1-5: save group   1-5: recall group"
	if units.is_empty():
		_status.text = "Nothing selected\n" + help
		return
	var counts := {}
	for u in units:
		counts[u.display_name] = counts.get(u.display_name, 0) + 1
	var parts := PackedStringArray()
	for n in counts:
		parts.append("%s x%d" % [n, counts[n]] if counts[n] > 1 else n)
	_status.text = "Selected: " + ", ".join(parts) + "\n" + help
