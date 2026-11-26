## A rival's raiding parties (one RivalRaids per rival that walks; main sets
## corp, rival_platform and party_mix from RivalCatalog). Each party spawns on the rival's wave spawn tile,
## marches along walkways toward the player's Hub, and stops to claim every
## platform on the way that isn't already Ironbell's. There's no combat yet:
## park your own units on a platform to contest it.
##
## WaveManager decides when parties leave. Raiders fight anything they meet on
## the way (they always attack-move).
class_name RivalRaids
extends Node

signal raid_sent(size: int)

@export var region: SkyRegion
@export var capture: CaptureSystem
## Optional: lets raiders hold position while enemies are close.
@export var combat: CombatSystem
## Optional: while Ironbell's bridge doesn't reach the target yet, raiders
## wait at the end of it.
@export var bridges: RivalBridges
@export var corp := "Ironbell"
@export var rival_platform := "Ironbell HQ"
@export var target_platform := "Hub"
@export var party_size := 3
@export var auto_raids := false
@export var seconds_between_raids := 90.0
@export var formation_spacing := 1.8
## What each place in a raiding party is, repeating. Ironbell is mostly
## armored walkers, with the same base troops the player trains mixed into
## bigger parties (the first 3 raiders are always walkers).
@export var party_mix: Array[String] = ["walker", "walker", "walker", "shieldbearer", "rifleman"]

var _timer := 0.0
var _count := 0


func _process(delta: float) -> void:
	if auto_raids:
		_timer += delta
		if _timer >= seconds_between_raids:
			_timer = 0.0
			send_party()
	for node in get_tree().get_nodes_in_group(Unit.ENEMY_GROUP):
		var unit := node as Unit
		# Airships take their orders from VesperFleet.
		if unit.flying:
			continue
		if not unit.is_moving():
			if combat and combat.nearest_enemy(unit.global_position, "rival", unit.aggro_range) != null:
				continue
			_give_orders(unit)


## Spawns a raiding party on the rival spawn tile. Returns the new units.
func send_party(size := party_size) -> Array[Unit]:
	var spawn := _spawn_point()
	var out: Array[Unit] = []
	var offsets := SelectionController.formation_offsets_for(size, formation_spacing)
	for i in size:
		_count += 1
		var type_id := unit_for_slot(i)
		var u := UnitCatalog.make(type_id, "rival")
		u.name = "%sWalker%d" % [corp, _count] if type_id == "walker" else "%s%s%d" % [corp, type_id.capitalize().replace(" ", ""), _count]
		u.set_meta("raid_index", _count)
		u.set_meta("corp", corp)
		u.position = region.snap_to_walkable(spawn + offsets[i])
		_units_root().add_child(u)
		out.append(u)
	raid_sent.emit(size)
	return out


## The UnitCatalog type for a place in a raiding party.
func unit_for_slot(slot: int) -> String:
	return party_mix[slot % party_mix.size()] if not party_mix.is_empty() else "walker"


## The platform a raider should head for next: the first one on the road to
## the target that Ironbell doesn't own yet, or the target itself.
func next_objective(from: Vector3) -> String:
	var route := _route(from, _target_point())
	for platform_name in region.platforms_along(from, route):
		if region.platform_owner(platform_name) != "rival" and capture.is_claimable(platform_name):
			return platform_name
	return target_platform


func _give_orders(unit: Unit) -> void:
	var here := region.platform_at(unit.position)
	var objective := next_objective(unit.position)
	# Stay put while claiming the platform we're standing on.
	if here == objective and objective != target_platform:
		return
	var goal: Vector3
	if objective == target_platform:
		goal = _target_point()
	else:
		goal = region.get_platform_position(objective)
	var index := int(unit.get_meta("raid_index", 0)) % 6
	var offsets := SelectionController.formation_offsets_for(6, formation_spacing)
	var target := region.snap_to_walkable(goal + offsets[index])
	if unit.position.distance_to(target) < 0.5:
		return
	var route := _route(unit.position, target)
	if route.is_empty():
		route = _route_to_frontier(unit)
	if not route.is_empty():
		unit.set_route(route, true)


## The way to the end of the bridge, or nothing if already waiting there.
func _route_to_frontier(unit: Unit) -> PackedVector3Array:
	if bridges == null:
		return PackedVector3Array()
	var end := bridges.frontier(corp)
	if end == "" or region.platform_at(unit.position) == end:
		return PackedVector3Array()
	var index := int(unit.get_meta("raid_index", 0)) % 6
	var offsets := SelectionController.formation_offsets_for(6, formation_spacing)
	return _route(unit.position, region.snap_to_walkable(region.get_platform_position(end) + offsets[index]))


## The open route if there is one, otherwise straight through the player's
## buildings (raiders attack whatever blocks them).
func _route(from: Vector3, to: Vector3) -> PackedVector3Array:
	var route := region.find_route(from, to)
	if route.is_empty():
		route = region.find_route(from, to, true)
	return route


func _spawn_point() -> Vector3:
	for hex in region.tiles_of_platform(rival_platform):
		if region.get_tile(hex).type == "spawn":
			return region.hex_center(hex)
	return region.get_platform_position(rival_platform)


## A walkable spot on the target's rim facing the rival, where raiders gather.
func _target_point() -> Vector3:
	var centre := region.get_platform_position(target_platform)
	var toward := (region.get_platform_position(rival_platform) - centre).normalized()
	var radius: float = region.platforms[target_platform].radius
	return region.snap_to_walkable(centre + toward * region.tile_size * 1.5 * (radius - 1))


func _units_root() -> Node3D:
	var root := region.get_parent().get_node_or_null("Units") as Node3D
	return root if root else region
