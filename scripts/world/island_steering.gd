## Steering turbine islands. Turbine Engines can only be built on turbine
## islands; once one of your turbine islands has ENGINES_NEEDED engines you
## can order it to move: pick Steer Island on the Ships tab, click the island,
## then click open sky in the direction it should go. It moves up to
## MAX_HEXES whole hexes that way, stopping early if something is in the way.
##
## It works like the balloon islands (DriftSystem): a 6 second warning while
## every walkway attached to it flashes, then the walkways break off (units
## still on them fall) and the island moves one hex at a time with its
## buildings and the units aboard. While the engines run they draw
## STEER_POWER from your grid, and you need that much spare power to start.
class_name IslandSteering
extends Node

signal notice(text: String)
signal mode_changed(active: bool)
## An island started moving after its warning.
signal steering_started(platform_name: String, hexes: int)
## An island finished moving.
signal arrived(platform_name: String)

const ENGINE := "turbine_engine"
const ENGINES_NEEDED := 4
const MAX_HEXES := 4
## Power the engines draw while the island is warning and moving.
const STEER_POWER := 30
const WARNING := "warning"
const MOVING := "moving"

@export var region: SkyRegion
@export var camera: RtsCamera
## Shares the balloon islands' warning look, falling and klaxon.
@export var drift: DriftSystem
@export var warning_seconds := 6.0
@export var hop_seconds := 1.4

## True while the player is picking an island and a direction.
var active := false
## Island picked by the first click, or "".
var picked := ""
## platform name -> {name, dir, left, state, timer, walkway, hop, riders,
## decor: {node: base position}, tile_base: {hex: position}, plain_mats,
## cautioned, beep}
var moving := {}


func _process(delta: float) -> void:
	step(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event.is_action_pressed("select"):
		var point = _ground_under_mouse()
		if point != null:
			if picked == "":
				var p := region.platform_at(point)
				var problem := steer_problem(p)
				if problem != "":
					notice.emit(problem)
				else:
					picked = p
					notice.emit("Now click open sky in the direction %s should go" % p)
			else:
				var err := steer_toward(picked, point)
				if err != "":
					notice.emit(err)
				else:
					cancel()
		get_viewport().set_input_as_handled()
	elif event.is_action_released("select"):
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("command") or event.is_action_pressed("building_cancel"):
		cancel()
		get_viewport().set_input_as_handled()


func begin() -> void:
	active = true
	picked = ""
	mode_changed.emit(true)
	notice.emit("Click one of your turbine islands with %d Turbine Engines" % ENGINES_NEEDED)


func cancel() -> void:
	active = false
	picked = ""
	mode_changed.emit(false)


## Turbine Engines on a platform.
func engines_on(platform_name: String) -> int:
	var n := 0
	for b in region.buildings_on(platform_name):
		if b.type_id == ENGINE and b.is_alive():
			n += 1
	return n


## Why this island can't be steered now, or "".
func steer_problem(platform_name: String) -> String:
	if platform_name == "" or not region.platforms.has(platform_name):
		return "Click one of your turbine islands"
	if region.platforms[platform_name].get("style", "") != "turbine":
		return "Only turbine islands can be steered"
	if region.platform_owner(platform_name) != "player":
		return "You don't own %s" % platform_name
	if moving.has(platform_name):
		return "%s is already under way" % platform_name
	var engines := engines_on(platform_name)
	if engines < ENGINES_NEEDED:
		return "%s needs %d Turbine Engines to move (has %d)" % [platform_name, ENGINES_NEEDED, engines]
	if region.power_supply() - region.power_demand() < STEER_POWER:
		return "Steering takes %d spare power (you have %d)" % [STEER_POWER, maxi(0, region.power_supply() - region.power_demand())]
	return ""


## Orders an island toward a world point: the nearest of the 6 hex
## directions, up to MAX_HEXES. Returns "" or why it can't go.
func steer_toward(platform_name: String, point: Vector3) -> String:
	var from := region.get_platform_position(platform_name)
	var to := point - from
	to.y = 0.0
	if to.length() < region.tile_size:
		return "Click open sky away from the island"
	var best := 0
	var best_dot := -INF
	for i in 6:
		var d := region.hex_center(HexGrid.DIRECTIONS[i]) - region.hex_center(Vector2i.ZERO)
		var dot := d.normalized().dot(to.normalized())
		if dot > best_dot:
			best_dot = dot
			best = i
	var hexes := clampi(roundi(to.length() / (region.tile_size * HexGrid.SQRT3)), 1, MAX_HEXES)
	return steer(platform_name, best, hexes)


## Orders an island `hexes` steps in hex direction `dir` (0..5). Returns ""
## or why it can't go.
func steer(platform_name: String, dir: int, hexes: int) -> String:
	var problem := steer_problem(platform_name)
	if problem != "":
		return problem
	var step_vec: Vector2i = HexGrid.DIRECTIONS[dir]
	var clear := 0
	for k in range(1, hexes + 1):
		if not _clear_at(platform_name, step_vec * k):
			break
		clear = k
	if clear == 0:
		return "Something is in the way of %s that way" % platform_name
	var s := {
		"name": platform_name, "dir": step_vec, "left": clear, "state": WARNING,
		"timer": warning_seconds, "walkway": _attached_walkways(platform_name),
		"hop": 0.0, "riders": [], "decor": {}, "tile_base": {}, "plain_mats": {},
		"cautioned": [], "beep": 1.0,
	}
	moving[platform_name] = s
	_update_power()
	var players := _players(_endangered(s))
	if players > 0 and drift:
		drift._klaxon.play()
	notice.emit("%s fires up its engines: it moves %d hex%s in %ds. Clear its walkways!" % [platform_name, clear, "" if clear == 1 else "es", int(warning_seconds)])
	return ""


## Advances every moving island. Public so tests can drive it.
func step(delta: float) -> void:
	for platform_name in moving.keys():
		var s: Dictionary = moving[platform_name]
		match s.state:
			WARNING:
				s.timer -= delta
				_update_warning(s, delta)
				if s.timer <= 0.0:
					_cast_off(s)
			MOVING:
				_move(s, delta)


# --- Warning and cast off -----------------------------------------------------

func _endangered(s: Dictionary) -> Array[Unit]:
	var out: Array[Unit] = []
	var on := {}
	for hex in s.walkway:
		on[hex] = true
	for group in [Unit.GROUP, Unit.ENEMY_GROUP]:
		for node in get_tree().get_nodes_in_group(group):
			var unit := node as Unit
			if unit.flying or unit.riding or not unit.is_alive():
				continue
			if on.has(region.hex_at(unit.global_position)):
				out.append(unit)
	return out


func _players(units: Array) -> int:
	return units.filter(func(u): return u.faction == "player").size()


func _update_warning(s: Dictionary, delta: float) -> void:
	var endangered := _endangered(s)
	if drift:
		drift._set_cautions(s, endangered)
	var on := fmod(Time.get_ticks_msec() / 1000.0, 0.5) < 0.25
	for hex in s.walkway:
		var node := region.tile_node(hex)
		if node:
			if not s.plain_mats.has(hex):
				s.plain_mats[hex] = node.material_override
			node.material_override = drift._warn_mat if on and drift else s.plain_mats[hex]
	s.beep -= delta
	if s.beep <= 0.0:
		s.beep = 1.0
		if drift and _players(endangered) > 0 and not drift._klaxon.playing:
			drift._beep.play()


func _cast_off(s: Dictionary) -> void:
	var fallen := _endangered(s)
	if drift:
		drift._set_cautions(s, [])
		for unit in fallen:
			drift._fall(unit)
	for hex in s.walkway:
		var node := region.tile_node(hex)
		if node == null:
			continue
		var debris := node.duplicate() as MeshInstance3D
		debris.material_override = s.plain_mats.get(hex, node.material_override)
		region.add_child(debris)
		var tween := debris.create_tween().set_parallel()
		tween.tween_property(debris, "position:y", debris.position.y - 30.0, 1.4).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(debris, "rotation", Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)), 1.4)
		tween.chain().tween_callback(debris.queue_free)
	region.remove_tiles(s.walkway)
	s.walkway = []
	region.walkways_changed.emit()
	s.state = MOVING
	s.hop = 0.0
	steering_started.emit(s.name, s.left)


# --- Moving -------------------------------------------------------------------

func _move(s: Dictionary, delta: float) -> void:
	if s.hop == 0.0:
		if s.left <= 0 or not _clear_at(s.name, s.dir):
			_finish(s)
			return
		s.riders = []
		for unit in get_tree().get_nodes_in_group(Unit.GROUP) + get_tree().get_nodes_in_group(Unit.ENEMY_GROUP):
			if not unit.flying and not unit.riding and unit.is_alive() and region.platform_at(unit.position) == s.name:
				unit.stop()
				s.riders.append(unit)
		s.tile_base = {}
		for hex in region.tiles_of_platform(s.name):
			var node := region.tile_node(hex)
			if node:
				s.tile_base[hex] = node.position
		s.decor = _decor_of(s.name)
	var step_vec := region.hex_center(s.dir) - region.hex_center(Vector2i.ZERO)
	var before: float = s.hop
	s.hop = minf(1.0, s.hop + delta / hop_seconds)
	var moved := step_vec * (_ease(s.hop) - _ease(before))
	var offset := step_vec * _ease(s.hop)
	for hex in s.tile_base:
		var node := region.tile_node(hex)
		if node:
			node.position = s.tile_base[hex] + offset
		var building: Building = region.buildings.get(hex)
		if building:
			building.position = region.hex_center(hex) + offset
	for node in s.decor:
		if is_instance_valid(node):
			node.position = s.decor[node] + offset
	for unit in s.riders:
		if is_instance_valid(unit):
			unit.position += moved
	if s.hop >= 1.0:
		_commit_hop(s, step_vec)


func _commit_hop(s: Dictionary, step_vec: Vector3) -> void:
	var shift: Vector2i = s.dir
	var old_hexes := region.tiles_of_platform(s.name)
	var moved_tiles := {}
	for hex in old_hexes:
		moved_tiles[hex + shift] = region.get_tile(hex).duplicate()
	var carried := []
	for hex in old_hexes:
		if region.buildings.has(hex):
			carried.append(region.buildings[hex])
			region.buildings.erase(hex)
	region.remove_tiles(old_hexes)
	for building in carried:
		building.hex += shift
		building.position = region.hex_center(building.hex)
		region.buildings[building.hex] = building
	region.add_tiles(moved_tiles)
	region.platforms[s.name].center += shift
	for node in s.decor:
		if is_instance_valid(node):
			node.position = s.decor[node] + step_vec
	s.left -= 1
	s.hop = 0.0
	s.riders = []
	region.walkways_changed.emit()
	region.buildings_changed.emit()


func _finish(s: Dictionary) -> void:
	moving.erase(s.name)
	_update_power()
	_replan_spans(s.name)
	arrived.emit(s.name)
	notice.emit("%s has stopped. Build walkways to link it up again" % s.name)


## Walkways planned to this island start from where it is now.
func _replan_spans(platform_name: String) -> void:
	for key in region.planned_spans.keys():
		var names: PackedStringArray = key.split("|")
		if names.has(platform_name):
			region._plan_walkway_span(names[0], names[1])


func _update_power() -> void:
	region.engine_draw = STEER_POWER * moving.size()
	region.buildings_changed.emit()


## True if the island, moved by `shift`, would fit: no other tiles (other
## than its own walkways, which break off) on or next to its new hexes, and
## no balloon tracks or walkways under construction.
func _clear_at(platform_name: String, shift: Vector2i) -> bool:
	var own := {}
	for hex in region.tiles_of_platform(platform_name):
		own[hex] = true
	var breaking := {}
	if moving.has(platform_name):
		for hex in moving[platform_name].walkway:
			breaking[hex] = true
	else:
		for hex in _attached_walkways(platform_name):
			breaking[hex] = true
	for hex in own:
		var to: Vector2i = hex + shift
		if region.reserved_hexes.has(to) or region.pending_hexes.has(to):
			return false
		for h in HexGrid.disk(to, 1):
			if own.has(h) or breaking.has(h):
				continue
			if region.tiles.has(h):
				return false
	return true


## Walkway tiles joined to the island (walking out along each walkway until
## it reaches another platform).
func _attached_walkways(platform_name: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var seen := {}
	var todo: Array[Vector2i] = []
	for hex in region.tiles_of_platform(platform_name):
		for n in HexGrid.neighbors(hex):
			if region.get_tile(n).get("type", "") == "walkway" and region.get_tile(n).platform == "" and not seen.has(n):
				seen[n] = true
				todo.append(n)
	while not todo.is_empty():
		var hex: Vector2i = todo.pop_back()
		out.append(hex)
		for n in HexGrid.neighbors(hex):
			if not seen.has(n) and region.get_tile(n).get("type", "") == "walkway" and region.get_tile(n).platform == "":
				seen[n] = true
				todo.append(n)
	return out


## Scenery that belongs to the island (underside, lamp posts, label), with
## where each piece is now.
func _decor_of(platform_name: String) -> Dictionary:
	var out := {}
	var near := {}
	for hex in region.tiles_of_platform(platform_name):
		for h in HexGrid.disk(hex, 1):
			near[h] = true
	var tag := platform_name.replace(" ", "")
	var skip_prefixes := ["Underside_", "Trim_", "Label_", "Cloud_", "AirLane_", "Ferry_"]
	for child in region.get_children():
		if not child is Node3D or child is Building or child is Headquarters:
			continue
		var n := String(child.name)
		if n in ["Tiles", "Buildings", "WalkwayCrew"]:
			continue
		if n.ends_with("_" + tag) and (n.begins_with("Underside_") or n.begins_with("Trim_") or n.begins_with("Label_")):
			out[child] = child.position
			continue
		if skip_prefixes.any(func(p): return n.begins_with(p)):
			continue
		# Unnamed lamp posts and dressing around the island's edge.
		if child is MeshInstance3D and near.has(region.hex_at(child.position)):
			out[child] = child.position
	var label := region.platform_label(platform_name)
	if label and not out.has(label):
		out[label] = label.position
	return out


func _ground_under_mouse():
	var cam := camera.camera
	var screen := get_viewport().get_mouse_position()
	return Plane(Vector3.UP, 0.0).intersects_ray(cam.project_ray_origin(screen), cam.project_ray_normal(screen))


func _ease(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)
