## The support side of defenses (CombatSystem does the shooting):
##
## - Ground-defense auras: each building with an "aura" in BuildingCatalog
##   (the Rally Horn) boosts its own side's ground units within the aura's
##   radius, and sounds every HORN_EVERY seconds with a ring showing it. Bonuses
##   from several buildings don't stack; a unit gets the best of each kind.
##   A building in a brownout gives a weaker aura.
## - Hangars: each building with a "hangar" entry keeps a few drones in the
##   air. Drones fly out to the nearest enemy within the hangar's leash,
##   fight it, and come back. Lost drones are rebuilt after a while (slower
##   in a brownout). If the hangar falls, its drones go down with it.
class_name DefenseSystem
extends Node

## Height drones fly at, above the deck.
const DRONE_ALTITUDE := 4.5
## How far from its hangar an idle drone circles.
const ORBIT_RADIUS := 2.0
## Seconds between blasts of an aura tower's horn (a ring shows its reach).
const HORN_EVERY := 4.0

@export var region: SkyRegion
@export var combat: CombatSystem

## Hangar Building -> {"drones": Array[Unit], "timer": float}
var hangars := {}
var _count := 0
var _time := 0.0
var _horn_beat := -1


func _process(delta: float) -> void:
	step(delta)


## Advances auras and hangars by `delta` seconds. Public so tests can drive it.
func step(delta: float) -> void:
	_time += delta
	_apply_auras(delta)
	_run_hangars(delta)


## The drones a hangar currently has in the air.
func drones_of(hangar: Building) -> Array:
	return hangars.get(hangar, {}).get("drones", [])


func _apply_auras(delta: float) -> void:
	var sources: Array[Building] = []
	for b in region.buildings.values():
		if b.is_alive() and b.get_data().has("aura"):
			sources.append(b)
	var beat := int(_time / HORN_EVERY)
	if beat != _horn_beat:
		_horn_beat = beat
		for b in sources:
			if b.efficiency > 0.0:
				CombatFx.ring(region, b.global_position, b.get_data().aura.radius, Color(1.0, 0.78, 0.35, 0.75) if b.faction == "player" else Color(1.0, 0.4, 0.3, 0.75))
	for group in [Unit.GROUP, Unit.ENEMY_GROUP]:
		for node in get_tree().get_nodes_in_group(group):
			var u := node as Unit
			u.reset_support()
			if u.flying or u.riding or not u.is_alive():
				continue
			var heal := 0.0
			for b in sources:
				if b.faction != u.faction:
					continue
				var aura: Dictionary = b.get_data().aura
				if _flat(b.global_position, u.global_position) > aura.radius:
					continue
				var strength := clampf(b.efficiency, 0.0, 1.0)
				u.damage_mult = maxf(u.damage_mult, lerpf(1.0, aura.get("damage_mult", 1.0), strength))
				u.cooldown_mult = minf(u.cooldown_mult, lerpf(1.0, aura.get("cooldown_mult", 1.0), strength))
				u.armor = maxf(u.armor, aura.get("armor", 0.0) * strength)
				heal = maxf(heal, aura.get("heal", 0.0) * strength)
			if heal > 0.0:
				u.heal(heal * delta)


func _run_hangars(delta: float) -> void:
	# Forget hangars that are gone, and ground their drones.
	for hangar in hangars.keys():
		if not is_instance_valid(hangar) or not hangar.is_alive() or not region.buildings.values().has(hangar):
			for d in hangars[hangar].drones:
				if is_instance_valid(d):
					d.queue_free()
			hangars.erase(hangar)
	for b in region.buildings.values():
		if b.is_alive() and b.get_data().has("hangar") and not hangars.has(b):
			# A new hangar launches its first drone right away.
			hangars[b] = {"drones": [], "timer": 0.0}

	for hangar in hangars:
		var state: Dictionary = hangars[hangar]
		var spec: Dictionary = hangar.get_data().hangar
		state.drones = state.drones.filter(func(d): return is_instance_valid(d) and d.is_alive())
		if state.drones.size() < spec.drones:
			state.timer -= delta * maxf(hangar.efficiency, 0.05)
			if state.timer <= 0.0:
				state.timer = spec.rebuild
				state.drones.append(_launch(hangar))
		else:
			state.timer = 0.0
		for i in state.drones.size():
			_steer(state.drones[i], hangar, spec.leash, i, state.drones.size())


func _launch(hangar: Building) -> Unit:
	_count += 1
	var d := Unit.new()
	d.name = "Drone%d" % _count
	d.display_name = "Defense Drone"
	d.faction = hangar.faction
	d.is_drone = true
	d.flying = true
	d.hits_air = true
	d.hull = "light"
	d.weight = 0
	d.move_speed = 9.0
	d.max_hp = 35.0
	d.damage = 5.0
	d.attack_range = 4.0
	d.attack_cooldown = 0.7
	d.footprint = 0.45
	d.body_color = Color(0.8, 0.65, 0.3) if hangar.faction == "player" else Color(0.6, 0.3, 0.3)
	d.position = hangar.global_position + Vector3.UP * DRONE_ALTITUDE
	_units_root().add_child(d)
	return d


## Sends a drone at the nearest enemy near its hangar, or back home.
func _steer(drone: Unit, hangar: Building, leash: float, index: int, total: int) -> void:
	var target = combat.nearest_enemy(hangar.global_position, hangar.faction, leash, true) if combat else null
	var goal: Vector3
	if target != null:
		if _flat(drone.global_position, target.global_position) <= drone.attack_range * 0.8:
			return
		goal = target.global_position
	else:
		var angle := TAU * index / maxf(total, 1) + _time * 0.6
		goal = hangar.global_position + Vector3(cos(angle), 0, sin(angle)) * ORBIT_RADIUS
		if _flat(drone.global_position, goal) < 0.5:
			return
	drone.set_route(PackedVector3Array([Vector3(goal.x, drone.position.y, goal.z)]), true)


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


func _units_root() -> Node3D:
	var root := region.get_parent().get_node_or_null("Units") as Node3D
	return root if root else region
