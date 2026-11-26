## A unit that moves along routes and fights. Player units can be selected and
## ordered; rival units are driven by RivalRaids. CombatSystem does the
## targeting and damage. UnitCatalog holds the stats for each kind of unit.
##
## Buffs: anything (a banner tower, a spell, a storm) can boost a unit with
##   unit.add_buff("drill_banner", {"damage": 1.25, "armor": 0.8}, 1.0)
## Each value multiplies a stat while the buff lasts; see BUFF_STATS. Adding
## a buff with an id the unit already has refreshes it, so an aura can simply
## re-add a short buff every frame (or use Unit.buff_allies_near). Seconds
## below 0 keep the buff until remove_buff() is called.
class_name Unit
extends Node3D

signal arrived
signal died(unit: Unit)

const GROUP := "player_units"
const ENEMY_GROUP := "enemy_units"
## Units with a longer reach than this fire projectiles, which shields can block.
const MELEE_RANGE := 2.5
## What a buff can change. All are multipliers (1.0 = no change), except
## "regen", which adds hit points per second.
const BUFF_STATS := {
	"damage": "damage dealt",
	"attack_speed": "attacks per second",
	"range": "attack range",
	"speed": "move speed",
	"armor": "damage taken (below 1 is tougher)",
	"healing": "healing and repair done",
	"regen": "hit points regained per second",
}
## Defensive drones from hangars (either faction). They fight like units but
## can't be selected, claim platforms or weigh anything down.
const DRONE_GROUP := "drones"

@export var display_name := "Riveteer"
## UnitCatalog id: riveteer, shieldbearer, rifleman, sapper, lancer, medic, walker.
@export var unit_type := "riveteer"
@export var is_hero := false
## "player" or "rival". Rival units aren't selectable.
@export var faction := "player"
@export var move_speed := 6.0
## Weight this unit adds to the platform it stands on.
@export var weight := 1
## Set by LoadSystem: below 1 on an overloaded platform.
var speed_multiplier := 1.0
## Airships: faster with a tailwind, slower into a headwind (VesperFleet).
var wind_multiplier := 1.0
@export var body_color := Color(0.42, 0.5, 0.6)
## Radius used for click picking and formation spacing.
@export var footprint := 0.6

@export_group("Combat")
@export var max_hp := 60.0
@export var damage := 8.0
@export var attack_range := 4.0
@export var attack_cooldown := 1.0
## Idle or attack-moving units go after enemies this close.
@export var aggro_range := 9.0
## Scrap the player gets for destroying this unit.
@export var bounty := 0
## Aircraft fly over the map; only anti-air weapons can hit them.
@export var flying := false
## Can this unit shoot aircraft?
@export var hits_air := false
## Air-to-air ships: shoots only aircraft and airships.
@export var air_only := false
## False for bombers, which only attack buildings and headquarters.
@export var targets_units := true
## Armored units take extra damage from anti-armor weapons (vs_armor).
@export var armored := false
## Share of a projectile's damage this unit's shield stops, 0 to 1. Shields
## also catch enemy shots flying past toward allies behind them.
@export var shield := 0.0
## Damage multiplier against armored units.
@export var vs_armor := 1.0
## Damage multiplier against buildings and headquarters.
@export var vs_buildings := 1.0
## Hit points per second healed on one wounded ally in range (medics).
@export var heal_power := 0.0
## Hit points per second repaired on one damaged friendly building (sappers).
@export var repair_power := 0.0
## Launched from a Drone Hangar; DefenseSystem flies it.
@export var is_drone := false

## Bonuses from nearby support buildings (see DefenseSystem). They work on
## any unit type, so new units get them for free. Reset every frame.
## Multiplies damage dealt.
var damage_mult := 1.0
## Multiplies time between shots (below 1 = faster).
var cooldown_mult := 1.0
## Fraction of incoming damage blocked, 0..0.9.
var armor := 0.0

var hp := 60.0
var cooldown_left := 0.0
var _health_bar: HealthBar

var selected := false:
	set(value):
		selected = value
		if _ring:
			_ring.visible = value
## True when the current order was an attack-move (used once enemies exist).
var attack_move := false
## True while aboard an airship ferry: FerrySystem moves the unit and it
## neither walks nor fights.
var riding := false

var _route := PackedVector3Array()
var _ring: MeshInstance3D
## Buff id -> {"mods": Dictionary, "time_left": float}.
var _buffs := {}


func _ready() -> void:
	if is_drone:
		add_to_group(DRONE_GROUP)
	else:
		add_to_group(GROUP if faction == "player" else ENEMY_GROUP)
	hp = max_hp
	_build_visuals()
	_health_bar = HealthBar.new()
	_health_bar.position.y = 2.9 if is_hero else 2.3
	add_child(_health_bar)


func is_alive() -> bool:
	return hp > 0.0 and is_inside_tree()


func take_damage(amount: float) -> void:
	if hp <= 0.0:
		return
	hp -= amount * (1.0 - clampf(armor, 0.0, 0.9)) * buff_multiplier("armor")
	_health_bar.set_ratio(hp / max_hp, faction != "player")
	if hp <= 0.0:
		hp = 0.0
		died.emit(self)
		queue_free()


## Restores hit points, up to the maximum. Returns how much was healed.
func heal(amount: float) -> float:
	if hp <= 0.0 or amount <= 0.0:
		return 0.0
	var before := hp
	hp = minf(max_hp, hp + amount)
	if _health_bar:
		_health_bar.set_ratio(hp / max_hp, faction != "player")
	return hp - before


## True for units that shoot from range (their shots can be blocked by shields).
func is_ranged() -> bool:
	return attack_range > MELEE_RANGE


## Damage per hit after buffs and support bonuses.
func get_damage() -> float:
	return damage * damage_mult * buff_multiplier("damage")


## Attack range after buffs.
func get_attack_range() -> float:
	return attack_range * buff_multiplier("range")


## Seconds between attacks after buffs and support bonuses.
func get_attack_cooldown() -> float:
	return attack_cooldown * cooldown_mult / maxf(buff_multiplier("attack_speed"), 0.05)


# --- Buffs -------------------------------------------------------------------

## Adds or refreshes a buff. `mods` maps BUFF_STATS keys to values, for
## example {"damage": 1.2}. Lasts `seconds`, or until removed if below 0.
func add_buff(id: String, mods: Dictionary, seconds := -1.0) -> void:
	_buffs[id] = {"mods": mods, "time_left": seconds}


func remove_buff(id: String) -> void:
	_buffs.erase(id)


func has_buff(id: String) -> bool:
	return _buffs.has(id)


## Ids of the buffs on this unit.
func buff_ids() -> Array:
	return _buffs.keys()


## The combined multiplier for a stat from every buff (1.0 with none).
## For "regen" it is the summed bonus instead.
func buff_multiplier(stat: String) -> float:
	var total := 0.0 if stat == "regen" else 1.0
	for buff in _buffs.values():
		if buff.mods.has(stat):
			if stat == "regen":
				total += float(buff.mods[stat])
			else:
				total *= float(buff.mods[stat])
	return total


## Counts buffs down, drops expired ones and applies regen. Called every frame.
func tick_buffs(delta: float) -> void:
	if _buffs.is_empty():
		return
	for id in _buffs.keys():
		var buff: Dictionary = _buffs[id]
		if buff.time_left >= 0.0:
			buff.time_left -= delta
			if buff.time_left < 0.0:
				_buffs.erase(id)
	var regen := buff_multiplier("regen")
	if regen > 0.0:
		heal(regen * delta)


## Gives every living ground unit of `faction` within `radius` of `center` a
## buff for `seconds`. Handy for aura buildings: call it every frame (or every
## few frames) with a short duration and the buff fades soon after a unit
## walks away or the building is destroyed. Returns how many units it reached.
static func buff_allies_near(tree_node: Node, center: Vector3, radius: float, faction: String, id: String, mods: Dictionary, seconds := 0.5) -> int:
	var count := 0
	var group := GROUP if faction == "player" else ENEMY_GROUP
	for node in tree_node.get_tree().get_nodes_in_group(group):
		var u := node as Unit
		if u == null or not u.is_alive() or u.flying:
			continue
		if Vector2(u.global_position.x - center.x, u.global_position.z - center.z).length() <= radius:
			u.add_buff(id, mods, seconds)
			count += 1
	return count


## Clears support bonuses back to normal.
func reset_support() -> void:
	damage_mult = 1.0
	cooldown_mult = 1.0
	armor = 0.0


func is_moving() -> bool:
	return not _route.is_empty()


## Follows the given waypoints in order. An empty route stops the unit.
func set_route(route: PackedVector3Array, as_attack_move := false) -> void:
	_route = route
	attack_move = as_attack_move


## The point the unit is heading for now, or where it stands.
func next_waypoint() -> Vector3:
	return _route[0] if not _route.is_empty() else position


func stop() -> void:
	_route = PackedVector3Array()


func _process(delta: float) -> void:
	tick_buffs(delta)
	if _route.is_empty() or riding:
		return
	var target := _route[0]
	var to_target := target - position
	to_target.y = 0.0
	var step := move_speed * speed_multiplier * wind_multiplier * buff_multiplier("speed") * delta
	if to_target.length() <= step:
		position = Vector3(target.x, position.y, target.z)
		_route.remove_at(0)
		if _route.is_empty():
			attack_move = false
			arrived.emit()
		return
	var dir := to_target.normalized()
	position += dir * step
	rotation.y = atan2(dir.x, dir.z)


func _build_visuals() -> void:
	if flying:
		_build_aircraft()
		return
	if unit_type == "walker":
		_build_walker()
		return
	var height := 2.2 if is_hero else 1.6
	var radius := footprint * (1.0 if is_hero else 0.8)

	var body := MeshInstance3D.new()
	body.name = "Body"
	var capsule := CapsuleMesh.new()
	capsule.radius = radius
	capsule.height = height
	body.mesh = capsule
	body.position.y = height / 2.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = body_color
	mat.metallic = 0.6
	mat.roughness = 0.4
	body.material_override = mat
	add_child(body)

	# A small block on the front so facing is readable from above.
	var nose := MeshInstance3D.new()
	nose.name = "Facing"
	var box := BoxMesh.new()
	box.size = Vector3(radius * 0.6, radius * 0.4, radius * 0.6)
	nose.mesh = box
	nose.position = Vector3(0.0, height * 0.7, radius)
	nose.material_override = mat
	add_child(nose)

	_add_gear(height, radius)

	_ring = MeshInstance3D.new()
	_ring.name = "SelectionRing"
	var torus := TorusMesh.new()
	torus.inner_radius = radius + 0.25
	torus.outer_radius = radius + 0.45
	_ring.mesh = torus
	_ring.position.y = 0.05
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.4, 1.0, 0.55)
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring.material_override = ring_mat
	_ring.visible = selected
	add_child(_ring)


## Placeholder bomber airship, plus a shadow on the deck below so it's easy to
## see where it is from the top-down camera.
func _build_aircraft() -> void:
	var f := footprint
	var mat := StandardMaterial3D.new()
	mat.albedo_color = body_color
	mat.roughness = 0.65
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.78, 0.58, 0.3)
	brass.metallic = 0.8
	brass.roughness = 0.35
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.2, 0.19, 0.19)
	iron.metallic = 0.6
	iron.roughness = 0.5
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color(1.0, 0.78, 0.4)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.7, 0.35)
	lamp.emission_energy_multiplier = 2.5
	# The gas envelope: a long cigar with brass hoops around it.
	var envelope := MeshInstance3D.new()
	envelope.name = "Body"
	var balloon := SphereMesh.new()
	balloon.radius = f
	balloon.height = f * 2.0
	balloon.radial_segments = 20
	balloon.rings = 10
	envelope.mesh = balloon
	envelope.scale = Vector3(1.0, 1.0, 2.2)
	envelope.material_override = mat
	add_child(envelope)
	for z in [-1.2, -0.4, 0.4, 1.2]:
		var hoop := MeshInstance3D.new()
		var torus := TorusMesh.new()
		var r := f * sqrt(maxf(0.05, 1.0 - pow(z / 2.2, 2.0)))
		torus.inner_radius = r * 0.98
		torus.outer_radius = r * 1.05
		torus.rings = 20
		hoop.mesh = torus
		hoop.rotation.x = PI / 2.0
		hoop.position.z = z * f
		hoop.material_override = brass
		add_child(hoop)
	# Gondola slung underneath, with lit windows down each side.
	var gondola := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(f * 0.7, f * 0.45, f * 1.8)
	gondola.mesh = box
	gondola.position.y = -f * 1.15
	gondola.material_override = iron
	add_child(gondola)
	for side in [-1.0, 1.0]:
		var windows := MeshInstance3D.new()
		var strip := BoxMesh.new()
		strip.size = Vector3(0.02, f * 0.12, f * 1.4)
		windows.mesh = strip
		windows.position = Vector3(side * f * 0.36, -f * 1.1, 0.0)
		windows.material_override = lamp
		add_child(windows)
		# Struts down to the gondola.
		var strut := MeshInstance3D.new()
		strut.mesh = _cyl(0.03, 0.03, f * 0.5)
		strut.position = Vector3(side * f * 0.3, -f * 0.85, 0.0)
		strut.material_override = brass
		add_child(strut)
		# An outrigger engine with a spinning propeller.
		var pod := MeshInstance3D.new()
		pod.mesh = _cyl(f * 0.14, f * 0.18, f * 0.6)
		pod.rotation.x = PI / 2.0
		pod.position = Vector3(side * f * 0.85, -f * 0.75, -f * 0.5)
		pod.material_override = brass
		add_child(pod)
		var arm := MeshInstance3D.new()
		var arm_box := BoxMesh.new()
		arm_box.size = Vector3(f * 0.5, 0.05, 0.08)
		arm.mesh = arm_box
		arm.position = Vector3(side * f * 0.55, -f * 0.85, -f * 0.5)
		arm.material_override = iron
		add_child(arm)
		var prop := MeshInstance3D.new()
		var blade := BoxMesh.new()
		blade.size = Vector3(f * 0.7, f * 0.08, 0.03)
		prop.mesh = blade
		prop.position = Vector3(side * f * 0.85, -f * 0.75, -f * 0.82)
		prop.material_override = iron
		add_child(prop)
		var spin := prop.create_tween().set_loops()
		spin.tween_property(prop, "rotation:z", TAU * side, 0.3).from(0.0)
	# Cruciform tail fins.
	for i in 4:
		var fin := MeshInstance3D.new()
		var fin_box := BoxMesh.new()
		fin_box.size = Vector3(0.06, f * 0.9, f * 0.8)
		fin.mesh = fin_box
		fin.rotation.z = i * PI / 2.0
		fin.position = Vector3(0, f * 0.55, 0).rotated(Vector3.BACK, i * PI / 2.0) + Vector3(0, 0, -f * 1.8)
		fin.material_override = mat if i % 2 == 0 else brass
		add_child(fin)
	# A brass nose cap and a running lamp.
	var nose := MeshInstance3D.new()
	var cap := SphereMesh.new()
	cap.radius = f * 0.22
	cap.height = f * 0.44
	nose.mesh = cap
	nose.position.z = f * 2.15
	nose.material_override = brass
	add_child(nose)
	var light := MeshInstance3D.new()
	var bulb := SphereMesh.new()
	bulb.radius = f * 0.1
	bulb.height = f * 0.2
	light.mesh = bulb
	light.position = Vector3(0, -f * 1.4, f * 0.8)
	light.material_override = lamp
	add_child(light)
	var shadow := MeshInstance3D.new()
	shadow.name = "Shadow"
	var disc := CylinderMesh.new()
	disc.top_radius = footprint * 1.4
	disc.bottom_radius = footprint * 1.4
	disc.height = 0.02
	shadow.mesh = disc
	var shadow_mat := StandardMaterial3D.new()
	shadow_mat.albedo_color = Color(0, 0, 0, 0.35)
	shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow.material_override = shadow_mat
	shadow.position.y = -position.y + 0.08
	add_child(shadow)


## Helmet, pack and rifle for player units; a top hat for the Commander.
func _add_gear(height: float, radius: float) -> void:
	var brass := _plain(Color(0.78, 0.6, 0.3))
	var leather := _plain(Color(0.35, 0.24, 0.16))
	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius * 0.7
	sphere.height = radius * 1.4
	head.mesh = sphere
	head.position.y = height + radius * 0.45
	head.material_override = _plain(Color(0.85, 0.7, 0.55))
	add_child(head)
	if is_hero:
		var brim := MeshInstance3D.new()
		brim.mesh = _cyl(radius * 1.1, radius * 1.1, 0.06)
		brim.position.y = height + radius * 0.85
		brim.material_override = _plain(Color(0.12, 0.1, 0.1))
		add_child(brim)
		var hat := MeshInstance3D.new()
		hat.mesh = _cyl(radius * 0.6, radius * 0.65, radius * 1.1)
		hat.position.y = height + radius * 1.4
		hat.material_override = brim.material_override
		add_child(hat)
	else:
		var helmet := MeshInstance3D.new()
		var dome := SphereMesh.new()
		dome.radius = radius * 0.78
		dome.height = radius * 0.9
		dome.is_hemisphere = true
		helmet.mesh = dome
		helmet.position.y = height + radius * 0.55
		helmet.material_override = brass
		add_child(helmet)
	var pack := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(radius * 1.2, height * 0.4, radius * 0.6)
	pack.mesh = box
	pack.position = Vector3(0, height * 0.6, -radius * 0.9)
	pack.material_override = leather
	add_child(pack)
	_add_weapon(height, radius, brass)


## The kit that tells unit types apart from above: a weapon, plus a shield,
## satchel or medic's cross.
func _add_weapon(height: float, radius: float, brass: StandardMaterial3D) -> void:
	var gunmetal := _plain(Color(0.2, 0.2, 0.22))
	match unit_type if not is_hero else "hero":
		"shieldbearer":
			# A tall riveted tower shield in front, and a short baton.
			_box(Vector3(radius * 2.4, height * 0.85, 0.12), Vector3(0, height * 0.5, radius + 0.25), _plain(Color(0.5, 0.52, 0.56)))
			_box(Vector3(radius * 1.6, 0.1, 0.14), Vector3(0, height * 0.75, radius + 0.33), brass)
			_box(Vector3(0.1, 0.1, radius * 1.2), Vector3(radius * 0.9, height * 0.5, radius * 0.4), gunmetal)
		"rifleman":
			# A long bolt gun with a brass scope.
			_box(Vector3(0.09, 0.09, radius * 3.6), Vector3(radius * 0.8, height * 0.6, radius * 1.1), gunmetal)
			_box(Vector3(0.12, 0.12, radius * 0.9), Vector3(radius * 0.8, height * 0.6 + 0.12, radius * 0.7), brass)
		"sapper":
			# A big wrench and a satchel of charges on the hip.
			_box(Vector3(0.12, 0.12, radius * 1.8), Vector3(radius * 0.85, height * 0.5, radius * 0.6), brass)
			_box(Vector3(0.3, 0.1, 0.12), Vector3(radius * 0.85, height * 0.5, radius * 1.5), brass)
			_box(Vector3(radius * 0.7, radius * 0.6, radius * 0.5), Vector3(-radius * 0.95, height * 0.35, 0), _plain(Color(0.6, 0.2, 0.15)))
		"lancer":
			# A heavy arc lance with a glowing tip.
			_box(Vector3(0.16, 0.16, radius * 4.0), Vector3(radius * 0.8, height * 0.6, radius * 1.2), gunmetal)
			var tip := _plain(Color(0.5, 0.8, 1.0))
			tip.emission_enabled = true
			tip.emission = Color(0.5, 0.8, 1.0)
			_box(Vector3(0.24, 0.24, 0.24), Vector3(radius * 0.8, height * 0.6, radius * 3.2), tip)
		"medic":
			# A white satchel with a red cross on the back, and a tonic sprayer.
			_box(Vector3(radius * 0.9, 0.08, radius * 0.25), Vector3(0, height * 0.6 + 0.05, -radius * 1.25), _plain(Color(0.85, 0.15, 0.15)))
			_box(Vector3(radius * 0.25, 0.08, radius * 0.9), Vector3(0, height * 0.6 + 0.05, -radius * 1.25), _plain(Color(0.85, 0.15, 0.15)))
			_box(Vector3(0.08, 0.08, radius * 1.0), Vector3(radius * 0.8, height * 0.55, radius * 0.5), brass)
		_:
			_box(Vector3(0.1, 0.1, radius * 2.4), Vector3(radius * 0.8, height * 0.55, radius * 0.7), gunmetal)


func _box(size: Vector3, at: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	part.position = at
	part.material_override = mat
	add_child(part)
	return part


## Ironbell walker: a boxy riveted body on two stubby legs with a smokestack.
func _build_walker() -> void:
	var iron := _plain(body_color)
	var dark := _plain(body_color.darkened(0.5))
	var torso := MeshInstance3D.new()
	torso.name = "Body"
	var box := BoxMesh.new()
	box.size = Vector3(1.2, 1.0, 1.0)
	torso.mesh = box
	torso.position.y = 1.5
	torso.material_override = iron
	add_child(torso)
	for x in [-0.35, 0.35]:
		var leg := MeshInstance3D.new()
		var leg_box := BoxMesh.new()
		leg_box.size = Vector3(0.3, 1.0, 0.4)
		leg.mesh = leg_box
		leg.position = Vector3(x, 0.5, 0)
		leg.material_override = dark
		add_child(leg)
	var stack := MeshInstance3D.new()
	stack.mesh = _cyl(0.15, 0.18, 0.8)
	stack.position = Vector3(-0.3, 2.3, -0.25)
	stack.material_override = dark
	add_child(stack)
	var eye := MeshInstance3D.new()
	var lens := SphereMesh.new()
	lens.radius = 0.15
	lens.height = 0.3
	eye.mesh = lens
	eye.position = Vector3(0, 1.65, 0.5)
	var glow := _plain(Color(1.0, 0.45, 0.2))
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.45, 0.2)
	eye.material_override = glow
	add_child(eye)
	var gun := MeshInstance3D.new()
	var barrel := BoxMesh.new()
	barrel.size = Vector3(0.18, 0.18, 0.9)
	gun.mesh = barrel
	gun.position = Vector3(0.7, 1.4, 0.4)
	gun.material_override = dark
	add_child(gun)


func _plain(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.6
	return mat


func _cyl(top: float, bottom: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 10
	return mesh
