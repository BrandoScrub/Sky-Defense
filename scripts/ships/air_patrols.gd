## Player airship patrols. Build an Airship Hangar, then Mooring Masts on
## your platforms (Defense tab), and order ships from the Army tab. Each ship
## launches from a hangar and flies a loop: hangar, then every mast on that
## hangar's patrol route in order, then home again, fighting whatever its
## role lets it hit on the way.
##
## Ship roles (SHIPS):
##   interceptor - air-to-air. Only shoots aircraft and airships.
##   gunboat     - air-to-ground. Shoots ground units and buildings, not aircraft.
##   utility     - a tender with a job you pick before building it (UTILITY_JOBS):
##                 repair (mends your buildings it flies over), scout (sees far
##                 through the fog) or troops (drops 3 Riveteers onto one of
##                 your platforms on its route that enemies are on, then
##                 flies home to pick up more for 45 scrap).
##
## Range: ships only chase enemies within PATROL_RANGE of one of your
## hangars or Mooring Masts, so masts decide which part of the sky is
## covered. There is no fuel to manage. Near a mast, ships spot enemies
## twice as far away, and a mast sees far through the fog.
##
## The route: Patrol Route (Defense tab), click a hangar, then click Mooring
## Masts in order; right click to finish. A hangar with no route set patrols
## all your masts, nearest first.
class_name AirPatrols
extends Node

signal notice(text: String)
signal mode_changed(active: bool)
signal ship_launched(ship: Unit)
signal routes_changed

const HANGAR := "airship_hangar"
const MAST := "mooring_mast"
const ALTITUDE := 6.0
const MAX_SHIPS_PER_HANGAR := 4
const HUNT_RADIUS := 12.0
## Within this of a Mooring Mast, ships hunt twice as far.
const MAST_RADIUS := 14.0
## Ships only chase enemies this close to one of your hangars or masts.
const PATROL_RANGE := 18.0
## How close a ship must be to its hangar to count as home (troop reload).
const DOCK_RADIUS := 2.5
const TROOP_RELOAD_COST := 45
const TROOPS := ["riveteer", "riveteer", "riveteer"]
const REPAIR_RADIUS := 7.0
const REPAIR_PER_SECOND := 10.0
const SCOUT_SIGHT := 34.0

const SHIPS := {
	"interceptor": {
		"name": "Skyhawk Interceptor", "role": "Air-to-air", "cost": 70, "build_seconds": 8.0,
		"hp": 90.0, "damage": 12.0, "range": 6.0, "cooldown": 0.6, "speed": 9.0,
		"hits_air": true, "air_only": true, "targets_units": true, "footprint": 0.55,
		"color": Color(0.85, 0.7, 0.35),
	},
	"gunboat": {
		"name": "Thunder Gunboat", "role": "Air-to-ground", "cost": 80, "build_seconds": 10.0,
		"hp": 150.0, "damage": 16.0, "range": 5.0, "cooldown": 1.2, "speed": 6.0,
		"hits_air": false, "air_only": false, "targets_units": true, "footprint": 0.8,
		"vs_buildings": 1.5, "color": Color(0.6, 0.45, 0.25),
	},
	"utility": {
		"name": "Tender", "role": "Utility", "cost": 60, "build_seconds": 8.0,
		"hp": 100.0, "damage": 0.0, "range": 0.0, "cooldown": 99.0, "speed": 7.0,
		"hits_air": false, "air_only": false, "targets_units": false, "footprint": 0.7,
		"color": Color(0.55, 0.7, 0.6),
	},
}
const UTILITY_JOBS := ["repair", "scout", "troops"]
const JOB_NAMES := {"repair": "Repair Tender", "scout": "Scout Tender", "troops": "Troop Tender"}

@export var region: SkyRegion
@export var combat: CombatSystem
@export var resources: PlayerResources
@export var camera: RtsCamera

## The job the next utility ship is built for.
var utility_job := "repair"
## Hangar Building -> {ships: Array[Unit], queue: Array[String], timer, route: Array[Building]}
var hangars := {}
## True while the player is setting a patrol route.
var editing := false
var _edit_hangar: Building
var _edit_points: Array = []
var _count := 0
var _routes_root: Node3D
var _routes_dirty := true


func _process(delta: float) -> void:
	step(delta)


# --- Orders -----------------------------------------------------------------

## Display name of a ship kind (utility ships by the current job).
func ship_name(kind: String, job := "") -> String:
	if kind == "utility":
		return JOB_NAMES[job if job != "" else utility_job]
	return SHIPS[kind].name


## Cycles the utility job for the next utility ship. Returns the new job.
func next_utility_job() -> String:
	utility_job = UTILITY_JOBS[(UTILITY_JOBS.find(utility_job) + 1) % UTILITY_JOBS.size()]
	notice.emit("Next utility ship: %s" % JOB_NAMES[utility_job])
	return utility_job


## Orders a ship from the hangar with the most room. Returns "" or why not.
func queue_ship(kind: String) -> String:
	_sync_hangars()
	var best: Building = null
	var best_n := MAX_SHIPS_PER_HANGAR
	for h in hangars:
		var n: int = hangars[h].ships.size() + hangars[h].queue.size()
		if n < best_n:
			best_n = n
			best = h
	if hangars.is_empty():
		return "Build an Airship Hangar first (Defense tab)"
	if best == null:
		return "Every hangar is full (%d ships each)" % MAX_SHIPS_PER_HANGAR
	var cost: int = SHIPS[kind].cost
	if resources and not resources.spend_scrap(cost):
		return "Not enough scrap (%d needed)" % cost
	hangars[best].queue.append(kind if kind != "utility" else "utility:" + utility_job)
	if hangars[best].queue.size() == 1:
		hangars[best].timer = SHIPS[kind].build_seconds
	return ""


## Ships in the air or being built, of a kind ("" for all).
func ship_count(kind := "") -> int:
	var n := 0
	for h in hangars:
		for s in hangars[h].ships:
			if is_instance_valid(s) and (kind == "" or s.get_meta("ship") == kind):
				n += 1
		for q in hangars[h].queue:
			if kind == "" or String(q).begins_with(kind):
				n += 1
	return n


## A hangar's patrol: its set route, or every Mooring Mast you own, nearest
## first.
func route_of(hangar: Building) -> Array:
	var state: Dictionary = hangars.get(hangar, {})
	var set_route: Array = state.get("route", []).filter(func(b): return is_instance_valid(b) and b.is_alive())
	if not set_route.is_empty():
		return set_route
	var points := waypoints()
	points.sort_custom(func(a, b): return _flat(a.global_position, hangar.global_position) < _flat(b.global_position, hangar.global_position))
	return points


## Every Mooring Mast you own.
func waypoints() -> Array:
	var out := []
	for b in region.buildings.values():
		if b.faction == "player" and b.is_alive() and b.type_id == MAST:
			out.append(b)
	return out


## Sets a hangar's route. Every point must be a Mooring Mast.
func set_route(hangar: Building, points: Array) -> void:
	_sync_hangars()
	if hangars.has(hangar):
		hangars[hangar].route = points.duplicate()
		for s in hangars[hangar].ships:
			if is_instance_valid(s):
				s.set_meta("leg", 0)
	_routes_dirty = true
	routes_changed.emit()


# --- Route editing ----------------------------------------------------------

func begin_route() -> void:
	editing = true
	_edit_hangar = null
	_edit_points = []
	mode_changed.emit(true)
	notice.emit("Click an Airship Hangar, then its Mooring Masts in order. Right click to finish")


func cancel_route() -> void:
	editing = false
	_edit_hangar = null
	_edit_points = []
	mode_changed.emit(false)


func _unhandled_input(event: InputEvent) -> void:
	if not editing:
		return
	if event.is_action_pressed("select"):
		var b := _building_under_mouse()
		if _edit_hangar == null:
			if b and b.type_id == HANGAR and b.faction == "player":
				_edit_hangar = b
				notice.emit("Now click Mooring Masts in patrol order. Right click to finish")
			else:
				notice.emit("Click one of your Airship Hangars first")
		elif b and b.type_id == MAST and b.faction == "player":
			_edit_points.append(b)
			notice.emit("Patrol point %d: %s on %s" % [_edit_points.size(), b.get_data().name, b.platform])
		else:
			notice.emit("Click a Mooring Mast")
		get_viewport().set_input_as_handled()
	elif event.is_action_released("select"):
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("command"):
		if _edit_hangar and not _edit_points.is_empty():
			set_route(_edit_hangar, _edit_points)
			notice.emit("Patrol route set: %d point%s" % [_edit_points.size(), "" if _edit_points.size() == 1 else "s"])
		cancel_route()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("building_cancel"):
		cancel_route()
		get_viewport().set_input_as_handled()


# --- Simulation -------------------------------------------------------------

## Advances building and patrols. Public so tests can drive it.
func step(delta: float) -> void:
	_sync_hangars()
	for h in hangars.keys():
		var state: Dictionary = hangars[h]
		state.ships = state.ships.filter(func(s): return is_instance_valid(s) and s.is_alive())
		if not state.queue.is_empty():
			state.timer -= delta * maxf(h.efficiency, 0.25)
			if state.timer <= 0.0:
				var entry: String = state.queue.pop_front()
				_launch(h, entry)
				if not state.queue.is_empty():
					state.timer = SHIPS[String(state.queue[0]).get_slice(":", 0)].build_seconds
		for ship in state.ships:
			_fly(ship, h, delta)
	if _routes_dirty:
		_draw_routes()


func _launch(hangar: Building, entry: String) -> Unit:
	var kind := entry.get_slice(":", 0)
	var job := entry.get_slice(":", 1) if entry.contains(":") else ""
	var spec: Dictionary = SHIPS[kind]
	_count += 1
	var u := Unit.new()
	u.name = "PlayerShip%d" % _count
	u.display_name = ship_name(kind, job)
	u.faction = "player"
	u.is_drone = true
	u.flying = true
	u.hits_air = spec.hits_air
	u.air_only = spec.air_only
	u.targets_units = spec.targets_units
	u.weight = 0
	u.move_speed = spec.speed * (1.25 if job == "scout" else 1.0)
	u.max_hp = spec.hp
	u.damage = spec.damage
	u.attack_range = spec.range
	u.attack_cooldown = spec.cooldown
	u.vs_buildings = spec.get("vs_buildings", 1.0)
	u.footprint = spec.footprint
	u.body_color = spec.color
	u.set_meta("ship", kind)
	u.set_meta("job", job)
	u.set_meta("leg", 0)
	u.set_meta("state", "patrol")
	if job == "scout":
		u.set_meta("sight", SCOUT_SIGHT)
	if job == "troops":
		u.set_meta("troops", TROOPS.size())
	u.position = hangar.global_position + Vector3.UP * ALTITUDE
	_units_root().add_child(u)
	hangars[hangar].ships.append(u)
	ship_launched.emit(u)
	return u


func _fly(ship: Unit, hangar: Building, delta: float) -> void:
	var job: String = ship.get_meta("job")
	if job == "repair":
		_repair_near(ship, delta)
	elif job == "troops":
		_maybe_drop(ship, hangar)
	if ship.get_meta("state") == "reload":
		if _flat(ship.global_position, hangar.global_position) <= DOCK_RADIUS:
			_reload(ship)
		elif not ship.is_moving():
			_go(ship, hangar.global_position, false)
		return
	if ship.is_moving():
		return
	# Something in reach: CombatSystem is shooting it.
	if combat and ship.attack_range > 0.0 and combat.nearest_enemy(ship.global_position, "player", ship.attack_range, ship.hits_air, ship.targets_units, ship.air_only) != null:
		return
	# Hunt nearby enemies the ship can hit, further near a mast, but only
	# inside the sky your hangars and masts cover.
	if combat and ship.attack_range > 0.0:
		var radius := hunt_radius(ship)
		var prey = combat.nearest_enemy(ship.global_position, "player", radius, ship.hits_air, ship.targets_units, ship.air_only)
		if prey != null and in_range(prey.global_position):
			_go(ship, prey.global_position, true)
			return
	_next_leg(ship, hangar)


## How far a ship looks for enemies.
func hunt_radius(ship: Unit) -> float:
	for b in waypoints():
		if _flat(ship.global_position, b.global_position) <= MAST_RADIUS:
			return HUNT_RADIUS * 2.0
	return HUNT_RADIUS


## True if a point is inside the sky your patrols cover: within
## PATROL_RANGE of one of your Airship Hangars or Mooring Masts.
func in_range(point: Vector3) -> bool:
	for b in region.buildings.values():
		if b.faction == "player" and b.is_alive() and (b.type_id == HANGAR or b.type_id == MAST):
			if _flat(point, b.global_position) <= PATROL_RANGE:
				return true
	return false


func _next_leg(ship: Unit, hangar: Building) -> void:
	var route := route_of(hangar)
	var stops := [hangar]
	stops.append_array(route)
	var leg: int = ship.get_meta("leg") % stops.size()
	var target: Node3D = stops[leg]
	if _flat(ship.global_position, target.global_position) <= 1.5:
		leg = (leg + 1) % stops.size()
		ship.set_meta("leg", leg)
		target = stops[leg]
	if stops.size() == 1:
		# No points yet: circle the hangar.
		var angle := float(Time.get_ticks_msec()) / 1000.0 * 0.5 + ship.get_instance_id() % 6
		_go(ship, hangar.global_position + Vector3(cos(angle), 0, sin(angle)) * 6.0, true)
		return
	_go(ship, target.global_position, true)


func _go(ship: Unit, to: Vector3, attack: bool) -> void:
	ship.set_route(PackedVector3Array([Vector3(to.x, ship.position.y, to.z)]), attack)


func _repair_near(ship: Unit, delta: float) -> void:
	for b in region.buildings.values():
		if b.faction == "player" and b.is_alive() and b.hp < b.max_hp and _flat(ship.global_position, b.global_position) <= REPAIR_RADIUS:
			b.repair(REPAIR_PER_SECOND * delta)


## A troop tender over one of your platforms with enemies on it drops its
## squad there, then heads home to reload.
func _maybe_drop(ship: Unit, _hangar: Building) -> void:
	if int(ship.get_meta("troops", 0)) <= 0:
		if ship.get_meta("state") == "patrol":
			ship.set_meta("state", "reload")
			ship.stop()
		return
	var here := region.platform_at(ship.position)
	if here == "" or region.platform_owner(here) != "player":
		return
	if region.units_on_platform(here, Unit.ENEMY_GROUP).is_empty():
		return
	drop_troops(ship)


## Drops a troop tender's squad on the deck below it. Returns the troops.
func drop_troops(ship: Unit) -> Array[Unit]:
	var out: Array[Unit] = []
	var offsets := SelectionController.formation_offsets_for(TROOPS.size(), 1.6)
	for i in TROOPS.size():
		var u := UnitCatalog.make(TROOPS[i])
		_count += 1
		u.name = "DroppedRiveteer%d" % _count
		u.position = region.snap_to_walkable(Vector3(ship.position.x, 0, ship.position.z) + offsets[i])
		_units_root().add_child(u)
		out.append(u)
	ship.set_meta("troops", 0)
	ship.set_meta("state", "reload")
	ship.stop()
	notice.emit("Your Troop Tender dropped %d Riveteers on %s" % [out.size(), region.platform_at(ship.position)])
	return out


func _reload(ship: Unit) -> void:
	if resources == null or resources.spend_scrap(TROOP_RELOAD_COST):
		ship.set_meta("troops", TROOPS.size())
		ship.set_meta("state", "patrol")
		ship.set_meta("leg", 0)
	# Can't pay yet: it waits at the hangar and tries again.


func _sync_hangars() -> void:
	var alive := {}
	for b in region.buildings.values():
		if b.type_id == HANGAR and b.faction == "player" and b.is_alive():
			alive[b] = true
			if not hangars.has(b):
				hangars[b] = {"ships": [], "queue": [], "timer": 0.0, "route": []}
	for h in hangars.keys():
		if not alive.has(h):
			# The hangar fell: its ships go to another hangar, or down.
			var others := alive.keys()
			for s in hangars[h].ships:
				if not is_instance_valid(s):
					continue
				if others.is_empty():
					s.take_damage(s.hp + 1.0)
				else:
					hangars[others[0]].ships.append(s)
			hangars.erase(h)
			_routes_dirty = true


## Thin gold markers along each hangar's patrol loop.
func _draw_routes() -> void:
	_routes_dirty = false
	if _routes_root:
		_routes_root.queue_free()
	_routes_root = Node3D.new()
	_routes_root.name = "PatrolRoutes"
	region.add_child(_routes_root)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.8, 0.3, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var dot := SphereMesh.new()
	dot.radius = 0.22
	dot.height = 0.44
	for h in hangars:
		var stops: Array = [h]
		stops.append_array(route_of(h))
		if stops.size() < 2:
			continue
		stops.append(h)
		for i in range(1, stops.size()):
			var a: Vector3 = stops[i - 1].global_position
			var b: Vector3 = stops[i].global_position
			var n := int(_flat(a, b) / 1.6)
			for k in range(1, n):
				var m := MeshInstance3D.new()
				m.mesh = dot
				m.material_override = mat
				var p := a.lerp(b, float(k) / n)
				m.position = Vector3(p.x, ALTITUDE, p.z)
				_routes_root.add_child(m)


## Marks the drawn routes stale (buildings came or went).
func mark_routes_dirty() -> void:
	_routes_dirty = true


func _building_under_mouse() -> Building:
	if camera == null:
		return null
	var cam := camera.camera
	var screen := get_viewport().get_mouse_position()
	var hit = Plane(Vector3.UP, 0.0).intersects_ray(cam.project_ray_origin(screen), cam.project_ray_normal(screen))
	if hit == null:
		return null
	return region.buildings.get(region.hex_at(hit))


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


func _units_root() -> Node3D:
	var root := region.get_parent().get_node_or_null("Units") as Node3D
	return root if root else region
