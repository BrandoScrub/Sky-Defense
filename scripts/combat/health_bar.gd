## A small billboard health bar that floats above anything with hit points.
## Hidden at full health.
class_name HealthBar
extends Node3D

@export var width := 1.4
@export var height := 0.16

var _fill: MeshInstance3D
var _back: MeshInstance3D


func _ready() -> void:
	_back = _quad(Color(0.1, 0.1, 0.1, 0.8), 0.0)
	_fill = _quad(Color(0.3, 0.95, 0.4), 0.01)
	visible = false


## ratio is 0..1. Colour shifts from green to red as health drops.
func set_ratio(ratio: float, enemy := false) -> void:
	ratio = clampf(ratio, 0.0, 1.0)
	visible = ratio < 0.999
	if _fill == null:
		return
	_fill.scale.x = maxf(ratio, 0.001)
	_fill.position.x = -width * (1.0 - ratio) / 2.0
	var full := Color(0.95, 0.35, 0.3) if enemy else Color(0.3, 0.95, 0.4)
	(_fill.material_override as StandardMaterial3D).albedo_color = full.lerp(Color(0.9, 0.2, 0.15), 1.0 - ratio) if not enemy else full


func _quad(color: Color, offset: float) -> MeshInstance3D:
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(width, height)
	quad.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.render_priority = 1 if offset > 0.0 else 0
	mat.albedo_color = color
	quad.material_override = mat
	add_child(quad)
	return quad
