## Flight planning for airships. Airships cruise in open sky and steer around
## islands instead of flying over them in a straight line. Only the island
## they take off from and the one they are attacking are open to them.
##
## The sky is a hex grid around the map. Every hex holding a platform tile
## (read live from SkyRegion.tiles, so any platform shape and moving balloon
## islands work) is closed. Wind makes flying downwind cheap and upwind dear,
## so routes bend with it, and `plan_attack` sends a flight round to the
## upwind side of its target so it makes its bombing run with the wind.
class_name AirNav
extends RefCounted

## Open sky kept around the edge of the map, in tiles.
const PAD := 7
## How much wind changes the cost of a step: 0.45 makes a downwind step cost
## 0.55 and an upwind step 1.45.
const WIND_PULL := 0.45
## Tiles between the target island's edge and the upwind staging point.
const STAGE_GAP := 3

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
