## Root of the prototype scene. Spawns the starting units on the Hub, sets up
## selection and build mode, and runs the HUD.
extends Node3D

const SQUAD_SIZE := 4

@onready var camera: RtsCamera = $RtsCamera
@onready var region: SkyRegion = $Region

var selection: SelectionController
var building: BuildController
var walkways: WalkwayBuilder
var capture: CaptureSystem
var raids: RivalRaids
var loads: LoadSystem
var economy: EconomySystem
var resources: PlayerResources
var _status: Label
var _resource_bar: Label
var _build_bar: Label
var _notice: Label
var _notice_tween: Tween


func _ready() -> void:
	camera.bounds = region.get_bounds()
	camera.position = region.get_platform_position("Hub")
	_spawn_starting_units()

	selection = SelectionController.new()
	selection.name = "SelectionController"
	selection.camera = camera
	selection.region = region
	add_child(selection)

	resources = PlayerResources.new()
	resources.name = "PlayerResources"
	add_child(resources)

	# Added after selection so it sees mouse clicks first while placing.
	building = BuildController.new()
	building.name = "BuildController"
	building.region = region
	building.camera = camera
	building.resources = resources
	add_child(building)

	walkways = WalkwayBuilder.new()
	walkways.name = "WalkwayBuilder"
	walkways.region = region
	walkways.camera = camera
	walkways.resources = resources
	add_child(walkways)

	capture = CaptureSystem.new()
	capture.name = "CaptureSystem"
	capture.region = region
	add_child(capture)

	raids = RivalRaids.new()
	raids.name = "RivalRaids"
	raids.region = region
	raids.capture = capture
	add_child(raids)

	loads = LoadSystem.new()
	loads.name = "LoadSystem"
	loads.region = region
	add_child(loads)

	economy = EconomySystem.new()
	economy.name = "EconomySystem"
	economy.region = region
	economy.resources = resources
	add_child(economy)

	_build_hud()
	selection.selection_changed.connect(_on_selection_changed)
	_on_selection_changed(selection.selected)
	resources.changed.connect(_refresh_resources)
	region.buildings_changed.connect(_refresh_resources)
	building.notice.connect(show_notice)
	building.mode_changed.connect(_on_build_mode_changed)
	walkways.notice.connect(show_notice)
	walkways.mode_changed.connect(_on_walkway_mode_changed)
	capture.platform_claimed.connect(_on_platform_claimed)
	raids.raid_sent.connect(func(n): show_notice("Ironbell sent %d walkers toward your Hub" % n))
	loads.building_lost.connect(func(b, p): show_notice("%s is overloaded: a %s broke off and fell!" % [p, b]))
	economy.grid_changed.connect(func(_e): _refresh_resources())
	_refresh_resources()
	_on_build_mode_changed("")


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
	hero.weight = 2
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

	_resource_bar = _hud_label("Resources", 20)
	_resource_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_resource_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_resource_bar.position.y = 16
	layer.add_child(_resource_bar)

	_build_bar = _hud_label("BuildBar", 16)
	_build_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_build_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_build_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_build_bar.offset_top = -40
	_build_bar.offset_bottom = -12
	_build_bar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(_build_bar)

	_notice = _hud_label("Notice", 18)
	_notice.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_notice.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_notice.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_notice.offset_top = -76
	_notice.offset_bottom = -48
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.modulate.a = 0.0
	layer.add_child(_notice)


func _hud_label(node_name: String, font_size: int) -> Label:
	var label := Label.new()
	label.name = node_name
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	return label


## Shows a short message above the build bar that fades out.
func show_notice(text: String) -> void:
	_notice.text = text
	_notice.modulate.a = 1.0
	if _notice_tween and _notice_tween.is_valid():
		_notice_tween.kill()
	_notice_tween = create_tween()
	_notice_tween.tween_interval(1.5)
	_notice_tween.tween_property(_notice, "modulate:a", 0.0, 0.6)


func _refresh_resources() -> void:
	var supply := region.power_supply()
	var demand := region.power_demand()
	var power := "Power %d / %d" % [demand, supply]
	if demand > supply:
		power += " (brownout: towers at %d%%)" % int(region.grid_efficiency() * 100)
	_resource_bar.text = "Scrap %d      %s      Crystals %d" % [resources.scrap, power, resources.crystals]


func _on_build_mode_changed(type_id: String) -> void:
	if type_id != "":
		var data := BuildingCatalog.get_data(type_id)
		_build_bar.text = "Placing %s (%d scrap, weight %d)    Left click: place    Shift: keep placing    R: rotate    Esc / right click: cancel" % [data.name, data.cost, data.weight]
		return
	var parts := PackedStringArray()
	for i in BuildingCatalog.HOTKEY_ORDER.size():
		var data := BuildingCatalog.get_data(BuildingCatalog.HOTKEY_ORDER[i])
		parts.append("%s %s (%d)" % [BuildingCatalog.HOTKEY_LABELS[i], data.name, data.cost])
	_build_bar.text = "    ".join(parts) + "    T Walkway    Del: demolish    G: send Ironbell raid"


func _on_walkway_mode_changed(active: bool) -> void:
	if active:
		_build_bar.text = "Building a walkway (%d scrap per tile): click a tile on your platform, then a tile on another platform    Esc / right click: cancel" % SkyRegion.WALKWAY_COST_PER_TILE
	else:
		_on_build_mode_changed("")


func _on_platform_claimed(platform_name: String, new_owner: String) -> void:
	if new_owner == "player":
		show_notice("You claimed %s" % platform_name)
	else:
		show_notice("Ironbell claimed %s" % platform_name)


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
