## A unit that moves along routes and fights. Player units can be selected and
## ordered; rival units are driven by RivalRaids. CombatSystem does the
## targeting and damage.
class_name Unit
extends Node3D

signal arrived
signal died(unit: Unit)

const GROUP := "player_units"
const ENEMY_GROUP := "enemy_units"

@export var display_name := "Riveteer"
@export var is_hero := false
## "player" or "rival". Rival units aren't selectable.
@export var faction := "player"
@export var move_speed := 6.0
## Weight this unit adds to the platform it stands on.
@export var weight := 1
## Set by LoadSystem: below 1 on an overloaded platform.
var speed_multiplier := 1.0
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
## False for bombers, which only attack buildings and headquarters.
@export var targets_units := true

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


func _ready() -> void:
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
	hp -= amount
	_health_bar.set_ratio(hp / max_hp, faction != "player")
	if hp <= 0.0:
		hp = 0.0
		died.emit(self)
		queue_free()


func is_moving() -> bool:
	return not _route.is_empty()


## Follows the given waypoints in order. An empty route stops the unit.
func set_route(route: PackedVector3Array, as_attack_move := false) -> void:
	_route = route
	attack_move = as_attack_move


func stop() -> void:
	_route = PackedVector3Array()


func _process(delta: float) -> void:
	if _route.is_empty() or riding:
		return
	var target := _route[0]
	var to_target := target - position
	to_target.y = 0.0
	var step := move_speed * speed_multiplier * delta
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
	var mat := StandardMaterial3D.new()
	mat.albedo_color = body_color
	mat.roughness = 0.5
	var envelope := MeshInstance3D.new()
	envelope.name = "Body"
	var balloon := CapsuleMesh.new()
	balloon.radius = footprint
	balloon.height = footprint * 4.0
	envelope.mesh = balloon
	envelope.rotation.x = PI / 2.0
	envelope.material_override = mat
	add_child(envelope)
	var gondola := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(footprint * 0.8, footprint * 0.5, footprint * 1.6)
	gondola.mesh = box
	gondola.position.y = -footprint * 1.1
	gondola.material_override = mat
	add_child(gondola)
	var fin := MeshInstance3D.new()
	var fin_box := BoxMesh.new()
	fin_box.size = Vector3(0.1, footprint * 1.2, footprint)
	fin.mesh = fin_box
	fin.position = Vector3(0, footprint * 0.5, -footprint * 1.8)
	fin.material_override = mat
	add_child(fin)
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
