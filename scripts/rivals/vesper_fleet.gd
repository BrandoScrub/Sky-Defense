## Every rival airship (the class keeps its old name; Vesper was the first
## corporation to fly). Kinds, in AIRSHIPS:
##   bomber  - Vesper. Each wave its bombers fly its wind lane from the Vesper
##             Aerodrome to your richest outer island (the one with the most
##             scrap in buildings; the Hub if you have none), then make
##             bombing runs: they fly straight over the nearest of your
##             buildings there (or the Hub's headquarters), turn and come
##             back. Over any of your buildings they drop a bomb, which
##             lands a moment later (its shadow shows where) and blasts
##             everything of yours nearby, troops included. Heavy hull.
##             The rival card names the target.
##   gunship - Vesper escort. Hunts your units and drones, in the air and on
##             the decks, then your buildings. Light hull.
##   carrier - Ironbell troop carrier. Flies to your platform nearest its HQ,
##             hovers, drops a squad onto the deck, and flies home. Shoot it
##             down on the way in and the troops go down with it. Heavy hull.
##
## Hulls (Unit.hull): flak bursts shred light craft and hurt heavy ones
## less; the Skyhook does double damage to heavy hulls. A heavy hull that is
## shot down falls, and crushes whatever is under it if it lands on an
## island, yours or theirs (CombatSystem).
##
## Wind lanes: each rival that flies airships has one broad lane from its
## HQ to its target, following the wind round to the target's upwind side.
## Every airship weaves its own line down the lane between the islands
## (AirNav.plan_weave), so a wave spreads out. They fly faster with a
## tailwind and slower into a headwind. When the wind turns (WindSystem,
## every 3 waves) the lanes are replanned and redrawn, and attacks come
## from a new side.
## Only anti-air weapons can hit airships: flak, hangar drones, headquarters
## guns and the Commander.
class_name VesperFleet
extends Node

signal flight_sent(size: int)
## Any airships launched (bombers too): corp, AIRSHIPS kind, how many.
signal airships_launched(corp: String, kind: String, count: int)
## A carrier dropped its squad on one of your platforms.
signal troops_dropped(corp: String, platform: String, units: Array)

const ALTITUDE := 7.0
## A full tailwind speeds an airship up by this share; a headwind slows it.
const WIND_SPEED := 0.3
## Seconds a carrier hovers before its troops are down.
const UNLOAD_SECONDS := 1.5
## Bombers start a straight run when this close to their target, and fly
## this far past it before turning back for the next run.
const RUN_START := 12.0
const RUN_OVERSHOOT := 7.0
## A bomb is dropped when a bomber is this close (flat) to one of your
## buildings, or to the edge of your headquarters.
const BOMB_REACH := 1.4

const AIRSHIPS := {
	"bomber": {
		# damage: each bomb's blast; cooldown: seconds between bombs.
		"name": "Vesper Bomber", "corp": "Vesper", "hp": 110.0, "damage": 20.0, "range": 2.5,
		"cooldown": 2.0, "speed": 5.0, "bounty": 25, "footprint": 0.9, "hull": "heavy",
		"color": Color(0.18, 0.22, 0.45), "targets_units": false, "hits_air": false,
	},
	"gunship": {
		"name": "Vesper Gunship", "corp": "Vesper", "hp": 90.0, "damage": 9.0, "range": 5.0,
		"cooldown": 0.8, "speed": 6.0, "bounty": 20, "footprint": 0.65, "hull": "light",
		"color": Color(0.32, 0.42, 0.7), "targets_units": true, "hits_air": true,
	},
	"carrier": {
		"name": "Ironbell Troop Carrier", "corp": "Ironbell", "hp": 220.0, "damage": 0.0, "range": 0.0,
		"cooldown": 99.0, "speed": 6.0, "bounty": 35, "footprint": 1.3, "hull": "heavy",
		"color": Color(0.45, 0.22, 0.16), "targets_units": false, "hits_air": false,
		"troops": ["shieldbearer", "rifleman", "riveteer"],
	},
}

@export var region: SkyRegion
@export var combat: CombatSystem
@export var home := "Vesper Aerodrome"
@export var formation_spacing := 2.4
## How far a gunship looks for your units to hunt.
@export var gunship_hunt_range := 40.0
## Optional: the wind bends the routes when set.
@export var wind: WindSystem:
	set(value):
		wind = value
		if wind and not wind.wind_changed.is_connected(_on_wind_changed):
			wind.wind_changed.connect(_on_wind_changed)

var nav: AirNav
var _count := 0
## corp -> the island its lane is drawn to, to notice when the target moves.
var _drawn_target := {}
var _target_timer := 0.0
var _next_lane := 0
var _drawn_version := -1
## Picks each airship's weave through its wind lane.
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = hash(["weave", SkyRegion.seed_override])
	if SkyRegion.seed_override < 0:
		_rng.randomize()
	_ensure_nav()
	# Replace the lanes the map drew with one to this wave's target.
	refresh_lanes.call_deferred()


func _ensure_nav() -> AirNav:
	if nav == null:
		nav = AirNav.new(region)
	return nav


func _process(delta: float) -> void:
	# A balloon island moved: replan the drawn lanes around it.
	if wind and nav and region.tiles_version != _drawn_version:
		refresh_lanes()
	# The bombers' target follows what you build: redraw when it moves.
	_target_timer -= delta
	if _target_timer <= 0.0:
		_target_timer = 0.5
		if _drawn_target != _lane_targets():
			refresh_lanes()
	step(delta)


## Display name of an airship kind, e.g. "Ironbell Troop Carrier".
static func name_of(kind: String) -> String:
	return AIRSHIPS[kind].name


## The headquarters platform of a corporation, or "".
func hq_of(corp: String) -> String:
	var path: Array = region.layout.get("paths", {}).get(corp, [])
	return path[path.size() - 1] if not path.is_empty() else ""


## Gives idle airships new orders and sets their wind speed. Public so tests
## can drive it.
func step(delta := 0.0) -> void:
	for node in get_tree().get_nodes_in_group(Unit.ENEMY_GROUP):
		var unit := node as Unit
		if not unit.flying or not unit.is_alive():
			continue
		unit.wind_multiplier = wind_speed_for(unit)
		match unit.get_meta("airship", "bomber"):
			"carrier":
				_step_carrier(unit, delta)
			"gunship":
				_step_gunship(unit)
			_:
				_step_bomber(unit, delta)


## Speed factor from the wind for where this airship is heading.
func wind_speed_for(unit: Unit) -> float:
	if wind == null or not unit.is_moving():
		return 1.0
	var to := unit.next_waypoint() - unit.position
	to.y = 0.0
	if to.length() < 0.01:
		return 1.0
	return 1.0 + WIND_SPEED * to.normalized().dot(wind.blowing())


func _step_bomber(unit: Unit, _delta := 0.0) -> void:
	# Bombs away over anything of yours below (CombatSystem counts the
	# cooldown down).
	if combat and unit.cooldown_left <= 0.0 and over_target(unit.global_position):
		unit.cooldown_left = unit.get_attack_cooldown()
		combat.drop_bomb(unit.global_position, "rival", unit.get_damage())
	if unit.is_moving():
		return
	var target := target_for(unit)
	if target == null:
		return
	var to := target.global_position - unit.global_position
	to.y = 0.0
	if to.length() > RUN_START:
		_fly(unit, target.global_position)
		return
	# A straight run over the target and out the other side; the next run
	# comes back the other way.
	var dir := to.normalized() if to.length() > 1.0 else unit.forward()
	unit.set_route(PackedVector3Array([target.global_position + dir * RUN_OVERSHOOT]))


## True when a bomber at `point` is over one of your buildings or your
## headquarters.
func over_target(point: Vector3) -> bool:
	for b in region.buildings.values():
		if b.faction == "player" and b.is_alive() and _flat(point, b.global_position) <= BOMB_REACH:
			return true
	for hq in get_tree().get_nodes_in_group(Headquarters.GROUP):
		if hq.faction == "player" and hq.is_alive() and _flat(point, hq.global_position) <= region.tile_size + BOMB_REACH:
			return true
	return false


func _step_gunship(unit: Unit) -> void:
	if combat == null:
		return
	# Your units and drones come first: a gunship flies to the nearest one
	# within hunt range, even past buildings, and only goes for buildings or
	# the Hub when there is no one left to hunt.
	var prey = combat.nearest_enemy_unit(unit.global_position, "rival", gunship_hunt_range, true)
	if prey != null:
		var gap := Vector2(unit.global_position.x - prey.global_position.x, unit.global_position.z - prey.global_position.z).length()
		if gap <= unit.attack_range * 0.9:
			return
		# Re-aim at most twice a second while chasing a moving target.
		var chase_left: float = unit.get_meta("rechase", 0.0) - get_process_delta_time()
		unit.set_meta("rechase", chase_left)
		if unit.is_moving() and chase_left > 0.0:
			return
		unit.set_meta("rechase", 0.5)
		_fly(unit, prey.global_position)
		return
	# While flying it attack-moves: combat stops it to shoot whatever's near.
	if unit.is_moving():
		return
	if combat.nearest_enemy(unit.global_position, "rival", unit.attack_range, true, true) != null:
		return
	var target = target_for(unit)
	if target != null:
		_fly(unit, target.global_position)


func _step_carrier(unit: Unit, delta: float) -> void:
	if unit.is_moving():
		return
	var target: String = unit.get_meta("carrier_target", "Hub")
	match unit.get_meta("carrier_state", "inbound"):
		"inbound":
			if region.platform_at(unit.position) == target:
				unit.set_meta("carrier_state", "unloading")
				unit.set_meta("unload_left", UNLOAD_SECONDS)
			else:
				_fly(unit, region.get_platform_position(target), true)
		"unloading":
			var left: float = unit.get_meta("unload_left", 0.0) - delta
			unit.set_meta("unload_left", left)
			if left <= 0.0:
				drop_troops(unit)
		"outbound":
			# Home again: it leaves the fight.
			unit.remove_from_group(Unit.ENEMY_GROUP)
			unit.queue_free()


## Puts a carrier's squad on the deck below it and sends it home. Returns
## the troops.
func drop_troops(carrier: Unit) -> Array[Unit]:
	var out: Array[Unit] = []
	var spec: Dictionary = AIRSHIPS.carrier
	var platform_name := region.platform_at(carrier.position)
	var offsets := SelectionController.formation_offsets_for(spec.troops.size(), 1.6)
	for i in spec.troops.size():
		_count += 1
		var u := UnitCatalog.make(spec.troops[i], "rival")
		u.set_meta("corp", carrier.get_meta("corp", "Ironbell"))
		u.name = "Dropped%s%d" % [String(spec.troops[i]).capitalize(), _count]
		u.set_meta("raid_index", _count)
		u.position = region.snap_to_walkable(Vector3(carrier.position.x, 0, carrier.position.z) + offsets[i])
		_units_root().add_child(u)
		out.append(u)
	carrier.set_meta("carrier_state", "outbound")
	var back := hq_of(carrier.get_meta("corp", "Ironbell"))
	if back != "":
		_fly(carrier, region.get_platform_position(back))
	troops_dropped.emit(carrier.get_meta("corp", "Ironbell"), platform_name, out)
	return out


## Your platform a carrier from `corp` lands troops on: the one nearest its
## headquarters.
func drop_target(corp: String) -> String:
	var hq := hq_of(corp)
	var from := region.get_platform_position(hq) if hq != "" else Vector3.ZERO
	var best := "Hub"
	var best_d := INF
	for p in region.platforms:
		if region.platform_owner(p) == "player":
			var d := from.distance_to(region.get_platform_position(p))
			if d < best_d:
				best_d = d
				best = p
	return best


## The wind lane a corporation's airships fly this wave (Vesper's by
## default), as [[from, to]] platform names: from its HQ to lane_target().
## Empty for a rival that flies no airships or whose HQ has fallen.
func lanes(corp := "") -> Array:
	if corp == "":
		corp = RivalCatalog.corp_at(home)
	if not _air_corps().has(corp):
		return []
	return [[hq_of(corp), lane_target(corp)]]


## Every rival's wind lane, as lanes() does for one.
func all_lanes() -> Array:
	var out := []
	for corp in _air_corps():
		out.append_array(lanes(corp))
	return out


## Where a corporation's airships head: bombers and gunships for
## bomb_target(), troop carriers for drop_target().
func lane_target(corp: String) -> String:
	for w in RivalCatalog.get_data(corp).get("waves", []):
		if w.unit == "bomber" or w.unit == "gunship":
			return bomb_target(corp)
	return drop_target(corp)


## Corporations on this map that fly airships and still have an HQ.
func _air_corps() -> Array:
	var out := []
	for corp in region.layout.get("paths", {}):
		var hq := hq_of(corp)
		if hq == "" or not region.platforms.has(hq):
			continue
		if combat and combat.headquarters_on(hq) == null:
			continue
		if RivalCatalog.get_data(corp).get("waves", []).any(func(w): return AIRSHIPS.has(w.unit)):
			out.append(corp)
	return out


## corp -> lane target, for every rival flying a lane now.
func _lane_targets() -> Dictionary:
	var out := {}
	for corp in _air_corps():
		out[corp] = lane_target(corp)
	return out


## The island a rival's bombers go for: your outer island with the most
## scrap sunk into buildings (ties go to the one further from the Hub), or
## the Hub when no outer island has any. So flak has to be where your
## islands are, not just beside your headquarters.
func bomb_target(_corp := "") -> String:
	var best := "Hub"
	var best_value := 0
	var best_d := -1.0
	var hub := region.get_platform_position("Hub")
	for p in region.platforms:
		if p == "Hub" or region.platform_owner(p) != "player":
			continue
		var value := 0
		for b in region.buildings_on(p):
			if b.faction == "player" and b.is_alive():
				value += int(b.get_data().get("cost", 0))
		if value <= 0:
			continue
		var d := hub.distance_to(region.get_platform_position(p))
		if value > best_value or (value == best_value and d > best_d):
			best = p
			best_value = value
			best_d = d
	return best


## Launches `size` bombers down the wind lane. Returns them.
func send_flight(size: int, corp := "") -> Array[Unit]:
	var out := launch("bomber", size, corp)
	if not out.is_empty():
		flight_sent.emit(size)
	return out


## Launches `count` airships of a kind from their corporation's HQ. Bombers
## and gunships head for bomb_target, carriers for drop_target. Each one
## weaves its own way down the corporation's wind lane (AirNav.plan_weave).
## `corp` flies them (default: the kind's own corporation in AIRSHIPS).
func launch(kind: String, count: int, corp := "") -> Array[Unit]:
	var out: Array[Unit] = []
	var spec: Dictionary = AIRSHIPS[kind]
	if corp == "":
		corp = spec.corp
	var start_name := hq_of(corp)
	if count <= 0 or start_name == "" or not region.platforms.has(start_name):
		return out
	var start := region.get_platform_position(start_name)
	var target_name := drop_target(corp) if kind == "carrier" else bomb_target(corp)
	var end := region.get_platform_position(target_name)
	var offsets := SelectionController.formation_offsets_for(count, formation_spacing)
	var lane := _ensure_nav().weave_lane(start, end)
	for i in count:
		_count += 1
		var u := _make(kind)
		u.name = "%s%d" % [String(spec.name).replace(" ", ""), _count]
		u.set_meta("corp", corp)
		if kind == "carrier":
			u.set_meta("carrier_target", target_name)
			u.set_meta("carrier_state", "inbound")
		u.position = start + offsets[i] + Vector3.UP * ALTITUDE
		_units_root().add_child(u)
		# Fly its own line down the lane first, attacking anything in reach
		# on the way. Only the end keeps the formation, so they don't stack.
		var mine := nav.plan_weave(start + offsets[i], end, _rng, lane)
		if mine.is_empty():
			mine = PackedVector3Array([end])
		mine[mine.size() - 1] = Vector3(end.x, 0.0, end.z) + offsets[i]
		u.set_route(mine, kind != "carrier")
		out.append(u)
	airships_launched.emit(corp, kind, count)
	return out


func _make(kind: String) -> Unit:
	var spec: Dictionary = AIRSHIPS[kind]
	var u := Unit.new()
	u.display_name = spec.name
	u.faction = "rival"
	u.flying = true
	u.targets_units = spec.targets_units
	u.hits_air = spec.hits_air
	u.move_speed = spec.speed
	u.weight = 0
	u.max_hp = spec.hp
	u.damage = spec.damage
	u.attack_range = spec.range
	u.attack_cooldown = spec.cooldown
	u.bounty = spec.bounty
	u.footprint = spec.footprint
	u.hull = spec.hull
	u.body_color = spec.color
	u.set_meta("airship", kind)
	if kind == "bomber":
		u.set_meta("bomb_runs", true)
	if kind == "gunship":
		u.set_meta("hunt_range", gunship_hunt_range)
	return u


## Flies a unit to a point through open sky, upwind-first when `attack`.
func _fly(unit: Unit, to: Vector3, attack := false) -> void:
	var route := _ensure_nav().plan_attack(unit.global_position, to) if attack else _ensure_nav().plan(unit.global_position, to)
	if route.is_empty():
		route = PackedVector3Array([Vector3(to.x, 0, to.z)])
	unit.set_route(route, unit.get_meta("airship", "bomber") != "carrier")


## The flight path for a lane: around islands, swinging upwind of the
## target to make the run with the wind.
func route_for(lane: Array) -> PackedVector3Array:
	return _ensure_nav().plan_attack(region.get_platform_position(lane[0]), region.get_platform_position(lane[1]))


## Replans and redraws every rival's wind lane for the current wind, each
## in its corporation's colour.
func refresh_lanes() -> void:
	_drawn_version = region.tiles_version
	for corp in _drawn_target:
		region.clear_air_routes_from(hq_of(corp))
	for corp in region.layout.get("paths", {}):
		region.clear_air_routes_from(hq_of(corp))
	_drawn_target = {}
	for corp in _air_corps():
		var tint: Color = RivalCatalog.get_data(corp).get("glow", [SkyRegion.COLORS.air_lane])[0]
		for lane in lanes(corp):
			region.set_air_route(lane[0], lane[1], route_for(lane), false, tint)
			_drawn_target[corp] = lane[1]
	region.air_routes_changed.emit()


func _on_wind_changed(_from_index: int, _first: bool) -> void:
	var blow := wind.blowing()
	_ensure_nav().wind = Vector2(blow.x, blow.z)
	refresh_lanes()


## The nearest of the player's buildings, or the Hub's headquarters.
func target_for(unit: Unit) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for b in region.buildings.values():
		if b.faction == "player" and b.is_alive():
			var d := _flat(unit.position, b.global_position)
			if d < best_d:
				best_d = d
				best = b
	if best:
		return best
	for hq in get_tree().get_nodes_in_group(Headquarters.GROUP):
		if hq.faction == "player" and hq.is_alive():
			return hq
	return null


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


func _units_root() -> Node3D:
	var root := region.get_parent().get_node_or_null("Units") as Node3D
	return root if root else region
