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
	"vesper": Color(0.25, 0.33, 0.55),
	"walkway": Color(0.3, 0.31, 0.33),
	"rival_walkway": Color(0.42, 0.2, 0.16),
	"grassy": Color(0.36, 0.56, 0.26),
	"overcharged": Color(0.42, 0.34, 0.62),
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
	["hub", "Your platform"], ["core", "Your headquarters"], ["neutral", "Neutral platform"], ["grassy", "Grassy crystal island"], ["overcharged", "Overcharged crystal island"],
	["rival", "Ironbell platform"], ["vesper", "Vesper platform"], ["rival_core", "Rival headquarters"],
	["walkway", "Walkway"], ["rival_walkway", "Ironbell bridge"], ["generator_socket", "Generator socket"],
	["harvester_anchor", "Storm harvester anchor"], ["scrap_heap", "Scrap heap"],
	["crystal_seam", "Crystal seam"], ["dock", "Ferry dock"], ["spawn", "Rival wave spawn"],
	["cloud", "Storm cloud"], ["ferry", "Ferry route"], ["air_lane", "Rival air lane"],
]

var tile_size := Layout.TILE_SIZE

## Seed for the generated map. -1 picks a new random map each game.
@export var map_seed := -1
## How many rival corporations the map has, 2 to 4 (RivalCatalog.ORDER:
## Ironbell, Vesper, then the Nimbus and Aurum stand-ins).
@export_range(2, 4) var rival_count := 2
## When 0 or more, overrides map_seed for every region built afterwards
## (tests and screenshots use this for a repeatable map).
static var seed_override := -1
## When not empty, the rivals to lay out instead of rival_count's.
static var rivals_override: Array = []
## The map starts with no walkways between islands: you build them to expand,
## and Ironbell bridges its way toward you (RivalBridges). Tests set this to
## lay every planned walkway up front instead.
static var prebuilt_walkways := false
## Walkways normally go up with harpoons and are laid tile by tile
## (WalkwayCrew). Tests set this to lay them in one go.
static var instant_walkways := false
## The generated layout (see LevelLayout.generate).
var layout := {}

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
## One walkway tile was laid (walkways under construction go tile by tile).
signal walkway_tile_added(hex: Vector2i)
## Emitted when the drawn rival air lanes change (the wind turned).
signal air_routes_changed

## Goes up whenever tiles are added or removed, so AirNav knows to rebuild.
var tiles_version := 0
## "from|to" -> the waypoints the air lane between those platforms follows.
var air_routes := {}

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
	var chosen := seed_override if seed_override >= 0 else map_seed
	if chosen < 0:
		chosen = randi() % 1000000
	layout = Layout.generate(chosen, rivals_override if not rivals_override.is_empty() else RivalCatalog.layout_rivals(rival_count))
	for p in layout.platforms:
		platforms[p.name] = p
		owners[p.name] = {"hub": "player", "rival": "rival"}.get(p.kind, "")
	for c in layout.clouds:
		clouds[c.name] = c

	for p in layout.platforms:
		_lay_platform(p)
	for p in layout.platforms:
		_lay_features(p)
	for w in layout.walkways:
		plan_walkway_span(w[0], w[1])
		if prebuilt_walkways:
			_lay_walkway(w[0], w[1])
	for f in layout.ferry_routes:
		_draw_ferry_route(f[0], f[1])
	for c in layout.clouds:
		_draw_cloud(c)

	_build_tiles()
	_build_walk_graph()
	crew = WalkwayCrew.new()
	crew.name = "WalkwayCrew"
	crew.region = self
	add_child(crew)
	# Air lanes curve around islands, so they need the tiles first. Calm
	# until the wind picks up (VesperFleet redraws them when it turns).
	var nav := AirNav.new(self)
	for a in layout.air_lanes:
		set_air_route(a[0], a[1], nav.plan(get_platform_position(a[0]), get_platform_position(a[1])), false)


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


## Like snap_to_walkable, but stays on one platform: the nearest open hex of
## `platform_name` (so a squad sent to an odd-shaped island all lands on it).
func snap_to_platform(point: Vector3, platform_name: String) -> Vector3:
	if is_walkable(point) and platform_at(point) == platform_name:
		return Vector3(point.x, 0.0, point.z)
	var best := snap_to_walkable(point)
	var best_d := INF
	for hex in tiles_of_platform(platform_name):
		if not is_hex_walkable(hex):
			continue
		var c := hex_center(hex)
		var d := Vector2(c.x - point.x, c.z - point.z).length()
		if d < best_d:
			best_d = d
			best = Vector3(c.x, 0.0, c.z)
	return best


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
	var style: String = BuildingCatalog.get_data(type_id).get("island_style", "")
	if style != "" and platforms.get(tile.platform, {}).get("style", "") != style:
		return "%ss only fit on %s islands" % [BuildingCatalog.get_data(type_id).name, style]
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
## unless `include_units` is false. Units count for half their weight
## (rounded down), so a squad can stand on a small island without
## overloading it.
func platform_load(platform_name: String, include_units := true) -> int:
	var total := 0
	var unit_weight := 0
	for hex in buildings:
		var b: Building = buildings[hex]
		if b.platform == platform_name:
			total += b.get_data().weight
	if include_units and is_inside_tree():
		for group in [Unit.GROUP, Unit.ENEMY_GROUP]:
			for node in get_tree().get_nodes_in_group(group):
				if not node.flying and platform_at((node as Node3D).global_position) == platform_name:
					unit_weight += (node as Unit).weight
	return total + unit_weight / 2


## Buildings on a platform, oldest first.
func buildings_on(platform_name: String) -> Array[Building]:
	var out: Array[Building] = []
	for b in buildings.values():
		if b.platform == platform_name:
			out.append(b)
	return out


## Weight a platform can carry: its own, plus what its Lift Engines add.
func platform_capacity(platform_name: String) -> int:
	var cap: int = platforms[platform_name].capacity
	for b in buildings.values():
		if b.platform == platform_name and b.hp > 0.0:
			cap += b.get_data().get("capacity", 0)
	return cap


## Extra power from storm clouds the player controls (set by StormSystem).
var storm_bonus := 0


## Electricity supplied by the player's buildings and controlled storms.
func power_supply() -> int:
	var total := storm_bonus
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
## Extra power drawn by turbine islands under way (IslandSteering).
var engine_draw := 0


func power_demand() -> int:
	var total := engine_draw
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
	var color: Color = COLORS[{"player": "hub", "rival": "rival"}.get(new_owner, _neutral_kind(platform_name))]
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
		# Aircraft overhead and ferry passengers aren't standing on it.
		if node.flying or node.riding:
			continue
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
			if reserved_hexes.has(hex):
				plan.problem = "That's a balloon platform's flight path"
				return plan
			if pending_hexes.has(hex):
				plan.problem = "A walkway is already going up there"
				return plan
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
## `builder` is "player" or "rival" (rival bridges are tinted).
func add_walkway(new_tiles: Array, builder := "player") -> void:
	for hex in new_tiles:
		add_walkway_tile(hex, builder)
	finish_walkway()


## Builds a walkway the proper way: harpoons fire from `from` to `to`, then
## the tiles are laid one at a time (see WalkwayCrew). `on_done` is called
## when the last tile is down. Lays it at once with instant_walkways.
func build_walkway(new_tiles: Array, builder: String, from: Vector3, to: Vector3, on_done = null) -> void:
	if instant_walkways or crew == null:
		add_walkway(new_tiles, builder)
		if on_done is Callable:
			on_done.call()
		return
	crew.start(new_tiles, builder, from, to, on_done)


## Lays one walkway tile and links it to its neighbours.
func add_walkway_tile(hex: Vector2i, builder := "player") -> void:
	tiles[hex] = {"type": "walkway", "platform": ""}
	if builder == "rival":
		tiles[hex].builder = "rival"
	_make_tile(hex)
	_add_walk_point(hex)
	_connect_walk_point(hex)
	walkway_tile_added.emit(hex)


## Counts a finished walkway.
func finish_walkway() -> void:
	walkway_count += 1
	walkways_changed.emit()


# --- Layout -----------------------------------------------------------------

func _lay_platform(p: Dictionary) -> void:
	for hex in shape_of(p):
		tiles[hex] = {"type": "deck", "platform": p.name}


## A platform's hexes: its island outline, or a full hexagon of its radius.
func shape_of(p: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if p.has("shape"):
		for off in p.shape:
			out.append(p.center + off)
	else:
		out = HexGrid.disk(p.center, p.radius)
	return out


## A platform's edge hexes: those with open sky (or anything else) beside them.
func rim_of(p: Dictionary) -> Array[Vector2i]:
	var own := {}
	for hex in shape_of(p):
		own[hex] = true
	var out: Array[Vector2i] = []
	for hex in own:
		for n in HexGrid.neighbors(hex):
			if not own.has(n):
				out.append(hex)
				break
	return out


func _lay_features(p: Dictionary) -> void:
	for feature in p.features:
		var hex: Vector2i
		if feature[1] is Vector2i:
			hex = p.center + feature[1]
		else:
			hex = rim_toward(p, _center_of(feature[1]))
		tiles[hex] = {"type": feature[0], "platform": p.name}
		if feature[1] is String:
			# What the feature faces, e.g. the storm a harvester anchor taps.
			tiles[hex].target = feature[1]


## The open-sky hexes a planned walkway between two platforms would cover,
## e.g. a span Ironbell will bridge. Empty if they already touch.
func planned_span_tiles(a_name: String, b_name: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for hex in planned_spans.get(_span_key(a_name, b_name), []):
		if not tiles.has(hex):
			out.append(hex)
	return out


## True if two platforms are joined by tiles you can walk on.
func platforms_linked(a_name: String, b_name: String) -> bool:
	var to := snap_to_walkable(get_platform_position(b_name))
	return not find_route(snap_to_walkable(get_platform_position(a_name)), to, true).is_empty()


## Platforms joined to `start` by planned walkways (whether built yet or not).
func planned_reachable(start: String) -> Dictionary:
	var seen := {start: true}
	var todo := [start]
	while not todo.is_empty():
		var here: String = todo.pop_back()
		for w in layout.walkways:
			for k in 2:
				if w[k] == here and not seen.has(w[1 - k]):
					seen[w[1 - k]] = true
					todo.append(w[1 - k])
	return seen


func _span_key(a_name: String, b_name: String) -> String:
	return a_name + "|" + b_name if a_name < b_name else b_name + "|" + a_name


func plan_walkway_span(a_name: String, b_name: String) -> void:
	var a: Dictionary = platforms[a_name]
	var b: Dictionary = platforms[b_name]
	var line := HexGrid.line(rim_toward(a, b.center, true), rim_toward(b, a.center, true))
	var span: Array[Vector2i] = []
	for hex in line:
		if not tiles.has(hex):
			span.append(hex)
			planned_hexes[hex] = true
	planned_spans[_span_key(a_name, b_name)] = span


func _lay_walkway(a_name: String, b_name: String) -> void:
	var a: Dictionary = platforms[a_name]
	var b: Dictionary = platforms[b_name]
	var start := rim_toward(a, b.center, true)
	var end := rim_toward(b, a.center, true)
	for hex in HexGrid.line(start, end):
		if not tiles.has(hex):
			tiles[hex] = {"type": "walkway", "platform": ""}
	walkway_count += 1


## The free rim tile of a platform closest to a target hex. With `allow_used`
## a rim tile that already holds a feature can be returned.
func rim_toward(p: Dictionary, target: Vector2i, allow_used := false) -> Vector2i:
	var target_world := hex_center(target)
	var best := p.center as Vector2i
	var best_d := INF
	for hex in rim_of(p):
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

	for p in layout.platforms:
		_add_underside(p)
		_add_trim(p)
		_add_label(p)


func _make_tile(hex: Vector2i) -> void:
	var t: Dictionary = tiles[hex]
	var kind: String = platforms[t.platform].kind if t.platform != "" else "walkway"
	if t.get("builder", "") == "rival":
		kind = "rival_walkway"
	if kind == "neutral":
		kind = _neutral_kind(t.platform)
	if t.platform != "" and platforms[t.platform].get("corp", "") != "":
		var corp_tile: String = RivalCatalog.get_data(platforms[t.platform].corp).get("tile", "rival")
		if corp_tile != "rival":
			kind = corp_tile
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
			prop.mesh = _hex_mesh(1.2, tile_size * 0.8)
			prop.position.y = top + 0.6
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
	_add_prop_details(prop, type)


## Extra placeholder pieces that make each feature read at a glance.
func _add_prop_details(prop: MeshInstance3D, type: String) -> void:
	var brass := _material(Color(0.75, 0.56, 0.26))
	var iron := _material(Color(0.22, 0.21, 0.2))
	match type:
		"core", "rival_core":
			# A clock-tower headquarters: column, dome and a glowing beacon.
			var player := type == "core"
			var column := _part(_cylinder_mesh(0.9, 1.1, 2.6, 8), Vector3(0, 1.9, 0),
				_material(Color(0.55, 0.4, 0.22) if player else Color(0.35, 0.12, 0.1)))
			prop.add_child(column)
			var dome := SphereMesh.new()
			dome.radius = 1.2
			dome.height = 1.6
			prop.add_child(_part(dome, Vector3(0, 3.3, 0), brass if player else iron))
			prop.add_child(_part(_cylinder_mesh(0.0, 0.25, 1.6, 6), Vector3(0, 4.6, 0), iron))
			var beacon := SphereMesh.new()
			beacon.radius = 0.35
			beacon.height = 0.7
			prop.add_child(_part(beacon, Vector3(0, 5.5, 0),
				_material(Color(1.0, 0.8, 0.4) if player else Color(1.0, 0.3, 0.2), true)))
			for x in [-1.0, 1.0]:
				prop.add_child(_part(_cylinder_mesh(0.25, 0.3, 2.2, 8), Vector3(x * 1.3, 1.7, 0.6), iron))
		"scrap_heap":
			for i in 4:
				var box := BoxMesh.new()
				box.size = Vector3(0.6 + i * 0.1, 0.4, 0.5)
				var junk := _part(box, Vector3(-0.5 + i * 0.35, 0.3 + (i % 2) * 0.25, 0.3 - i * 0.2),
					_material(Color(0.45, 0.3, 0.2) if i % 2 == 0 else Color(0.4, 0.4, 0.42)))
				junk.rotation = Vector3(0.3 * i, 0.7 * i, 0.2)
				prop.add_child(junk)
		"crystal_seam":
			for i in 3:
				var shard := _part(_cylinder_mesh(0.0, 0.35, 1.4, 4), Vector3(0.6 * cos(i * 2.1), -0.4, 0.6 * sin(i * 2.1)), prop.material_override)
				shard.rotation = Vector3(0.4 * sin(i * 2.1), 0, -0.4 * cos(i * 2.1))
				prop.add_child(shard)
		"dock":
			var arm := BoxMesh.new()
			arm.size = Vector3(0.3, 0.3, 1.8)
			prop.add_child(_part(arm, Vector3(0, 1.1, 0.8), iron))
			var lamp := SphereMesh.new()
			lamp.radius = 0.25
			lamp.height = 0.5
			prop.add_child(_part(lamp, Vector3(0, 1.5, 0), _material(Color(0.5, 1.0, 0.9), true)))
		"generator_socket":
			var coil := TorusMesh.new()
			coil.inner_radius = 0.5
			coil.outer_radius = 0.7
			prop.add_child(_part(coil, Vector3(0, 0.25, 0), brass))


func _part(mesh: Mesh, at: Vector3, mat: Material) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = at
	part.material_override = mat
	return part


func _cylinder_mesh(top: float, bottom: float, height: float, sides: int) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = sides
	return mesh


func _add_underside(p: Dictionary) -> void:
	if p.get("style", "city") != "city":
		_add_island_underside(p)
		return
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

	# Lift engines: brass turbines around the cone that keep the platform up.
	var brass := _material(Color(0.7, 0.52, 0.25))
	var dark := _material(Color(0.18, 0.17, 0.17))
	var engines := 3 if p.radius <= 1 else 4
	for i in engines:
		var angle := TAU * i / engines + 0.4
		var out := Vector3(cos(angle), 0, sin(angle))
		var engine := Node3D.new()
		engine.position = hex_center(p.center) + out * radius * 0.55 + Vector3.DOWN * (DECK_HEIGHT + mesh.height * 0.45)
		engine.rotation.y = -angle
		add_child(engine)
		var housing := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.9
		cyl.bottom_radius = 1.1
		cyl.height = 1.6
		cyl.radial_segments = 10
		housing.mesh = cyl
		housing.rotation.z = PI / 2.0
		housing.position = Vector3(0.9, 0, 0)
		housing.material_override = brass
		engine.add_child(housing)
		var blades := MeshInstance3D.new()
		var blade := BoxMesh.new()
		blade.size = Vector3(0.1, 2.6, 0.3)
		blades.mesh = blade
		blades.position = Vector3(1.8, 0, 0)
		blades.rotation.x = angle
		blades.material_override = dark
		engine.add_child(blades)
	# A warm lamp at the tip of the cone.
	var lamp := MeshInstance3D.new()
	var bulb := SphereMesh.new()
	bulb.radius = 0.6
	bulb.height = 1.2
	lamp.mesh = bulb
	lamp.material_override = _material(Color(1.0, 0.75, 0.4), true)
	lamp.position = hex_center(p.center) + Vector3.DOWN * (DECK_HEIGHT + mesh.height + 0.3)
	add_child(lamp)


## A riveted brass band around the deck's edge and lamp posts at its corners.
func _add_trim(p: Dictionary) -> void:
	if p.get("style", "city") != "city":
		_add_island_trim(p)
		return
	var band := MeshInstance3D.new()
	band.name = "Trim_" + p.name.replace(" ", "")
	var ring := CylinderMesh.new()
	var radius: float = tile_size * HexGrid.SQRT3 * (p.radius + 0.42)
	ring.top_radius = radius
	ring.bottom_radius = radius * 0.97
	ring.height = 0.9
	ring.radial_segments = 6
	ring.cap_top = false
	band.mesh = ring
	var mat := _material(Color(0.62, 0.45, 0.22)).duplicate() as StandardMaterial3D
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.metallic = 0.3
	band.material_override = mat
	band.position = hex_center(p.center) + Vector3.DOWN * (DECK_HEIGHT * 0.55)
	band.rotation.y = PI / 6.0
	add_child(band)
	var post_mat := _material(Color(0.2, 0.19, 0.18))
	var glow := _material(Color(1.0, 0.8, 0.45), true)
	for i in 6:
		var corner: Vector2i = p.center + HexGrid.DIRECTIONS[i] * p.radius
		var pos := hex_center(corner)
		var out := pos - hex_center(p.center)
		out = out.normalized() if out.length() > 0.01 else Vector3.ZERO
		var post := MeshInstance3D.new()
		var pole := CylinderMesh.new()
		pole.top_radius = 0.07
		pole.bottom_radius = 0.1
		pole.height = 2.2
		post.mesh = pole
		post.material_override = post_mat
		post.position = pos + out * tile_size * 0.75 + Vector3.UP * 1.1
		add_child(post)
		var light := MeshInstance3D.new()
		var bulb := SphereMesh.new()
		bulb.radius = 0.2
		bulb.height = 0.4
		light.mesh = bulb
		light.material_override = glow
		light.position = post.position + Vector3.UP * 1.2
		add_child(light)


## Island colours under the deck, by style.
const UNDERSIDE_COLORS := {
	"rock": Color(0.34, 0.28, 0.23),
	"turbine": Color(0.27, 0.27, 0.29),
	"crystal": Color(0.2, 0.22, 0.28),
	"grassy": Color(0.38, 0.27, 0.17),
	"overcharged": Color(0.18, 0.17, 0.26),
}


## Under an irregular island: a column of rock or ironwork beneath every
## hex, deepest in the middle, so the outline reads from any angle. Turbine
## islands get lift engines under their blades, crystal islands glowing
## shards hanging below, rocks a few loose boulders.
func _add_island_underside(p: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(p.name)
	var root := Node3D.new()
	root.name = "Underside_" + p.name.replace(" ", "")
	root.position = hex_center(p.center)
	add_child(root)
	var style: String = p.style
	var variant: String = p.get("variant", "")
	var mat := _material(UNDERSIDE_COLORS.get(variant if variant != "" else style, COLORS.underside))
	var root_mat := _material(Color(0.22, 0.16, 0.1))
	var crystal := _material(Color(0.35, 0.95, 1.0), true)
	var brass := _material(Color(0.7, 0.52, 0.25))
	var rim := {}
	for hex in rim_of(p):
		rim[hex] = true
	for hex in shape_of(p):
		var depth: float = 1.2 + (p.radius + 1 - HexGrid.distance(hex, p.center)) * 1.6 + rng.randf_range(0.0, 1.6)
		depth = snappedf(depth, 0.5)
		var col := MeshInstance3D.new()
		col.mesh = _column_mesh(depth)
		col.material_override = mat
		col.position = hex_center(hex) - root.position + Vector3.DOWN * (DECK_HEIGHT + depth / 2.0)
		root.add_child(col)
		var bottom := col.position + Vector3.DOWN * depth / 2.0
		match style:
			"crystal":
				if variant == "grassy" and rng.randf() < 0.5:
					# Roots trailing from earth the crystals tore out of the ground.
					var root_line := MeshInstance3D.new()
					root_line.mesh = _cylinder_mesh(0.08, 0.02, rng.randf_range(1.5, 3.5), 4)
					root_line.material_override = root_mat
					root_line.position = bottom + Vector3(rng.randf_range(-0.5, 0.5), -1.0, rng.randf_range(-0.5, 0.5))
					root_line.rotation = Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4))
					root.add_child(root_line)
				if rng.randf() < (0.2 if variant == "grassy" else 0.7):
					var shard := MeshInstance3D.new()
					shard.mesh = _cylinder_mesh(0.45, 0.0, rng.randf_range(1.5, 3.0), 5)
					shard.material_override = crystal
					shard.position = bottom + Vector3.DOWN * 1.0
					shard.rotation = Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
					root.add_child(shard)
			"rock":
				if rng.randf() < 0.2:
					var boulder := MeshInstance3D.new()
					var sphere := SphereMesh.new()
					sphere.radius = rng.randf_range(0.5, 0.9)
					sphere.height = sphere.radius * 1.6
					boulder.mesh = sphere
					boulder.material_override = mat
					boulder.position = bottom + Vector3(rng.randf_range(-0.6, 0.6), -0.4, rng.randf_range(-0.6, 0.6))
					root.add_child(boulder)
			"turbine":
				if rim.has(hex) and HexGrid.distance(hex, p.center) == p.radius:
					var engine := MeshInstance3D.new()
					engine.mesh = _cylinder_mesh(0.7, 0.9, 1.3, 10)
					engine.material_override = brass
					engine.position = col.position + Vector3.DOWN * 0.3
					engine.rotation.z = PI / 2.0
					root.add_child(engine)


## Deck dressing for irregular islands: lamp posts on turbine blade tips and
## crystal spikes poking up from crystal islands' edges.
func _add_island_trim(p: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(p.name) + 1
	var post_mat := _material(Color(0.2, 0.19, 0.18))
	var glow := _material(Color(1.0, 0.8, 0.45), true)
	var crystal := _material(Color(0.35, 0.95, 1.0), true)
	for hex in rim_of(p):
		if tiles.get(hex, {}).get("type", "deck") != "deck":
			continue
		var pos := hex_center(hex)
		var out := pos - hex_center(p.center)
		out = out.normalized() if out.length() > 0.01 else Vector3.ZERO
		if p.style == "turbine" and HexGrid.distance(hex, p.center) == p.radius:
			var post := MeshInstance3D.new()
			post.mesh = _cylinder_mesh(0.07, 0.1, 2.2, 6)
			post.material_override = post_mat
			post.position = pos + out * tile_size * 0.7 + Vector3.UP * 1.1
			add_child(post)
			var light := MeshInstance3D.new()
			var bulb := SphereMesh.new()
			bulb.radius = 0.2
			bulb.height = 0.4
			light.mesh = bulb
			light.material_override = glow
			light.position = post.position + Vector3.UP * 1.2
			add_child(light)
		elif p.get("variant", "") == "grassy" and rng.randf() < 0.45:
			var bush := MeshInstance3D.new()
			var ball := SphereMesh.new()
			ball.radius = rng.randf_range(0.35, 0.6)
			ball.height = ball.radius * 1.5
			bush.mesh = ball
			bush.material_override = _material(Color(0.25, 0.45, 0.18))
			bush.position = pos + out * tile_size * 0.55 + Vector3.UP * 0.25
			add_child(bush)
		elif p.style == "crystal" and p.get("variant", "") != "grassy" and rng.randf() < 0.7:
			var spike := MeshInstance3D.new()
			spike.mesh = _cylinder_mesh(0.0, 0.3, rng.randf_range(0.8, 1.6), 5)
			spike.material_override = crystal
			spike.position = pos + out * tile_size * 0.75 + Vector3.UP * 0.4
			spike.rotation = Vector3(out.z * 0.4, 0, -out.x * 0.4)
			add_child(spike)


## A hex column that narrows toward the bottom, for island undersides.
func _column_mesh(depth: float) -> CylinderMesh:
	var key := Vector2(depth, -1.0)
	if not _hex_mesh_cache.has(key):
		var mesh := CylinderMesh.new()
		mesh.top_radius = tile_size * TILE_GAP
		mesh.bottom_radius = tile_size * TILE_GAP * 0.55
		mesh.height = depth
		mesh.radial_segments = 6
		mesh.rings = 1
		_hex_mesh_cache[key] = mesh
	return _hex_mesh_cache[key]


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
	var a := find_feature(a_name, "dock")
	var b := find_feature(b_name, "dock")
	_draw_markers("Ferry_%s_%s" % [a_name, b_name], a, b, FERRY_HEIGHT, COLORS.ferry, 0.5)


## Draws the air lane from one platform to another along `route` (from
## AirNav), replacing any earlier drawing of it.
func set_air_route(a_name: String, b_name: String, route: PackedVector3Array, announce := true) -> void:
	var points := PackedVector3Array([Vector3(get_platform_position(a_name).x, 0.0, get_platform_position(a_name).z)])
	points.append_array(route)
	air_routes[a_name + "|" + b_name] = points
	var node_name := ("AirLane_%s_%s" % [a_name, b_name]).replace(" ", "")
	var old := get_node_or_null(node_name)
	if old:
		remove_child(old)
		old.queue_free()
	var root := Node3D.new()
	root.name = node_name
	add_child(root)
	# A marker every tile or so along the flight path, skipping both ends.
	var spacing := tile_size * 1.6
	var carry := spacing
	for i in range(1, points.size()):
		var a := points[i - 1]
		var b := points[i]
		var length := a.distance_to(b)
		var t := carry
		while t < length:
			var at := a.lerp(b, t / length)
			if at.distance_to(points[points.size() - 1]) > tile_size * 2.0 and at.distance_to(points[0]) > tile_size * 2.0:
				var marker := MeshInstance3D.new()
				marker.mesh = _hex_mesh(0.15, tile_size * 0.6)
				marker.material_override = _material(COLORS.air_lane, true)
				marker.position = at + Vector3.UP * AIR_LANE_HEIGHT
				root.add_child(marker)
			t += spacing
		carry = t - length
	if announce:
		air_routes_changed.emit()


## The drawn air lanes as [from, to, waypoints] (waypoints include the start).
func air_lane_routes() -> Array:
	var out := []
	for key in air_routes:
		var names: PackedStringArray = key.split("|")
		out.append([names[0], names[1], air_routes[key]])
	return out


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


func find_feature(platform_name: String, type: String) -> Vector2i:
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


# --- Moving platforms -------------------------------------------------------
# Used by DriftSystem: balloon platforms hop one hex at a time, so their tiles
# (and the walkways that moor them) come and go at runtime.

## Registers a platform that isn't in the generated layout (a balloon
## platform). Its tiles are added separately with add_tiles.
## Open-sky hexes a balloon platform flies through. Walkways can't be built
## across them.
var reserved_hexes := {}
## Sky hexes where a walkway is being built right now.
var pending_hexes := {}
## Builds walkways tile by tile.
var crew: WalkwayCrew
## Sky hexes that planned walkways (built or not) run over, so balloon tracks
## keep clear of them.
var planned_hexes := {}
## "A|B" platform pair -> the hexes of the walkway planned between them.
var planned_spans := {}


func add_platform(p: Dictionary) -> void:
	platforms[p.name] = p
	owners[p.name] = ""
	_add_label(p)


## The floating name label of a platform, or null.
func platform_label(platform_name: String) -> Label3D:
	return _labels.get(platform_name)


## The placeholder mesh of a tile, or null.
func tile_node(hex: Vector2i) -> MeshInstance3D:
	return _tile_nodes.get(hex)


## The colour key for an unowned platform: crystal islands are either grassy
## (lifted from the ground by their crystals) or overcharged.
func _neutral_kind(platform_name: String) -> String:
	var p: Dictionary = platforms.get(platform_name, {})
	return p.get("variant", "neutral") if p.get("style", "") == "crystal" else "neutral"


## Adds tiles ({hex: {"type", "platform"}}) with their meshes, and links the
## walkable ones into the walking graph.
func add_tiles(new_tiles: Dictionary) -> void:
	tiles_version += 1
	for hex in new_tiles:
		tiles[hex] = new_tiles[hex]
		_make_tile(hex)
		var owner_name := platform_owner(tiles[hex].platform) if tiles[hex].platform != "" else ""
		if owner_name != "":
			_tile_nodes[hex].material_override = _material(COLORS[{"player": "hub", "rival": "rival"}[owner_name]])
		if WALKABLE.has(tiles[hex].type):
			_add_walk_point(hex)
			if buildings.has(hex):
				_astar.set_point_disabled(_astar_ids[hex], true)
	for hex in new_tiles:
		if _astar_ids.has(hex):
			_connect_walk_point(hex)


## Removes tiles, their meshes and their walking-graph points.
func remove_tiles(hexes: Array) -> void:
	tiles_version += 1
	for hex in hexes:
		tiles.erase(hex)
		var node: Node = _tile_nodes.get(hex)
		if node:
			node.get_parent().remove_child(node)
			node.queue_free()
		_tile_nodes.erase(hex)
		if _astar_ids.has(hex):
			_astar.remove_point(_astar_ids[hex])
			_astar_ids.erase(hex)


## Moves a building's bookkeeping from one hex to another (the caller moves
## the tiles under it).
func move_building(from_hex: Vector2i, to_hex: Vector2i) -> void:
	var building: Building = buildings.get(from_hex)
	if building == null:
		return
	buildings.erase(from_hex)
	buildings[to_hex] = building
	building.hex = to_hex
	building.position = hex_center(to_hex)
