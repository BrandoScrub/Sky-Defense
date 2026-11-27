## The info card in the bottom-right corner. Left click anything in the world
## (a unit, building, headquarters, platform, tile feature, storm cloud or
## air lane) to see what it is and a short summary of what it does.
## Clicking empty sky, the x button or Esc hides it.
class_name InfoPanel
extends PanelContainer

const WIDTH := 320.0
## Mouse travel in pixels before a click counts as a drag (a box select).
const CLICK_SLOP := 6.0
## Click radius in pixels for picking units.
const PICK_RADIUS := 28.0

## What each kind of unit is for, by display name. Ground units not listed
## here use their blurb from UnitCatalog.
const UNIT_INFO := {
	"Commander": "You, in a walking rig. Tougher and quicker than any trooper, and can shoot at aircraft. Back on the Hub 15 seconds after falling.",
	"Skyhawk Interceptor": "Air-to-air patrol ship. Flies from its hangar along your Mooring Masts and hunts enemy aircraft near them. Can't hit the ground.",
	"Thunder Gunboat": "Air-to-ground patrol ship. Shells enemy troops and buildings below its route. Can't hit aircraft.",
	"Repair Tender": "Utility ship on repair duty. Mends the buildings it flies over. Doesn't fight.",
	"Scout Tender": "Utility ship on scouting duty. Fast, and sees far into the storm clouds. Doesn't fight.",
	"Troop Tender": "Utility ship carrying 3 Riveteers. Drops them wherever enemies land on its route, then flies home to reload (45 scrap). Doesn't fight.",
	"Vesper Gunship": "Vesper's escort. Rides the wind with the bombers and strafes your units and drones. Only anti-air can hit it.",
	"Ironbell Troop Carrier": "Ironbell's troop ship. Hovers over your island nearest Ironbell and drops a squad on the deck. Shoot it down first and the squad goes down with it.",
	"Vesper Bomber": "Vesper's bomber. Flies the red air lanes from upwind and bombs your buildings and Hub. Only anti-air can hit it: flak, drones, the Commander and headquarters guns.",
	"Defense Drone": "A clockwork flyer from an Airship Hangar. Chases anything that comes near, aircraft included, then flies home. The hangar winds up a new one when it's lost.",
}

## What each building is for, by type id.
static var BUILDING_INFO := {
	"dynamo": "A coal-fired dynamo that powers your towers. Makes %d power, or %d on a yellow generator socket." % [BuildingCatalog.BUILDINGS.dynamo.power, BuildingCatalog.BUILDINGS.dynamo.power_on_socket],
	"lift_engine": "An extra lift rotor under the deck. This island carries %d more weight, and the engine weighs nothing. One per island." % BuildingCatalog.BUILDINGS.lift_engine.capacity,
	"harvester": "Draws charge from a storm cloud through a blue anchor. Gives power, pays crystals each wave, and counts toward who holds the storm.",
	"rivet_turret": "A sturdy gun tower for walkers. Its plating gives cover to your units fighting beside it. Can't hit aircraft.",
	"arc_coil": "Throws chain lightning across up to 3 walkers. Power hungry, and can't hit aircraft.",
	"rally_horn": "A brass horn blaring marching tunes. Its own gun is weak, but nearby troops hit harder and fire faster. Can't hit aircraft.",
	"flak_battery": "Rapid anti-air guns. Shreds bombers and other aircraft, ignores everything on the ground.",
	"skyhook_cannon": "A long harpoon gun for big airships. Slow, but every hit tears the envelope. Ignores the ground.",
	"turbine_engine": "A big brass propeller bolted to a turbine island. With 4 on one island you can steer it (Industry tab). It drifts up to 4 hexes, drops its walkways after a warning, and draws 30 power while under way.",
	"airship_hangar": "Keeps 2 defense drones aloft and builds your patrol ships (Army tab, Z X). Ships fly a loop from here through your Mooring Masts. Holds 4. If it falls, its ships go to another hangar or go down.",
	"mooring_mast": "A waypoint for your patrol ships. Ships only hunt within reach of a hangar or mast, so masts decide which sky you cover. It also sees far into the storm clouds.",
}

## What each tile feature is for, by tile type.
static var TILE_INFO := {
	"generator_socket": ["Generator socket", "A Dynamo built here makes %d power instead of %d." % [BuildingCatalog.BUILDINGS.dynamo.power_on_socket, BuildingCatalog.BUILDINGS.dynamo.power]],
	"harvester_anchor": ["Storm anchor", "Cloud Harvesters go here. They tap the nearest storm cloud for power and crystals."],
	"scrap_heap": ["Scrap heap", "Salvage left by the Rising. Pays scrap at the end of each wave while you hold this island."],
	"crystal_seam": ["Crystal seam", "A seam of Hum-charged crystal. Pays 5 crystals a wave while you hold the island."],
	"spawn": ["Rival muster point", "Rival walkers set out from here when a wave starts."],
	"walkway": ["Walkway", "Riveted decking between islands. Lay new ones from the Industry tab to expand."],
	"rival_walkway": ["Ironbell bridge", "A span Ironbell's crews built toward your Hub. Their walkers march along it, and so can yours."],
}

var region: SkyRegion
var camera: RtsCamera
var selection: SelectionController
var building: BuildController
var walkways: WalkwayBuilder
var combat: CombatSystem
var storms: StormSystem
var defenses: DefenseSystem
var fog: FogSystem
var wind: WindSystem

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
	_title.theme_type_variation = "Title"
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
	_subtitle = _label("Subtitle", 14, HudTheme.AMBER)
	box.add_child(_subtitle)
	_body = _label("Body", 16, HudTheme.PARCHMENT)
	box.add_child(_body)
	_stats = _label("Stats", 14, Color(HudTheme.PARCHMENT, 0.75))
	box.add_child(_stats)
	visible = false


func _label(node_name: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.name = node_name
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = WIDTH
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
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
			var tile_type: String = "rival_walkway" if tile.get("builder", "") == "rival" else tile.type
			if TILE_INFO.has(tile_type):
				return {"kind": "tile", "type": tile_type, "platform": tile.platform, "target": tile.get("target", "")}
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
		info.body = UNIT_INFO.get(u.display_name, UnitCatalog.get_data(u.unit_type).blurb if not u.flying else "")
		var stats := ["Health %d / %d" % [ceili(u.hp), int(u.max_hp)]]
		if u.damage > 0.0:
			stats.append("Damage %d" % roundi(u.get_damage()))
		if u.heal_power > 0.0:
			stats.append("Heals %d/s" % int(u.heal_power))
		stats.append("Range %s" % str(snappedf(u.get_attack_range(), 0.1)))
		if u.shield > 0.0:
			stats.append("Shield %d%%" % int(u.shield * 100))
		if u.armored:
			stats.append("Armored")
		if u.vs_armor > 1.0:
			stats.append("x%s vs armor" % str(u.vs_armor))
		if u.vs_buildings > 1.0:
			stats.append("x%s vs buildings" % str(u.vs_buildings))
		if u.repair_power > 0.0:
			stats.append("Repairs %d/s" % int(u.repair_power))
		if u.flying:
			stats.append("Flying")
		if u.air_only:
			stats.append("Air targets only")
		if u.damage_mult > 1.0 or u.cooldown_mult < 1.0 or u.armor > 0.0:
			stats.append("Boosted by nearby defenses")
		if not u.buff_ids().is_empty():
			stats.append("Buffs: " + ", ".join(PackedStringArray(u.buff_ids().map(func(id): return String(id).capitalize()))))
		info.stats = "   ".join(stats)
	elif thing is Building:
		var b: Building = thing
		var data := b.get_data()
		info.title = data.name
		info.subtitle = ("Yours" if b.faction == "player" else "Rival") + " · on " + b.platform
		info.body = BUILDING_INFO.get(b.type_id, "")
		if data.has("role"):
			info.subtitle += " · " + String(data.role).capitalize() + (" defense" if data.role == "ground" else "")
		var stats := ["Health %d / %d" % [ceili(b.hp), int(b.max_hp)]]
		if b.power > 0:
			stats.append("Makes %d power" % b.power)
		elif b.power < 0:
			stats.append("Uses %d power" % -b.power)
		stats.append("Weight %d" % data.weight)
		stats.append_array(Array(BuildMenu.defense_lines(data)))
		if data.has("hangar") and defenses:
			stats.append("Drones up: %d / %d" % [defenses.drones_of(b).size(), int(data.hangar.drones)])
		if b.efficiency < 1.0:
			stats.append("Brownout: %d%% speed" % int(b.efficiency * 100))
		info.stats = "   ".join(stats)
	elif thing is Headquarters:
		var hq: Headquarters = thing
		var corp: String = region.platforms.get(hq.platform, {}).get("corp", "")
		if hq.faction == "player":
			info.title = "Your Headquarters"
			info.subtitle = "Hub"
			info.body = "The heart of your company. Its guns cover the Hub and can hit aircraft. If it falls, the charter is lost."
		else:
			info.title = hq.platform
			info.subtitle = "%s headquarters" % (corp if corp != "" else "Rival")
			info.body = "%s's headquarters. Its guns cover the island. Wreck it and they stop attacking; ground every rival to win." % (corp if corp != "" else "The rival")
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
				info.body = "A charged storm. Whoever has more Cloud Harvesters on it holds it: yours feeds your grid, a rival's throws lightning at everything of yours nearby."
				if storms:
					var count := storms.harvesters_on(thing.name)
					var who: String = {"player": "You", "rival": "Rival"}.get(storms.control.get(thing.name, ""), "Nobody")
					info.stats = "Controlled by: %s   Your harvesters %d, rival %d" % [who, count.player, count.rival]
			"air_lane":
				info.title = "Rival air lane"
				info.subtitle = "%s to %s" % [thing.a, thing.b]
				info.body = "Vesper's bombers fly this route from upwind. It moves when the wind turns, every 3 waves. Put flak or a Hangar under it."
				if wind:
					info.stats = "Wind from the %s, turns in %d wave%s" % [wind.from_name(), wind.waves_until_shift(wind.waves.wave), "" if wind.waves_until_shift(wind.waves.wave) == 1 else "s"]
	return info


func _describe_platform(platform_name: String, info: Dictionary) -> void:
	var p: Dictionary = region.platforms.get(platform_name, {})
	var owner := region.platform_owner(platform_name)
	info.title = platform_name
	info.subtitle = {"player": "Your island", "rival": "Rival island"}.get(owner, "Unclaimed island")
	match owner:
		"player":
			info.body = "Yours to build on. Keep its load under the limit or it sways, sags and sheds buildings."
		"rival":
			info.body = "Held by a rival. Park your units on it to take it."
		_:
			info.body = "Nobody holds it yet. Park units on it to claim it."
	if platform_name == "Hub":
		info.body = "Your home island and headquarters. Fortify it first."
	if p.get("balloon", false):
		info.subtitle += ", drifting balloon"
		info.body += " It drifts between two moorings. When its walkway flashes, clear it: anything left on it falls."
	var features := PackedStringArray()
	for f in p.get("features", []):
		var t: String = f[0] if f is Array else (f.get("type", "") if f is Dictionary else str(f))
		if TILE_INFO.has(t) and not TILE_INFO[t][0] in features:
			features.append(TILE_INFO[t][0])
	var stats := "Load %d / %d" % [region.platform_load(platform_name), region.platform_capacity(platform_name)]
	if not features.is_empty():
		stats += "\nHas: " + ", ".join(features)
	info.stats = stats


func _unit_at(screen: Vector2) -> Unit:
	var cam := camera.camera
	var best: Unit = null
	var best_dist := PICK_RADIUS
	for node in get_tree().get_nodes_in_group(Unit.GROUP) + get_tree().get_nodes_in_group(Unit.ENEMY_GROUP) + get_tree().get_nodes_in_group(Unit.DRONE_GROUP):
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


## The air lane under a screen point, or {}.
func _route_at(screen: Vector2) -> Dictionary:
	var base := region.hex_center(Vector2i.ZERO).y
	# Air lanes bend around islands, so test each leg of the drawn route.
	var point = _point_at(screen, base + SkyRegion.AIR_LANE_HEIGHT)
	if point != null:
		var flat := Vector2(point.x, point.z)
		for lane in region.air_lane_routes():
			var pts: PackedVector3Array = lane[2]
			for i in range(1, pts.size()):
				var a := Vector2(pts[i - 1].x, pts[i - 1].z)
				var b := Vector2(pts[i].x, pts[i].z)
				if flat.distance_to(Geometry2D.get_closest_point_to_segment(flat, a, b)) < region.tile_size:
					return {"kind": "air_lane", "a": lane[0], "b": lane[1]}
	return {}


func _point_at(screen: Vector2, height: float):
	var cam := camera.camera
	return Plane(Vector3.UP, height).intersects_ray(cam.project_ray_origin(screen), cam.project_ray_normal(screen))
