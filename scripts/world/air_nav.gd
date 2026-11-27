## Flight planning for airships. Airships cruise in open sky and steer around
## islands instead of flying over them in a straight line. Only the island
## they take off from and the one they are attacking are open to them.
##
## The sky is a hex grid around the map. Every hex holding a platform tile
## (read live from SkyRegion.tiles, so any platform shape and moving balloon
## islands work) is closed. Wind makes flying downwind cheap and upwind dear,
## so routes bend with it, and `plan_attack` sends a flight round to the
## upwind side of its target so it makes its bombing run with the wind.
##
## Wind lanes: the route plan_attack finds is the middle of a broad lane
## (LANE_HALF_WIDTH either side). `plan_weave` gives each airship its own
## way down that lane, swinging from side to side and threading whichever
## gaps between islands it meets, so a wave spreads out instead of flying
## single file. Every lane moves when the wind turns.
class_name AirNav
extends RefCounted

## Open sky kept around the edge of the map, in tiles.
const PAD := 7
## How much wind changes the cost of a step: 0.45 makes a downwind step cost
## 0.55 and an upwind step 1.45.
const WIND_PULL := 0.45
## Tiles between the target island's edge and the upwind staging point.
const STAGE_GAP := 3
## Half the width of a wind lane, in tiles.
const LANE_HALF_WIDTH := 1.75
## Tiles between the points an airship weaves through along its lane.
const WEAVE_SPACING := 3.0
## A weave point is skipped when getting to it takes more than this many
## times the straight distance (it sits behind an island).
const WEAVE_DETOUR := 2.2

var region: SkyRegion
## Direction the wind blows toward, on the XZ plane as (x, z); length 0..1.
var wind := Vector2.ZERO:
	set(value):
		wind = value
		if _graph:
			_graph.wind = value

var _graph: _WindAStar
## hex -> point id
var _ids := {}
## platform name -> hexes it closes
var _closed_by := {}
var _signature := -1


func _init(sky: SkyRegion) -> void:
	region = sky


## Waypoints (y = 0) from `from` to `to` through open sky. The islands under
## `from` and `to` are open, plus any named in `open`.
func plan(from: Vector3, to: Vector3, open: Array = []) -> PackedVector3Array:
	_ensure_graph()
	var names := open.duplicate()
	for p in [region.platform_at(from), region.platform_at(to)]:
		if p != "" and not names.has(p):
			names.append(p)
	var opened: Array[int] = []
	for p in names:
		for hex in _closed_by.get(p, []):
			var id: int = _ids.get(hex, -1)
			if id >= 0 and _graph.is_point_disabled(id) and _only_closed_by(hex, names):
				_graph.set_point_disabled(id, false)
				opened.append(id)
	var route := PackedVector3Array()
	var a := _graph.get_closest_point(Vector2(from.x, from.z))
	var b := _graph.get_closest_point(Vector2(to.x, to.z))
	if a >= 0 and b >= 0:
		var path := _graph.get_point_path(a, b)
		var points := PackedVector3Array()
		for p in path:
			points.append(Vector3(p.x, 0.0, p.y))
		if not points.is_empty():
			points[points.size() - 1] = Vector3(to.x, 0.0, to.z)
			route = _smooth(Vector3(from.x, 0.0, from.z), points)
	for id in opened:
		_graph.set_point_disabled(id, true)
	return route


## Like plan, but when the target is on another island and there is wind,
## the flight first circles to the upwind side of that island and makes its
## run downwind. When the wind turns, the attack comes from a new side.
func plan_attack(from: Vector3, to: Vector3) -> PackedVector3Array:
	var stage = staging_point(from, to)
	if stage == null:
		return plan(from, to)
	var first := plan(from, stage)
	var second := plan(stage, to)
	if first.is_empty():
		return second
	first.append_array(second)
	return first


## The upwind point a flight gathers at before attacking `to`, or null when
## there's no wind or the target is on the island the flight is already over.
func staging_point(from: Vector3, to: Vector3):
	var target := region.platform_at(to)
	if wind.length() < 0.05 or target == "" or target == region.platform_at(from):
		return null
	var upwind := -Vector3(wind.x, 0.0, wind.y).normalized()
	var to_hex := region.hex_at(to)
	var extent := 0
	for hex in region.tiles_of_platform(target):
		extent = maxi(extent, HexGrid.distance(hex, to_hex))
	var reach := (extent + STAGE_GAP) * region.tile_size * HexGrid.SQRT3
	var stage := Vector3(to.x, 0.0, to.z) + upwind * reach
	_ensure_graph()
	var id := _graph.get_closest_point(Vector2(stage.x, stage.z))
	if id < 0:
		return null
	var p := _graph.get_point_position(id)
	return Vector3(p.x, 0.0, p.y)


## Distance between neighbouring hex centres.
func step_length() -> float:
	return region.tile_size * HexGrid.SQRT3


## One airship's own way down the wind lane from `from` to `to`: through
## open sky, weaving from side to side of the lane's middle (plan_attack)
## by a random amount, then gathering upwind of the target near (not
## exactly at) the staging point and making its run downwind. `rng` picks
## the weave, so each airship flies a different line. Airships launched
## together can share `lane` (from weave_lane) to plan it only once.
func plan_weave(from: Vector3, to: Vector3, rng: RandomNumberGenerator, lane := PackedVector3Array()) -> PackedVector3Array:
	var start := Vector3(from.x, 0.0, from.z)
	var stage = staging_point(from, to)
	var line := lane if not lane.is_empty() else weave_lane(from, to)
	if line.size() < 2:
		return plan_attack(from, to)
	var total := _length(line)
	var step := step_length()
	var count := int(total / (step * WEAVE_SPACING))
	var route := PackedVector3Array()
	var here := start
	if count >= 2:
		var amp := rng.randf_range(0.6, 1.0) * LANE_HALF_WIDTH * step
		var turns := rng.randf_range(0.6, 1.6)
		var phase := rng.randf() * TAU
		for k in range(1, count):
			var t := float(k) / count
			var at := _sample(line, t * total)
			var side := Vector3(-at[1].z, 0.0, at[1].x)
			# Widest mid-lane, closing in at both ends.
			var want: Vector3 = at[0] + side * amp * sin(PI * t) * sin(TAU * turns * t + phase)
			var got = _open_near(want, step * 1.2)
			if got == null:
				continue
			# Most hops are clear sky; only plan round an island in the way.
			var leg := PackedVector3Array([got]) if k > 1 and _clear(here, got) else plan(here, got)
			if leg.is_empty() or _length(_with_start(here, leg)) > here.distance_to(got) * WEAVE_DETOUR + step:
				continue
			route.append_array(leg)
			here = got
	if stage != null:
		# Spread out a little across the wind before the run.
		var across := Vector3(-wind.y, 0.0, wind.x).normalized()
		var gather = _open_near(stage + across * rng.randf_range(-1.0, 1.0) * step, step * 1.2)
		if gather == null:
			gather = stage
		route.append_array(plan(here, gather))
		here = gather
	route.append_array(plan(here, to))
	return route


## The middle of the lane plan_weave weaves along: from `from` to the
## staging point upwind of `to` (or to `to` when there is none), starting
## at `from`.
func weave_lane(from: Vector3, to: Vector3) -> PackedVector3Array:
	var stage = staging_point(from, to)
	var line := PackedVector3Array([Vector3(from.x, 0.0, from.z)])
	line.append_array(plan(from, stage if stage != null else to))
	return line


## Nearest open-sky point to `want`, or null if none within `within`.
func _open_near(want: Vector3, within: float):
	_ensure_graph()
	var id := _graph.get_closest_point(Vector2(want.x, want.z))
	if id < 0:
		return null
	var p := _graph.get_point_position(id)
	var got := Vector3(p.x, 0.0, p.y)
	return got if got.distance_to(want) <= within else null


## [point, unit direction] at `distance` along a polyline.
static func _sample(line: PackedVector3Array, distance: float) -> Array:
	for i in range(1, line.size()):
		var seg := line[i].distance_to(line[i - 1])
		if distance <= seg or i == line.size() - 1:
			var dir := (line[i] - line[i - 1]).normalized() if seg > 0.0 else Vector3.FORWARD
			return [line[i - 1].lerp(line[i], clampf(distance / seg, 0.0, 1.0) if seg > 0.0 else 0.0), dir]
		distance -= seg
	return [line[line.size() - 1], Vector3.FORWARD]


static func _length(line: PackedVector3Array) -> float:
	var out := 0.0
	for i in range(1, line.size()):
		out += line[i].distance_to(line[i - 1])
	return out


static func _with_start(start: Vector3, route: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array([start])
	out.append_array(route)
	return out


## True if an airship may fly through this hex (ignoring which islands a
## particular flight has opened).
func is_open_sky(hex: Vector2i) -> bool:
	_ensure_graph()
	return _ids.has(hex) and not _graph.is_point_disabled(_ids[hex])


## Rebuilds the sky grid whenever tiles have been added, removed or moved.
func _ensure_graph() -> void:
	if _graph != null and _signature == region.tiles_version:
		return
	_signature = region.tiles_version
	_graph = _WindAStar.new()
	_graph.wind = wind
	_ids.clear()
	_closed_by.clear()
	if region.tiles.is_empty():
		return
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := -lo
	for hex in region.tiles:
		lo = Vector2i(mini(lo.x, hex.x), mini(lo.y, hex.y))
		hi = Vector2i(maxi(hi.x, hex.x), maxi(hi.y, hex.y))
	# The map's world rectangle, padded, so the sheared axial box doesn't
	# add far-off sky nobody flies through.
	var bounds := region.get_bounds().grow(PAD * region.tile_size * HexGrid.SQRT3)
	var reach := PAD * 2 + (hi.y - lo.y)
	for r in range(lo.y - PAD, hi.y + PAD + 1):
		for q in range(lo.x - reach, hi.x + reach + 1):
			var hex := Vector2i(q, r)
			var w := region.hex_center(hex)
			if not bounds.has_point(Vector2(w.x, w.z)):
				continue
			var id := _ids.size()
			_ids[hex] = id
			_graph.add_point(id, Vector2(w.x, w.z))
	for hex in _ids:
		for n in HexGrid.neighbors(hex):
			if _ids.has(n) and _ids[n] > _ids[hex]:
				_graph.connect_points(_ids[hex], _ids[n])
	for hex in region.tiles:
		var p: String = region.tiles[hex].platform
		if p == "":
			continue  # walkways hang low; airships pass over them
		if not _closed_by.has(p):
			_closed_by[p] = []
		_closed_by[p].append(hex)
		if _ids.has(hex):
			_graph.set_point_disabled(_ids[hex], true)


func _only_closed_by(hex: Vector2i, names: Array) -> bool:
	var tile: Dictionary = region.tiles.get(hex, {})
	return names.has(tile.get("platform", ""))


## Drops waypoints the airship can skip with a clear straight flight.
func _smooth(from: Vector3, path: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	var here := from
	var i := 0
	while i < path.size():
		var j := path.size() - 1
		while j > i and not _clear(here, path[j]):
			j -= 1
		out.append(path[j])
		here = path[j]
		i = j + 1
	return out


func _clear(a: Vector3, b: Vector3) -> bool:
	var steps := int(ceil(a.distance_to(b) / (region.tile_size * 0.35)))
	for s in range(1, steps):
		var hex := region.hex_at(a.lerp(b, float(s) / steps))
		if not _ids.has(hex) or _graph.is_point_disabled(_ids[hex]):
			return false
	return true


## A* whose step cost depends on the wind.
class _WindAStar:
	extends AStar2D
	var wind := Vector2.ZERO

	func _compute_cost(from_id: int, to_id: int) -> float:
		var d := get_point_position(to_id) - get_point_position(from_id)
		var length := d.length()
		if length == 0.0:
			return 0.0
		return length * (1.0 - AirNav.WIND_PULL * d.dot(wind) / length)

	func _estimate_cost(from_id: int, to_id: int) -> float:
		return get_point_position(from_id).distance_to(get_point_position(to_id)) * (1.0 - AirNav.WIND_PULL)
