## A player unit that can be selected and ordered to move along a route.
## Combat, health and stances arrive in later milestones.
class_name Unit
extends Node3D

signal arrived

const GROUP := "player_units"
const ENEMY_GROUP := "enemy_units"

@export var display_name := "Riveteer"
@export var is_hero := false
## "player" or "rival". Rival units aren't selectable.
@export var faction := "player"
@export var move_speed := 6.0
@export var body_color := Color(0.42, 0.5, 0.6)
## Radius used for click picking and formation spacing.
@export var footprint := 0.6

var selected := false:
	set(value):
		selected = value
		if _ring:
			_ring.visible = value
## True when the current order was an attack-move (used once enemies exist).
var attack_move := false

var _route := PackedVector3Array()
var _ring: MeshInstance3D


func _ready() -> void:
	add_to_group(GROUP if faction == "player" else ENEMY_GROUP)
	_build_visuals()


func is_moving() -> bool:
	return not _route.is_empty()


## Follows the given waypoints in order. An empty route stops the unit.
func set_route(route: PackedVector3Array, as_attack_move := false) -> void:
	_route = route
	attack_move = as_attack_move


func stop() -> void:
	_route = PackedVector3Array()


func _process(delta: float) -> void:
	if _route.is_empty():
		return
	var target := _route[0]
	var to_target := target - position
	to_target.y = 0.0
	var step := move_speed * delta
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
