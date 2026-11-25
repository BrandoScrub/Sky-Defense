## The info card in the bottom-right corner. Left click anything in the world
## (a unit, building, headquarters, platform, tile feature, storm cloud, ferry
## route or air lane) to see what it is and a short summary of what it does.
## Clicking empty sky, the x button or Esc hides it.
class_name InfoPanel
extends PanelContainer

const WIDTH := 320.0
## Mouse travel in pixels before a click counts as a drag (a box select).
const CLICK_SLOP := 6.0
## Click radius in pixels for picking units.
const PICK_RADIUS := 28.0

## What each kind of unit is for, by display name.
const UNIT_INFO := {
	"Commander": "Leads your squad. Tougher and faster than a Riveteer, and can shoot aircraft. Comes back to the Hub 15 seconds after falling.",
	"Riveteer": "Your basic soldier. Claims neutral platforms by standing on them and fights walkers. Can't hit aircraft. Train more from the Army tab.",
	"Ironbell Walker": "Ironbell's ground trooper. Marches down walkways toward your Hub, claiming platforms and smashing buildings on the way. Pays scrap when killed.",
	"Vesper Bomber": "Vesper's bomber airship. Flies the red air lanes and bombs your buildings and Hub. Only anti-air can hit it: Flak Batteries, the Commander and headquarters guns.",
}

## What each building is for, by type id.
const BUILDING_INFO := {
	"dynamo": "Burns fuel to power your towers. Makes more on a yellow generator socket.",
	"harvester": "Taps a storm cloud from a blue anchor. Gives lots of power, slowly forms crystals, and counts toward who controls the storm.",
	"rivet_turret": "All-round gun tower. Good against walkers; only scratches aircraft.",
	"flak_battery": "Anti-air guns. Shreds Vesper bombers; weak against walkers.",
	"arc_coil": "Chain lightning that jumps between up to 3 walkers. Power hungry, and can't hit aircraft.",
}

## What each tile feature is for, by tile type.
const TILE_INFO := {
	"generator_socket": ["Generator socket", "A Dynamo Generator built here makes 15 power instead of 10."],
	"harvester_anchor": ["Storm harvester anchor", "Cloud Harvesters can only be built here. They tap the nearest storm cloud for power and crystals."],
	"scrap_heap": ["Scrap heap", "Salvage. Produces scrap over time while you own this platform."],
	"crystal_seam": ["Crystal seam", "A seam of energized crystals. Mining it comes in a later update."],
	"dock": ["Ferry dock", "Airships stop here. Right click a platform with no walkway and your units ride the ferry there."],
	"spawn": ["Rival wave spawn", "Rival walkers set out from here when a wave starts."],
	"walkway": ["Walkway", "A metal walkway between platforms. Units walk along it. Build more from the Economy tab."],
}

var region: SkyRegion
var camera: RtsCamera
var selection: SelectionController
var building: BuildController
var walkways: WalkwayBuilder
var combat: CombatSystem
var storms: StormSystem
var loads: LoadSystem
var fog: FogSystem

## The thing being described: a Node3D, or a Dictionary for map features.
var shown = null

var _title: Label
var _subtitle: Label
var _body: Label
var _stats: Label
var _press_at = null


func _init() -> void:
	name = "InfoPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_left = -12
	offset_right = -12
	offset_top = -12
	offset_bottom = -12

	var box := VBoxContainer.new()
	box.name = "Box"
	box.custom_minimum_size.x = WIDTH
	add_child(box)
	var top := HBoxContainer.new()
	box.add_child(top)
	_title = Label.new()
	_title.name = "Title"
	_title.add_theme_font_size_override("font_size", 20)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top.add_child(_title)
	var close := Button.new()
	close.text = "x"
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.tooltip_text = "Close (Esc)"
	close.pressed.connect(clear)
	top.add_child(close)
	_subtitle = _label("Subtitle", 13, Color(1.0, 0.85, 0.45))
	box.add_child(_subtitle)
	_body = _label("Body", 15, Color.WHITE)
	box.add_child(_body)
	_stats = _label("Stats", 13, Color(1, 1, 1, 0.75))
	box.add_child(_stats)
	visible = false


func _label(node_name: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.name = node_name
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = WIDTH
	label.add_theme_font_size_override("font_size", font_size)
	label.modulate = color
	return label


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("select"):
		# Only a plain click counts: not one that places a building or walkway.
		var busy := (building and building.placing != "") or (walkways and walkways.active)
		_press_at = null if busy else get_viewport().get_mouse_position()
	elif event.is_action_released("select") and _press_at != null:
		var at := get_viewport().get_mouse_position()
		if at.distance_to(_press_at) <= CLICK_SLOP:
			show_at(at)
		_press_at = null
	elif event.is_action_pressed("building_cancel") and visible:
		clear()


func _process(_delta: float) -> void:
	# Keep live numbers (health, load, storm control) up to date.
	if visible:
		if shown is Node and not is_instance_valid(shown):
			clear()
		else:
			_refresh()


## Describes whatever is at a screen point, or hides the card if nothing is.
func show_at(screen: Vector2) -> void:
	var thing = pick(screen)
	if thing == null:
		clear()
	else:
		show_thing(thing)


func show_thing(thing) -> void:
	shown = thing
	visible = true
	_refresh()
	# Shrink to fit the new text, keeping the bottom-right corner in place.
	offset_left = offset_right
	offset_top = offset_bottom


func clear() -> void:
	shown = null
	visible = false


## What is under a screen point: a Unit, Building or Headquarters, or a
## Dictionary {"kind": ...} for platforms, tiles, clouds, ferries and air
## lanes. Returns null for empty sky.
func pick(screen: Vector2):
	var unit := _unit_at(screen)
	if unit:
		return unit
	# Nothing to learn about sky still hidden in the storm.
	var under = _point_at(screen, 0.0)
	if fog and under != null and not fog.is_explored(under):
		return null
	var cloud := _cloud_at(screen)
	if cloud != "":
		return {"kind": "cloud", "name": cloud}
	var ground = _point_at(screen, 0.0)
	if ground != null:
		var hex := region.hex_at(ground)
		var b: Building = region.buildings.get(hex)
		if b and is_instance_valid(b):
			return b
		var tile := region.get_tile(hex)
		if not tile.is_empty():
			if tile.type in ["core", "rival_core"] and combat:
				var hq := combat.headquarters_on(tile.platform)
				if hq and is_instance_valid(hq):
					return hq
			if TILE_INFO.has(tile.type):
				return {"kind": "tile", "type": tile.type, "platform": tile.platform, "target": tile.get("target", "")}
			return {"kind": "platform", "name": tile.platform}
	var route := _route_at(screen)
	if not route.is_empty():
		return route
	return null


func _refresh() -> void:
	var info := describe(shown)
	_title.text = info.title
	_subtitle.text = info.subtitle
	_subtitle.visible = info.subtitle != ""
	_body.text = info.body
	_stats.text = info.stats
	_stats.visible = info.stats != ""


## Title, subtitle, body and stats text for a picked thing.
func describe(thing) -> Dictionary:
	var info := {"title": "", "subtitle": "", "body": "", "stats": ""}
	if thing is Unit:
		var u: Unit = thing
		info.title = u.display_name
		info.subtitle = "Yours" if u.faction == "player" else "Enemy"
		if u.is_hero:
			info.subtitle = "Your hero"
		info.body = UNIT_INFO.get(u.display_name, "")
		var stats := ["Health %d / %d" % [ceili(u.hp), int(u.max_hp)], "Damage %d" % int(u.damage), "Range %d" % int(u.attack_range)]
		if u.flying:
			stats.append("Flying")
		info.stats = "   ".join(stats)
	elif thing is Building:
		var b: Building = thing
		var data := b.get_data()
		info.title = data.name
		info.subtitle = ("Yours" if b.faction == "player" else "Rival") + " · on " + b.platform
		info.body = BUILDING_INFO.get(b.type_id, "")
		var stats := ["Health %d / %d" % [ceili(b.hp), int(b.max_hp)]]
		if b.power > 0:
			stats.append("Makes %d power" % b.power)
		elif b.power < 0:
			stats.append("Uses %d power" % -b.power)
		stats.append("Weight %d" % data.weight)
		if data.has("attack"):
			stats.append("Damage %d, range %d" % [int(data.attack.damage), int(data.attack.range)])
		if b.efficiency < 1.0:
			stats.append("Brownout: %d%% speed" % int(b.efficiency * 100))
		info.stats = "   ".join(stats)
	elif thing is Headquarters:
		var hq: Headquarters = thing
		var corp: String = region.platforms.get(hq.platform, {}).get("corp", "")
		if hq.faction == "player":
			info.title = "Your Headquarters"
			info.subtitle = "Hub"
			info.body = "The heart of your sky city. Its guns defend the Hub and can hit aircraft. If it falls, you lose."
		else:
			info.title = hq.platform
			info.subtitle = "%s headquarters" % (corp if corp != "" else "Rival")
			info.body = "The rival's base. Its guns defend the platform. Destroy it and %s stops attacking; destroy every rival headquarters to win." % (corp if corp != "" else "that rival")
		info.stats = "Health %d / %d   Damage %d, range %d" % [ceili(hq.hp), int(hq.max_hp), int(hq.attack.damage), int(hq.attack.range)]
	elif thing is Dictionary:
		match thing.kind:
			"platform":
				_describe_platform(thing.name, info)
			"tile":
				info.title = TILE_INFO[thing.type][0]
				info.subtitle = "On " + thing.platform if thing.platform != "" else ""
				info.body = TILE_INFO[thing.type][1]
				if thing.type == "harvester_anchor" and region.clouds.has(thing.target):
					info.stats = "Faces the " + thing.target
			"cloud":
				info.title = thing.name
				info.subtitle = "Storm cloud"
				info.body = "An electromagnetic storm. Whoever has more Cloud Harvesters on it controls it: yours add power to your grid, a rival's throws lightning at your units and buildings nearby."
				if storms:
					var count := storms.harvesters_on(thing.name)
					var who: String = {"player": "You", "rival": "Rival"}.get(storms.control.get(thing.name, ""), "Nobody")
					info.stats = "Controlled by: %s   Your harvesters %d, rival %d" % [who, count.player, count.rival]
			"ferry":
				info.title = "Ferry route"
				info.subtitle = "%s to %s" % [thing.a, thing.b]
				info.body = "An airship shuttles between the two docks. Right click the far platform and your units walk to the dock and ride across."
			"air_lane":
				info.title = "Rival air lane"
				info.subtitle = "%s to %s" % [thing.a, thing.b]
				info.body = "Vesper bombers fly this route toward your buildings. Put Flak Batteries under it."
	return info


func _describe_platform(platform_name: String, info: Dictionary) -> void:
	var p: Dictionary = region.platforms.get(platform_name, {})
	var owner := region.platform_owner(platform_name)
	info.title = platform_name
	info.subtitle = {"player": "Your platform", "rival": "Rival platform"}.get(owner, "Neutral platform")
	match owner:
		"player":
			info.body = "You can build here. Keep its load under the limit or it sways, sags, and starts dropping buildings."
		"rival":
			info.body = "Held by a rival. Send units to stand on it to take it back."
		_:
			info.body = "Nobody owns it yet. Park units on it to claim it, then you can build here."
	if platform_name == "Hub":
		info.body = "Your home platform and headquarters. Build defenses here first."
	var features := PackedStringArray()
	for f in p.get("features", []):
		var t: String = f[0] if f is Array else (f.get("type", "") if f is Dictionary else str(f))
		if TILE_INFO.has(t) and not TILE_INFO[t][0] in features:
			features.append(TILE_INFO[t][0])
	var stats := "Load %d / %d" % [region.platform_load(platform_name), region.platform_capacity(platform_name)]
	var state: String = region.load_states.get(platform_name, "")
	if state != "" and state != "Stable":
		stats += " (%s)" % state
	if not features.is_empty():
		stats += "\nHas: " + ", ".join(features)
	info.stats = stats


func _unit_at(screen: Vector2) -> Unit:
	var cam := camera.camera
	var best: Unit = null
	var best_dist := PICK_RADIUS
	for node in get_tree().get_nodes_in_group(Unit.GROUP) + get_tree().get_nodes_in_group(Unit.ENEMY_GROUP):
		var u := node as Unit
		if u == null or not u.visible:
			continue
		var world := u.global_position + Vector3.UP
		if cam.is_position_behind(world):
			continue
		var d := screen.distance_to(cam.unproject_position(world))
		if d < best_dist:
			best_dist = d
			best = u
	return best


func _cloud_at(screen: Vector2) -> String:
	var height := region.hex_center(Vector2i.ZERO).y + SkyRegion.CLOUD_HEIGHT
	var point = _point_at(screen, height)
	if point == null:
		return ""
	var hex := region.hex_at(point)
	for cloud in region.clouds:
		var c: Dictionary = region.clouds[cloud]
		if HexGrid.distance(hex, c.center) <= c.radius:
			return cloud
	return ""


## The ferry route or air lane under a screen point, or {}.
func _route_at(screen: Vector2) -> Dictionary:
	var base := region.hex_center(Vector2i.ZERO).y
	var checks := [
		["ferry", region.layout.get("ferry_routes", []), SkyRegion.FERRY_HEIGHT, true],
		["air_lane", region.layout.get("air_lanes", []), SkyRegion.AIR_LANE_HEIGHT, false],
	]
	for check in checks:
		var point = _point_at(screen, base + check[2])
		if point == null:
			continue
		var flat := Vector2(point.x, point.z)
		for pair in check[1]:
			var a := _route_end(pair[0], check[3])
			var b := _route_end(pair[1], check[3])
			var closest := Geometry2D.get_closest_point_to_segment(flat, a, b)
			if flat.distance_to(closest) < region.tile_size:
				return {"kind": check[0], "a": pair[0], "b": pair[1]}
	return {}


func _route_end(platform_name: String, at_dock: bool) -> Vector2:
	var hex: Vector2i = region.platforms[platform_name].center
	if at_dock:
		for h in region.tiles_of_platform(platform_name):
			if region.get_tile(h).type == "dock":
				hex = h
	var w := region.hex_center(hex)
	return Vector2(w.x, w.z)


func _point_at(screen: Vector2, height: float):
	var cam := camera.camera
	return Plane(Vector3.UP, height).intersects_ray(cam.project_ray_origin(screen), cam.project_ray_normal(screen))
