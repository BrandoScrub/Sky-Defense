## Builds the sky region from LevelLayout as placeholder hex tiles, and answers
## questions about it: which tile or platform is at a point, what is walkable,
## and how to walk from one point to another.
class_name SkyRegion
extends Node3D

const Layout = preload("res://scripts/world/level_layout.gd")

const DECK_HEIGHT := 1.0
const WALKWAY_HEIGHT := 0.35
const CLOUD_HEIGHT := 4.0
const FERRY_HEIGHT := 3.0
const AIR_LANE_HEIGHT := 9.0
## Tiles are drawn slightly smaller than the grid so their edges show.
const TILE_GAP := 0.94

## Tile types that units can stand on.
const WALKABLE := {
	"deck": true, "walkway": true, "generator_socket": true, "harvester_anchor": true,
	"scrap_heap": true, "crystal_seam": true, "dock": true, "spawn": true,
}

const COLORS := {
	"hub": Color(0.72, 0.56, 0.3),
	"neutral": Color(0.5, 0.52, 0.55),
	"rival": Color(0.5, 0.2, 0.18),
	"walkway": Color(0.3, 0.31, 0.33),
	"core": Color(0.45, 0.28, 0.12),
	"rival_core": Color(0.25, 0.08, 0.06),
	"generator_socket": Color(0.95, 0.85, 0.2),
	"harvester_anchor": Color(0.3, 0.6, 1.0),
	"scrap_heap": Color(0.55, 0.33, 0.18),
	"crystal_seam": Color(0.3, 0.95, 0.9),
	"dock": Color(0.2, 0.65, 0.6),
	"spawn": Color(1.0, 0.5, 0.1),
	"cloud": Color(0.4, 0.55, 1.0, 0.35),
	"ferry": Color(0.2, 0.75, 0.7, 0.8),
	"air_lane": Color(1.0, 0.3, 0.25, 0.35),
	"underside": Color(0.25, 0.24, 0.24),
}

## Human-readable names for the legend.
const LEGEND := [
	["hub", "Your platform"], ["core", "Your headquarters"], ["neutral", "Neutral platform"],
	["rival", "Rival platform"], ["rival_core", "Rival headquarters"],
	["walkway", "Walkway"], ["generator_socket", "Generator socket"],
	["harvester_anchor", "Storm harvester anchor"], ["scrap_heap", "Scrap heap"],
	["crystal_seam", "Crystal seam"], ["dock", "Ferry dock"], ["spawn", "Rival wave spawn"],
	["cloud", "Storm cloud"], ["ferry", "Ferry route"], ["air_lane", "Rival air lane"],
]

var tile_size := Layout.TILE_SIZE

## hex (Vector2i) -> {"type": String, "platform": String}
var tiles := {}
## platform name -> its layout entry
var platforms := {}
## cloud name -> its layout entry
var clouds := {}
var walkway_count := 0
## cloud name -> hexes it covers (clouds float above the deck, not on it).
var tiles_in_clouds := {}

## Emitted when a building is placed or removed.
signal buildings_changed
## Emitted when a platform changes hands.
signal owner_changed(platform_name: String, new_owner: String)
## Emitted when a walkway is added at runtime.
signal walkways_changed

## Walkway cost per tile and the longest walkway the player can build.
const WALKWAY_COST_PER_TILE := 15
const WALKWAY_MAX_TILES := 8

## Who owns each platform: "player", "rival" or "" for neutral.
var owners := {}
## hex -> Building standing on it.
var buildings := {}

## platform name -> overload state written by LoadSystem ("Stable" etc.)
var load_states := {}
var _labels := {}
## platform name -> extra status line for its label (claim progress etc.)
var _label_status := {}
var _tile_nodes := {}
var _astar := AStar3D.new()
var _astar_ids := {}
var _hex_mesh_cache := {}
var _material_cache := {}


func _ready() -> void:
	for p in Layout.PLATFORMS:
		platforms[p.name] = p
		owners[p.name] = {"hub": "player", "rival": "rival"}.get(p.kind, "")
	for c in Layout.CLOUDS:
		clouds[c.name] = c

	for p in Layout.PLATFORMS:
		_lay_platform(p)
	for p in Layout.PLATFORMS:
		_lay_features(p)
	for w in Layout.WALKWAYS:
		_lay_walkway(w[0], w[1])
	for f in Layout.FERRY_ROUTES:
		_draw_ferry_route(f[0], f[1])
	for c in Layout.CLOUDS:
		_draw_cloud(c)
	for a in Layout.AIR_LANES:
		_draw_air_lane(a[0], a[1])

	_build_tiles()
	_build_walk_graph()


# --- Queries ----------------------------------------------------------------

func hex_at(point: Vector3) -> Vector2i:
	return HexGrid.from_world(point, tile_size)


func hex_center(hex: Vector2i) -> Vector3:
	return HexGrid.to_world(hex, tile_size)


func get_tile(hex: Vector2i) -> Dictionary:
	return tiles.get(hex, {})


func tiles_of_platform(platform_name: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for hex in tiles:
		if tiles[hex].platform == platform_name:
			out.append(hex)
	return out


func get_platform_position(platform_name: String) -> Vector3:
	return hex_center(platforms[platform_name].center)


## Name of the platform under a point, or "" for walkways and open sky.
func platform_at(point: Vector3) -> String:
	return get_tile(hex_at(point)).get("platform", "")


func is_walkable(point: Vector3) -> bool:
	return is_hex_walkable(hex_at(point))


## Walkable tile with nothing built on it.
func is_hex_walkable(hex: Vector2i) -> bool:
	return _astar_ids.has(hex) and not _astar.is_point_disabled(_astar_ids[hex])


## The point itself if walkable, otherwise the centre of the nearest walkable tile.
func snap_to_walkable(point: Vector3) -> Vector3:
	if is_walkable(point):
		return Vector3(point.x, 0.0, point.z)
	var id := _astar.get_closest_point(Vector3(point.x, 0.0, point.z))
	return _astar.get_point_position(id)


## Waypoints from one point to another across decks and walkways, ending at
## `to`. Empty if `to` isn't walkable or can't be reached on foot.
##
## With `through_buildings`, buildings don't block the route: raiders use this
## when the player has walled off a walkway, and smash through.
func find_route(from: Vector3, to: Vector3, through_buildings := false) -> PackedVector3Array:
	var route := PackedVector3Array()
	var goal_hex := hex_at(to)
	if not _astar_ids.has(goal_hex) or (not through_buildings and not is_hex_walkable(goal_hex)):
		return route
	var blocked: Array[int] = []
	if through_buildings:
		for hex in buildings:
			if _astar_ids.has(hex):
				blocked.append(_astar_ids[hex])
				_astar.set_point_disabled(_astar_ids[hex], false)
	var start_id := _astar.get_closest_point(Vector3(from.x, 0.0, from.z))
	var path := _astar.get_point_path(start_id, _astar_ids[goal_hex])
	for id in blocked:
		_astar.set_point_disabled(id, true)
	if path.is_empty():
		return route
	path[path.size() - 1] = Vector3(to.x, 0.0, to.z)
	if through_buildings:
		return path
	return _smooth(Vector3(from.x, 0.0, from.z), path)


## Platforms a route passes through when walked from `from`, in order.
func platforms_along(from: Vector3, route: PackedVector3Array) -> PackedStringArray:
	var out := PackedStringArray()
	var prev := from
	for point in route:
		var steps := int(ceil(prev.distance_to(point) / (tile_size * 0.5)))
		for s in range(steps + 1):
			var platform_name := platform_at(prev.lerp(point, float(s) / maxi(steps, 1)))
			if platform_name != "" and (out.is_empty() or out[out.size() - 1] != platform_name):
				out.append(platform_name)
		prev = point
	return out


## Rectangle on the XZ plane covering every tile, for camera bounds.
func get_bounds() -> Rect2:
	var rect := Rect2()
	var first := true
	for hex in tiles:
		var c := hex_center(hex)
		if first:
			rect = Rect2(c.x, c.z, 0, 0)
			first = false
		else:
			rect = rect.expand(Vector2(c.x, c.z))
	return rect.grow(tile_size * 2.0)


# --- Buildings --------------------------------------------------------------

## Why a building can't go on this tile, or "" if it can. Doesn't check cost
## or units standing there; BuildController handles those.
func build_problem(type_id: String, hex: Vector2i) -> String:
	var tile := get_tile(hex)
	if tile.is_empty() or tile.type == "walkway":
		return "Buildings go on platform decks"
	if owners.get(tile.platform, "") != "player":
		return "You don't own %s yet" % tile.platform
	if buildings.has(hex):
		return "Something is already built there"
	var allowed: Array = BuildingCatalog.get_data(type_id).tiles
	if not allowed.has(tile.type):
		if type_id == "harvester":
			return "Cloud Harvesters go on a storm harvester anchor"
		return "Can't build on a %s" % tile.type.replace("_", " ")
	return ""


## Places a building on a tile. The caller checks build_problem first.
func place_building(building: Building, hex: Vector2i, facing := 0) -> void:
	var tile := get_tile(hex)
	building.hex = hex
	building.platform = tile.platform
	building.power = BuildingCatalog.power_for(building.type_id, tile.type)
	building.faction = "rival" if platform_owner(tile.platform) == "rival" else "player"
	building.position = hex_center(hex)
	building.rotation.y = facing * PI / 3.0
	if building.get_parent() == null:
		_buildings_root().add_child(building)
	buildings[hex] = building
	if _astar_ids.has(hex):
		_astar.set_point_disabled(_astar_ids[hex], true)
	_refresh_label(tile.platform)
	buildings_changed.emit()


## Removes and returns the building on a tile, or null.
func remove_building(hex: Vector2i) -> Building:
	var building: Building = buildings.get(hex)
	if building == null:
		return null
	buildings.erase(hex)
	if _astar_ids.has(hex):
		_astar.set_point_disabled(_astar_ids[hex], false)
	_refresh_label(building.platform)
	buildings_changed.emit()
	return building


## Total weight of everything built on a platform.
## Total weight on a platform: its buildings, plus units standing on it
## unless `include_units` is false.
func platform_load(platform_name: String, include_units := true) -> int:
	var total := 0
	for hex in buildings:
		var b: Building = buildings[hex]
		if b.platform == platform_name:
			total += b.get_data().weight
	if include_units and is_inside_tree():
		for group in [Unit.GROUP, Unit.ENEMY_GROUP]:
			for node in get_tree().get_nodes_in_group(group):
				if platform_at((node as Node3D).global_position) == platform_name:
					total += (node as Unit).weight
	return total


## Buildings on a platform, oldest first.
func buildings_on(platform_name: String) -> Array[Building]:
	var out: Array[Building] = []
	for b in buildings.values():
		if b.platform == platform_name:
			out.append(b)
	return out


func platform_capacity(platform_name: String) -> int:
	return platforms[platform_name].capacity


## Electricity supplied by the player's buildings.
func power_supply() -> int:
	var total := 0
	for b in buildings.values():
		if b.power > 0 and owners.get(b.platform) == "player":
			total += b.power
	return total


## Share of demand the grid can meet: 1.0 when supply covers demand.
func grid_efficiency() -> float:
	var demand := power_demand()
	if demand == 0:
		return 1.0
	return minf(1.0, float(power_supply()) / demand)


## Electricity drawn by the player's buildings.
func power_demand() -> int:
	var total := 0
	for b in buildings.values():
		if b.power < 0 and owners.get(b.platform) == "player":
			total -= b.power
	return total


func _buildings_root() -> Node3D:
	var root := get_node_or_null("Buildings") as Node3D
	if root == null:
		root = Node3D.new()
		root.name = "Buildings"
		add_child(root)
	return root


func refresh_label(platform_name: String) -> void:
	_refresh_label(platform_name)


func _refresh_label(platform_name: String) -> void:
	var label: Label3D = _labels.get(platform_name)
	if label == null:
		return
	var used := platform_load(platform_name)
	var cap := platform_capacity(platform_name)
	label.text = "%s\nLoad %d / %d" % [platform_name, used, cap]
	var state: String = load_states.get(platform_name, "Stable")
	if state != "Stable":
		label.text += "  (%s)" % state
	var status: String = _label_status.get(platform_name, "")
	if status != "":
		label.text += "\n" + status
	label.modulate = {
		"Swaying": Color(1.0, 0.9, 0.4), "Sagging": Color(1.0, 0.6, 0.3), "Failing": Color(1.0, 0.35, 0.3),
	}.get(state, Color.WHITE)


# --- Ownership --------------------------------------------------------------

func platform_owner(platform_name: String) -> String:
	return owners.get(platform_name, "")


## Hands a platform to "player", "rival" or "" and recolours its deck.
func set_platform_owner(platform_name: String, new_owner: String) -> void:
	if owners.get(platform_name) == new_owner:
		return
	owners[platform_name] = new_owner
	var color: Color = COLORS[{"player": "hub", "rival": "rival"}.get(new_owner, "neutral")]
	for hex in tiles_of_platform(platform_name):
		var node: MeshInstance3D = _tile_nodes.get(hex)
		if node:
			node.material_override = _material(color)
	owner_changed.emit(platform_name, new_owner)


## Sets the extra line under a platform's name and load, e.g. "Claiming 40%".
func set_platform_status(platform_name: String, status: String) -> void:
	if _label_status.get(platform_name, "") == status:
		return
	_label_status[platform_name] = status
	_refresh_label(platform_name)


## Every unit of a faction standing on a platform's tiles.
func units_on_platform(platform_name: String, group: String) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group(group):
		if platform_at((node as Node3D).global_position) == platform_name:
			out.append(node)
	return out


# --- Building walkways ------------------------------------------------------

## Plans a walkway from a tile on one platform to a tile on another.
## Returns {"tiles": [...new sky hexes...], "cost": int, "problem": String}.
func plan_walkway(from_hex: Vector2i, to_hex: Vector2i) -> Dictionary:
	var plan := {"tiles": [], "cost": 0, "problem": ""}
	var a := get_tile(from_hex)
	var b := get_tile(to_hex)
	if a.is_empty() or a.platform == "":
		plan.problem = "Start the walkway on a platform"
	elif platform_owner(a.platform) != "player":
		plan.problem = "Start the walkway on a platform you own"
	elif b.is_empty() or b.platform == "":
		plan.problem = "End the walkway on another platform"
	elif b.platform == a.platform:
		plan.problem = "End the walkway on a different platform"
	if plan.problem != "":
		return plan
	var line := HexGrid.line(from_hex, to_hex)
	var new_tiles: Array[Vector2i] = []
	var left_start := false
	for i in range(1, line.size() - 1):
		var hex: Vector2i = line[i]
		var t := get_tile(hex)
		if t.is_empty():
			left_start = true
			new_tiles.append(hex)
		elif left_start and t.platform != b.platform:
			plan.problem = "The walkway would run into something"
			return plan
		elif left_start and t.platform == b.platform:
			break
	if new_tiles.is_empty():
		plan.problem = "Those platforms are already touching"
	elif new_tiles.size() > WALKWAY_MAX_TILES:
		plan.problem = "Too long: walkways reach at most %d tiles" % WALKWAY_MAX_TILES
	plan.tiles = new_tiles
	plan.cost = new_tiles.size() * WALKWAY_COST_PER_TILE
	return plan


## Adds walkway tiles in the sky and links them into the walking graph.
func add_walkway(new_tiles: Array) -> void:
	for hex in new_tiles:
		tiles[hex] = {"type": "walkway", "platform": ""}
		_make_tile(hex)
		_add_walk_point(hex)
	for hex in new_tiles:
		_connect_walk_point(hex)
	walkway_count += 1
	walkways_changed.emit()


# --- Layout -----------------------------------------------------------------

func _lay_platform(p: Dictionary) -> void:
	for hex in HexGrid.disk(p.center, p.radius):
		tiles[hex] = {"type": "deck", "platform": p.name}


func _lay_features(p: Dictionary) -> void:
	for feature in p.features:
		var hex: Vector2i
		if feature[1] is Vector2i:
			hex = p.center + feature[1]
		else:
			hex = _rim_toward(p, _center_of(feature[1]))
		tiles[hex] = {"type": feature[0], "platform": p.name}


func _lay_walkway(a_name: String, b_name: String) -> void:
	var a: Dictionary = platforms[a_name]
	var b: Dictionary = platforms[b_name]
	var start := _rim_toward(a, b.center, true)
	var end := _rim_toward(b, a.center, true)
	for hex in HexGrid.line(start, end):
		if not tiles.has(hex):
			tiles[hex] = {"type": "walkway", "platform": ""}
	walkway_count += 1


## The free rim tile of a platform closest to a target hex. With `allow_used`
## a rim tile that already holds a feature can be returned.
func _rim_toward(p: Dictionary, target: Vector2i, allow_used := false) -> Vector2i:
	var target_world := hex_center(target)
	var best := p.center as Vector2i
	var best_d := INF
	for hex in HexGrid.ring(p.center, p.radius):
		if not allow_used and tiles.get(hex, {}).get("type", "deck") != "deck":
			continue
		var d := hex_center(hex).distance_to(target_world)
		if d < best_d:
			best_d = d
			best = hex
	return best


func _center_of(thing: String) -> Vector2i:
	if platforms.has(thing):
		return platforms[thing].center
	if clouds.has(thing):
		return clouds[thing].center
	push_error("Unknown layout name: " + thing)
	return Vector2i.ZERO


# --- Walking ----------------------------------------------------------------

func _build_walk_graph() -> void:
	for hex in tiles:
		if WALKABLE.has(tiles[hex].type):
			_add_walk_point(hex)
	for hex in _astar_ids:
		_connect_walk_point(hex)


func _add_walk_point(hex: Vector2i) -> void:
	var id := _astar.get_available_point_id()
	_astar.add_point(id, hex_center(hex))
	_astar_ids[hex] = id


func _connect_walk_point(hex: Vector2i) -> void:
	for n in HexGrid.neighbors(hex):
		if _astar_ids.has(n) and not _astar.are_points_connected(_astar_ids[hex], _astar_ids[n]):
			_astar.connect_points(_astar_ids[hex], _astar_ids[n])


## Drops waypoints that can be skipped by walking straight over walkable tiles.
func _smooth(from: Vector3, path: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	var anchor := from
	var i := 0
	while i < path.size():
		var furthest := i
		for j in range(path.size() - 1, i - 1, -1):
			if _clear_line(anchor, path[j]):
				furthest = j
				break
		out.append(path[furthest])
		anchor = path[furthest]
		i = furthest + 1
	return out


func _clear_line(a: Vector3, b: Vector3) -> bool:
	var steps := int(ceil(a.distance_to(b) / (tile_size * 0.25)))
	for s in range(steps + 1):
		var p := a.lerp(b, float(s) / maxi(steps, 1))
		if not is_hex_walkable(hex_at(p)):
			return false
	return true


# --- Placeholder visuals ----------------------------------------------------

func _build_tiles() -> void:
	var deck_root := Node3D.new()
	deck_root.name = "Tiles"
	add_child(deck_root)
	for hex in tiles:
		_make_tile(hex)

	for p in Layout.PLATFORMS:
		_add_underside(p)
		_add_label(p)


func _make_tile(hex: Vector2i) -> void:
	var t: Dictionary = tiles[hex]
	var kind: String = platforms[t.platform].kind if t.platform != "" else "walkway"
	var is_walkway: bool = t.type == "walkway"
	var height := WALKWAY_HEIGHT if is_walkway else DECK_HEIGHT
	var tile := MeshInstance3D.new()
	tile.name = "Tile_%d_%d" % [hex.x, hex.y]
	tile.mesh = _hex_mesh(height, tile_size * TILE_GAP)
	tile.material_override = _material(COLORS[kind])
	tile.position = hex_center(hex) + Vector3.DOWN * height / 2.0
	get_node("Tiles").add_child(tile)
	_tile_nodes[hex] = tile
	if t.type != "deck" and not is_walkway:
		_add_prop(tile, t.type, height)


func _add_prop(tile: Node3D, type: String, tile_height: float) -> void:
	var prop := MeshInstance3D.new()
	prop.name = "Prop"
	var top := tile_height / 2.0
	match type:
		"core", "rival_core":
			prop.mesh = _hex_mesh(3.0, tile_size * 0.7)
			prop.position.y = top + 1.5
		"generator_socket":
			var cyl := CylinderMesh.new()
			cyl.top_radius = tile_size * 0.35
			cyl.bottom_radius = tile_size * 0.45
			cyl.height = 0.4
			prop.mesh = cyl
			prop.position.y = top + 0.2
		"harvester_anchor", "spawn":
			var torus := TorusMesh.new()
			torus.inner_radius = tile_size * 0.45
			torus.outer_radius = tile_size * 0.65
			prop.mesh = torus
			prop.position.y = top + 0.1
		"scrap_heap":
			var box := BoxMesh.new()
			box.size = Vector3(1.4, 0.8, 1.0)
			prop.mesh = box
			prop.position.y = top + 0.4
			prop.rotation.y = 0.5
		"crystal_seam":
			var shard := CylinderMesh.new()
			shard.top_radius = 0.0
			shard.bottom_radius = 0.6
			shard.height = 2.0
			shard.radial_segments = 4
			prop.mesh = shard
			prop.position.y = top + 1.0
		"dock":
			var pier := BoxMesh.new()
			pier.size = Vector3(0.6, 2.5, 0.6)
			prop.mesh = pier
			prop.position.y = top + 1.25
	prop.material_override = _material(COLORS[type], type == "crystal_seam" or type == "spawn")
	tile.add_child(prop)


func _add_underside(p: Dictionary) -> void:
	# An inverted cone of rock and machinery so platforms read as floating.
	var cone := MeshInstance3D.new()
	cone.name = "Underside_" + p.name.replace(" ", "")
	var mesh := CylinderMesh.new()
	var radius: float = tile_size * HexGrid.SQRT3 * (p.radius + 0.4)
	mesh.top_radius = radius
	mesh.bottom_radius = radius * 0.15
	mesh.height = 4.0 + p.radius * 2.0
	mesh.radial_segments = 6
	cone.mesh = mesh
	cone.material_override = _material(COLORS.underside)
	cone.position = hex_center(p.center) + Vector3.DOWN * (DECK_HEIGHT + mesh.height / 2.0)
	cone.rotation.y = PI / 6.0
	add_child(cone)


func _add_label(p: Dictionary) -> void:
	var label := Label3D.new()
	label.name = "Label_" + p.name.replace(" ", "")
	label.text = "%s\nLoad 0 / %d" % [p.name, p.capacity]
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 64
	label.outline_size = 12
	label.pixel_size = 0.02
	label.position = hex_center(p.center) + Vector3.UP * (6.0 + p.radius)
	add_child(label)
	_labels[p.name] = label


func _draw_cloud(c: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "Cloud_" + c.name.replace(" ", "")
	add_child(root)
	for hex in HexGrid.disk(c.center, c.radius):
		var puff := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = tile_size * 1.1
		sphere.height = tile_size * 1.3
		puff.mesh = sphere
		puff.material_override = _material(COLORS.cloud, true)
		puff.position = hex_center(hex) + Vector3.UP * CLOUD_HEIGHT
		root.add_child(puff)
	tiles_in_clouds[c.name] = HexGrid.disk(c.center, c.radius)


func _draw_ferry_route(a_name: String, b_name: String) -> void:
	var a := _find_feature(a_name, "dock")
	var b := _find_feature(b_name, "dock")
	_draw_markers("Ferry_%s_%s" % [a_name, b_name], a, b, FERRY_HEIGHT, COLORS.ferry, 0.5)


func _draw_air_lane(a_name: String, b_name: String) -> void:
	var a: Vector2i = platforms[a_name].center
	var b: Vector2i = platforms[b_name].center
	_draw_markers("AirLane_%s_%s" % [a_name, b_name], a, b, AIR_LANE_HEIGHT, COLORS.air_lane, 0.6)


func _draw_markers(node_name: String, a: Vector2i, b: Vector2i, height: float, color: Color, scale_factor: float) -> void:
	var root := Node3D.new()
	root.name = node_name.replace(" ", "")
	add_child(root)
	var line := HexGrid.line(a, b)
	for i in range(1, line.size() - 1):
		var marker := MeshInstance3D.new()
		marker.mesh = _hex_mesh(0.15, tile_size * scale_factor)
		marker.material_override = _material(color, true)
		marker.position = hex_center(line[i]) + Vector3.UP * height
		root.add_child(marker)


func _find_feature(platform_name: String, type: String) -> Vector2i:
	for hex in tiles:
		if tiles[hex].platform == platform_name and tiles[hex].type == type:
			return hex
	return platforms[platform_name].center


func _hex_mesh(height: float, radius: float) -> CylinderMesh:
	var key := Vector2(height, radius)
	if not _hex_mesh_cache.has(key):
		var mesh := CylinderMesh.new()
		mesh.top_radius = radius
		mesh.bottom_radius = radius
		mesh.height = height
		mesh.radial_segments = 6
		mesh.rings = 1
		_hex_mesh_cache[key] = mesh
	return _hex_mesh_cache[key]


func _material(color: Color, glow := false) -> StandardMaterial3D:
	var key := [color, glow]
	if _material_cache.has(key):
		return _material_cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if glow:
		mat.emission_enabled = true
		mat.emission = Color(color.r, color.g, color.b)
		mat.emission_energy_multiplier = 0.8
	_material_cache[key] = mat
	return mat
