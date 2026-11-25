## Runs every fight in the region: picks targets, applies damage on cooldown,
## draws tracers, pays bounties and clears out the dead.
##
## - Units shoot the nearest enemy in range. Idle or attack-moving units also
##   walk toward enemies within their aggro range. A plain move order ignores
##   enemies until the unit arrives (like the reference game's RTS controls).
## - Towers shoot the nearest enemy in range. Their fire rate scales with grid
##   efficiency, and they miss more on an overloaded platform.
## - Headquarters have a light gun of their own.
class_name CombatSystem
extends Node

signal building_destroyed(building_name: String, faction: String)
signal headquarters_destroyed(faction: String, platform: String)
signal unit_killed(unit: Unit)

## Chance to miss for towers on a platform in each overload state.
const MISS_CHANCE := {"Stable": 0.0, "Swaying": 0.15, "Sagging": 0.3, "Failing": 0.45}
## How far an Arc Coil's lightning can jump between targets.
const CHAIN_JUMP := 5.0

@export var region: SkyRegion
@export var resources: PlayerResources
@export var loads: LoadSystem

var rng := RandomNumberGenerator.new()
var _chase_timer := 0.0


func _ready() -> void:
	rng.seed = 1234


func _process(delta: float) -> void:
	step(delta)


## Spawns a Headquarters on every core tile. Called once after the region is built.
func spawn_headquarters() -> void:
	for hex in region.tiles:
		var t: Dictionary = region.tiles[hex]
		if t.type == "core" or t.type == "rival_core":
			var hq := Headquarters.new()
			hq.name = "HQ_" + t.platform.replace(" ", "")
			hq.faction = "player" if t.type == "core" else "rival"
			hq.platform = t.platform
			if hq.faction == "rival":
				hq.max_hp = 800.0
			hq.position = region.hex_center(hex)
			region.add_child(hq)
			hq.destroyed.connect(_on_headquarters_destroyed)


## Advances all fighting by `delta` seconds. Public so tests can drive it.
func step(delta: float) -> void:
	_chase_timer -= delta
	var chase := _chase_timer <= 0.0
	if chase:
		_chase_timer = 0.5

	for faction in ["player", "rival"]:
		for unit in _units(faction):
			if not unit.is_alive() or unit.riding:
				continue
			unit.cooldown_left -= delta
			var target = nearest_enemy(unit.global_position, faction, unit.attack_range, unit.hits_air, unit.targets_units)
			if target != null:
				if not unit.is_moving() or unit.attack_move:
					unit.stop()
				if unit.cooldown_left <= 0.0 and not unit.is_moving():
					unit.cooldown_left = unit.attack_cooldown
					_hit(unit, target, unit.damage, Color(1.0, 0.85, 0.4))
			elif chase and not unit.flying and (not unit.is_moving() or unit.attack_move):
				var prey = nearest_enemy(unit.global_position, faction, unit.aggro_range, unit.hits_air, unit.targets_units)
				if prey == null and faction == "player" and not unit.is_moving():
					prey = _intruder_on_platform(unit)
				if prey != null:
					var route := region.find_route(unit.position, region.snap_to_walkable(prey.global_position))
					if not route.is_empty():
						unit.set_route(route, true)

	for b in region.buildings.values().duplicate():
		var attack: Dictionary = b.get_attack()
		if attack.is_empty() or not b.is_alive():
			continue
		b.cooldown_left -= delta * maxf(b.efficiency, 0.05)
		if b.cooldown_left > 0.0:
			continue
		var target = nearest_enemy(b.global_position, b.faction, attack.range, attack.has("air"))
		if target == null:
			continue
		var amount: float = attack.air if target is Unit and target.flying else attack.damage
		b.cooldown_left = attack.cooldown
		var miss: float = MISS_CHANCE.get(loads.state_of(b.platform) if loads else "Stable", 0.0)
		if rng.randf() < miss:
			_tracer(b.global_position + Vector3.UP * 1.2, target.global_position + Vector3(1.5, 1, 0), Color(0.7, 0.7, 0.7))
			continue
		_hit(b, target, amount, Color(0.6, 0.7, 1.0) if attack.has("chain") else Color(1.0, 0.85, 0.4))
		if attack.has("chain"):
			_chain(target, b.faction, amount * 0.7, int(attack.chain) - 1)

	for hq in get_tree().get_nodes_in_group(Headquarters.GROUP):
		if not hq.is_alive():
			continue
		hq.cooldown_left -= delta
		if hq.cooldown_left > 0.0:
			continue
		var target = nearest_enemy(hq.global_position, hq.faction, hq.attack.range, true)
		if target != null:
			hq.cooldown_left = hq.attack.cooldown
			_hit(hq, target, hq.attack.damage, Color(1.0, 0.6, 0.3))


## The closest living enemy of `faction` within `max_range`: a unit, a
## building or a headquarters. Null if none. Aircraft only count when
## `hits_air`; bombers pass `hits_units` false to ignore units entirely.
func nearest_enemy(from: Vector3, faction: String, max_range: float, hits_air := false, hits_units := true):
	var best = null
	var best_d := max_range
	var other := "rival" if faction == "player" else "player"
	for unit in _units(other):
		if not hits_units or (unit.flying and not hits_air):
			continue
		if unit.is_alive() and not unit.riding:
			var d := _flat_distance(from, unit.global_position)
			if d <= best_d:
				best_d = d
				best = unit
	for b in region.buildings.values():
		if b.faction == other and b.is_alive():
			var d := _flat_distance(from, b.global_position)
			if d <= best_d:
				best_d = d
				best = b
	for hq in get_tree().get_nodes_in_group(Headquarters.GROUP):
		if hq.faction == other and hq.is_alive():
			# Headquarters are big: count range from their edge.
			var d := _flat_distance(from, hq.global_position) - region.tile_size
			if d <= best_d:
				best_d = d
				best = hq
	return best


## An enemy unit standing on the same platform as an idle player unit, so a
## squad parked anywhere on the Hub defends all of it.
func _intruder_on_platform(unit: Unit):
	var here := region.platform_at(unit.position)
	if here == "" or region.platform_owner(here) != "player":
		return null
	var best = null
	var best_d := INF
	for foe in _units("rival"):
		if foe.is_alive() and not foe.riding and (not foe.flying or unit.hits_air) and region.platform_at(foe.position) == here:
			var d := _flat_distance(unit.global_position, foe.global_position)
			if d < best_d:
				best_d = d
				best = foe
	return best


func _hit(attacker: Node3D, target: Node3D, amount: float, color: Color) -> void:
	_tracer(attacker.global_position + Vector3.UP * 1.2, target.global_position + Vector3.UP * 1.0, color)
	if target is Building:
		var b := target as Building
		if b.take_damage(amount):
			region.remove_building(b.hex)
			building_destroyed.emit(b.get_data().name, b.faction)
			b.queue_free()
	elif target is Unit:
		var u := target as Unit
		var was_alive := u.hp > 0.0
		u.take_damage(amount)
		if was_alive and u.hp <= 0.0:
			if u.faction == "rival" and resources:
				resources.add_scrap(u.bounty)
			unit_killed.emit(u)
	else:
		target.take_damage(amount)


func _chain(first: Node3D, faction: String, amount: float, jumps: int) -> void:
	var hit := [first]
	var from := first
	for i in jumps:
		var next = null
		var best := CHAIN_JUMP
		for unit in _units("rival" if faction == "player" else "player"):
			if unit.is_alive() and not unit.flying and not hit.has(unit):
				var d := _flat_distance(from.global_position, unit.global_position)
				if d <= best:
					best = d
					next = unit
		if next == null:
			return
		_hit(from, next, amount, Color(0.6, 0.7, 1.0))
		hit.append(next)
		from = next


func _units(faction: String) -> Array[Unit]:
	var out: Array[Unit] = []
	for node in get_tree().get_nodes_in_group(Unit.GROUP if faction == "player" else Unit.ENEMY_GROUP):
		out.append(node as Unit)
	return out


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


## The living headquarters on a platform, or null.
func headquarters_on(platform_name: String) -> Headquarters:
	for hq in get_tree().get_nodes_in_group(Headquarters.GROUP):
		if hq.platform == platform_name and hq.is_alive():
			return hq
	return null


func _on_headquarters_destroyed(hq: Headquarters) -> void:
	headquarters_destroyed.emit(hq.faction, hq.platform)


## A short-lived line from shooter to target.
func _tracer(from: Vector3, to: Vector3, color: Color) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var line := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	var length := from.distance_to(to)
	mesh.size = Vector3(0.08, 0.08, length)
	line.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	line.material_override = mat
	region.add_child(line)
	line.global_position = (from + to) / 2.0
	if length > 0.01:
		line.look_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)
	var tween := line.create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.15)
	tween.tween_callback(line.queue_free)
