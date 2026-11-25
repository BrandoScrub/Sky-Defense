## Vesper Aeronautics, the second rival corporation. It fights from the air:
## each flight of bomber airships takes off from the Vesper Aerodrome, flies
## an air lane (region.layout.air_lanes), then bombs the nearest of your
## buildings, or your Hub's headquarters if there are none.
##
## Bombers ignore your units, and only anti-air weapons can hit them: Flak
## Batteries (strong), Rivet Turrets (weak), headquarters guns and the
## Commander.
class_name VesperFleet
extends Node

signal flight_sent(size: int)

const ALTITUDE := 7.0

@export var region: SkyRegion
@export var combat: CombatSystem
@export var home := "Vesper Aerodrome"
@export var formation_spacing := 2.4

var _count := 0
var _next_lane := 0


func _process(_delta: float) -> void:
	step()


## Gives idle bombers a new target. Public so tests can drive it.
func step() -> void:
	for node in get_tree().get_nodes_in_group(Unit.ENEMY_GROUP):
		var unit := node as Unit
		if not unit.flying or not unit.is_alive() or unit.is_moving():
			continue
		if combat and combat.nearest_enemy(unit.global_position, "rival", unit.attack_range, false, false) != null:
			continue
		var target := target_for(unit)
		if target != null:
			unit.set_route(PackedVector3Array([Vector3(target.global_position.x, 0, target.global_position.z)]), true)


## Lanes that start at the aerodrome, as [from, to] platform names.
func lanes() -> Array:
	return region.layout.air_lanes.filter(func(l): return l[0] == home)


## Launches `size` bombers along the next air lane. Returns them.
func send_flight(size: int) -> Array[Unit]:
	var out: Array[Unit] = []
	var all := lanes()
	if all.is_empty() or size <= 0:
		return out
	var lane: Array = all[_next_lane % all.size()]
	_next_lane += 1
	var start := region.get_platform_position(home)
	var end := region.get_platform_position(lane[1])
	var offsets := SelectionController.formation_offsets_for(size, formation_spacing)
	for i in size:
		_count += 1
		var u := Unit.new()
		u.name = "VesperBomber%d" % _count
		u.display_name = "Vesper Bomber"
		u.faction = "rival"
		u.flying = true
		u.targets_units = false
		u.move_speed = 5.0
		u.weight = 0
		u.max_hp = 110.0
		u.damage = 30.0
		u.attack_range = 2.5
		u.attack_cooldown = 2.5
		u.bounty = 25
		u.footprint = 0.9
		u.body_color = Color(0.18, 0.22, 0.45)
		u.position = start + offsets[i] + Vector3.UP * ALTITUDE
		_units_root().add_child(u)
		# Fly the lane first, bombing anything of yours right under it.
		u.set_route(PackedVector3Array([end + offsets[i]]), true)
		out.append(u)
	flight_sent.emit(size)
	return out


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
