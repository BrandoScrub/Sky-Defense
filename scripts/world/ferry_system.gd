## Airship ferries between docks (region.layout.ferry_routes). Each ferry
## shuttles back and forth on a timer: it waits at a dock, then flies to the
## other one. Units sent somewhere they can't walk to are routed to the nearer
## dock, board when the ferry is in, ride across, and walk on to their goal.
class_name FerrySystem
extends Node

signal departed(from_platform: String, to_platform: String, passengers: int)

@export var region: SkyRegion
## Seconds in the air for one crossing.
@export var trip_seconds := 8.0
## Seconds spent at each dock before leaving.
@export var dock_seconds := 5.0
@export var capacity := 6
## How close a unit must be to the dock tile to board.
@export var boarding_range := 2.6

const SHIP_HEIGHT := 2.6

## One entry per route: {a, b, docks: [hex_a, hex_b], at: 0/1, flying, timer,
## ship: Node3D, passengers: Array[Unit]}
var ferries: Array[Dictionary] = []
## Unit -> {ferry: index, side: 0/1, goal: Vector3, attack_move: bool}
var _trips := {}


func _ready() -> void:
	for f in region.layout.ferry_routes:
		var docks := [region._find_feature(f[0], "dock"), region._find_feature(f[1], "dock")]
		var ferry := {
			"names": [f[0], f[1]], "docks": docks, "at": 0, "flying": false,
			"timer": dock_seconds, "passengers": [], "ship": _build_ship(),
		}
		ferry.ship.name = "Ferry_%s_%s" % [f[0].replace(" ", ""), f[1].replace(" ", "")]
		region.add_child(ferry.ship)
		ferry.ship.position = berth(ferry, 0)
		ferries.append(ferry)


func _process(delta: float) -> void:
	step(delta)


## Advances every ferry by `delta` seconds. Public so tests can drive it.
func step(delta: float) -> void:
	_prune()
	for i in ferries.size():
		var f: Dictionary = ferries[i]
		f.timer -= delta
		if f.flying:
			var t := clampf(1.0 - f.timer / trip_seconds, 0.0, 1.0)
			var from := berth(f, f.at)
			var to := berth(f, 1 - f.at)
			f.ship.position = from.lerp(to, t) + Vector3.UP * sin(t * PI) * 1.5
			f.ship.rotation.y = atan2(to.x - from.x, to.z - from.z)
			_carry(f)
			if f.timer <= 0.0:
				f.flying = false
				f.at = 1 - f.at
				f.timer = dock_seconds
				f.ship.position = berth(f, f.at)
				_unload(f)
		else:
			_board(i)
			if f.timer <= 0.0:
				f.flying = true
				f.timer = trip_seconds
				departed.emit(f.names[f.at], f.names[1 - f.at], f.passengers.size())


## Sends a unit to `goal` by ferry. Returns false if no ferry route helps.
func send(unit: Unit, goal: Vector3, attack_move := false) -> bool:
	if is_riding(unit):
		_trips[unit].goal = goal
		_trips[unit].attack_move = attack_move
		return true
	for i in ferries.size():
		var f: Dictionary = ferries[i]
		for side in [0, 1]:
			var walk := region.find_route(unit.position, dock_point(f, side))
			if walk.is_empty() and not _near_dock(unit, f, side):
				continue
			if region.find_route(dock_point(f, 1 - side), goal).is_empty():
				continue
			_trips[unit] = {"ferry": i, "side": side, "goal": goal, "attack_move": attack_move}
			unit.set_route(walk)
			return true
	return false


## Forgets a unit's planned trip (when it's given a walking order instead).
## Riding units stay aboard.
func cancel(unit: Unit) -> void:
	if not is_riding(unit):
		_trips.erase(unit)


func is_riding(unit: Unit) -> bool:
	return unit.riding


func is_waiting(unit: Unit) -> bool:
	return _trips.has(unit) and not unit.riding


## Centre of a dock tile at deck level.
func dock_point(f: Dictionary, side: int) -> Vector3:
	return region.hex_center(f.docks[side])


## Where the ship hovers at a dock: just off the platform's edge.
func berth(f: Dictionary, side: int) -> Vector3:
	var dock := dock_point(f, side)
	var platform: String = f.names[side]
	var out := dock - region.get_platform_position(platform)
	out.y = 0.0
	out = out.normalized() if out.length() > 0.01 else Vector3.FORWARD
	return dock + out * region.tile_size * 1.6 + Vector3.UP * SHIP_HEIGHT


func _board(index: int) -> void:
	var f: Dictionary = ferries[index]
	for unit in _trips.keys():
		var trip: Dictionary = _trips[unit]
		if trip.ferry != index or trip.side != f.at or unit.riding:
			continue
		if f.passengers.size() >= capacity or not _near_dock(unit, f, f.at):
			continue
		unit.stop()
		unit.riding = true
		f.passengers.append(unit)
	_carry(f)


func _unload(f: Dictionary) -> void:
	var dock := dock_point(f, f.at)
	var offsets := SelectionController.formation_offsets_for(f.passengers.size(), 1.4)
	for i in f.passengers.size():
		var unit: Unit = f.passengers[i]
		unit.riding = false
		unit.position = region.snap_to_walkable(dock + offsets[i])
		var trip: Dictionary = _trips.get(unit, {})
		_trips.erase(unit)
		if trip.is_empty():
			continue
		var route := region.find_route(unit.position, trip.goal)
		if not route.is_empty():
			unit.set_route(route, trip.attack_move)
	f.passengers.clear()


## Keeps passengers standing on the deck of the gondola.
func _carry(f: Dictionary) -> void:
	for i in f.passengers.size():
		var unit: Unit = f.passengers[i]
		var slot := Vector3((i % 3) * 0.7 - 0.7, -1.4, (i / 3) * 0.8 - 0.4)
		unit.position = f.ship.position + slot.rotated(Vector3.UP, f.ship.rotation.y)


func _near_dock(unit: Unit, f: Dictionary, side: int) -> bool:
	var d := unit.position - dock_point(f, side)
	return Vector2(d.x, d.z).length() <= boarding_range


func _prune() -> void:
	for unit in _trips.keys():
		if not is_instance_valid(unit) or not unit.is_alive():
			_trips.erase(unit)
	for f in ferries:
		f.passengers = f.passengers.filter(func(u): return is_instance_valid(u) and u.is_alive())


## Placeholder airship: a gas envelope over an open gondola with a propeller.
func _build_ship() -> Node3D:
	var ship := Node3D.new()
	var envelope := MeshInstance3D.new()
	var balloon := CapsuleMesh.new()
	balloon.radius = 1.1
	balloon.height = 4.6
	envelope.mesh = balloon
	envelope.rotation.x = PI / 2.0
	envelope.position.y = 1.3
	envelope.material_override = _mat(Color(0.62, 0.5, 0.36))
	ship.add_child(envelope)
	var gondola := MeshInstance3D.new()
	var hull := BoxMesh.new()
	hull.size = Vector3(2.0, 0.5, 2.8)
	gondola.mesh = hull
	gondola.position.y = -1.6
	gondola.material_override = _mat(Color(0.35, 0.25, 0.18))
	ship.add_child(gondola)
	for x in [-0.8, 0.8]:
		var rope := MeshInstance3D.new()
		var line := CylinderMesh.new()
		line.top_radius = 0.04
		line.bottom_radius = 0.04
		line.height = 2.4
		rope.mesh = line
		rope.position = Vector3(x, -0.3, 0)
		rope.material_override = _mat(Color(0.2, 0.2, 0.2))
		ship.add_child(rope)
	var prop := MeshInstance3D.new()
	var blade := BoxMesh.new()
	blade.size = Vector3(1.6, 0.15, 0.1)
	prop.mesh = blade
	prop.position = Vector3(0, 1.3, -2.5)
	prop.material_override = _mat(Color(0.8, 0.65, 0.3))
	ship.add_child(prop)
	return ship


func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.7
	return m
