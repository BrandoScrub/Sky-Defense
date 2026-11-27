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
## Launched from an Airship Hangar; DefenseSystem flies it.
@export var is_drone := false
## Aircraft hull: "light" (drones, interceptors, gunships, tenders) or
## "heavy" (bombers, troop carriers, gunboats); "" for ground units. Flak
## shreds light craft, the Skyhook harpoon is made for heavy hulls, and only
## a heavy hull crashes hard enough to hurt what's under it.
@export var hull := ""
## Heavy hitters (Lancers, walkers) stagger what they hit: a short shove
## back and a pause before its next attack. A Shieldbearer facing the hit
## braces and doesn't budge.
@export var heavy_hits := false
## How fast this unit's shots fly (units per second). Slower shells are
## easier to see; the hit lands when the shell arrives.
@export var shell_speed := 50.0

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
## Knockback slide: where the unit is being shoved to, and time left.
var _knock_to := Vector3.ZERO
var _knock_left := 0.0
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


## The way the unit faces, flat on the deck.
func forward() -> Vector3:
	return Vector3(sin(rotation.y), 0.0, cos(rotation.y))


## Turns the unit to face a point (it fights facing its target, which is
## what a Shieldbearer's shield covers).
func face(point: Vector3) -> void:
	var to := point - global_position
	to.y = 0.0
	if to.length() > 0.01:
		rotation.y = atan2(to.x, to.z)


## True when `point` is in front of the unit, within `arc_cos` (the cosine
## of half the arc: 0.5 is a 120 degree front).
func is_facing(point: Vector3, arc_cos := 0.5) -> bool:
	var to := point - global_position
	to.y = 0.0
	if to.length() < 0.01:
		return true
	return to.normalized().dot(forward()) >= arc_cos


## Shoves the unit to `to` over a moment and holds off its next attack for
## `seconds`. CombatSystem checks the spot is walkable first.
func stagger(to: Vector3, seconds: float) -> void:
	cooldown_left = maxf(cooldown_left, seconds)
	if to != global_position:
		_knock_to = Vector3(to.x, position.y, to.z)
		_knock_left = 0.15


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
	if _knock_left > 0.0:
		var t := minf(delta / _knock_left, 1.0)
		_knock_left -= delta
		position = position.lerp(_knock_to, t)
		return
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


## Builds the model (see UnitModels) and, for troops, the selection ring.
func _build_visuals() -> void:
	UnitModels.build(self)
	if flying or unit_type == "walker":
		return
	var radius := footprint * (1.0 if is_hero else 0.8)
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
