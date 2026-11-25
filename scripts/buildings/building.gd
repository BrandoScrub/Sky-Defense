## A placed building, or the see-through ghost shown while placing one.
## Placeholder shapes only; combat and power effects come in later milestones.
class_name Building
extends Node3D

const SIZE := 2.0

var type_id := ""
var hex := Vector2i.ZERO
var platform := ""
## Power this building gives (+) or takes (-) where it stands.
var power := 0

var _materials: Array[StandardMaterial3D] = []


func setup(id: String) -> Building:
	type_id = id
	name = BuildingCatalog.get_data(id).name.replace(" ", "")
	_build_shape()
	return self


func get_data() -> Dictionary:
	return BuildingCatalog.get_data(type_id)


## Turns this into a placement preview tinted green (valid) or red (invalid).
func set_ghost(valid: bool) -> void:
	var tint := Color(0.4, 1.0, 0.5, 0.55) if valid else Color(1.0, 0.3, 0.25, 0.55)
	for mat in _materials:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = tint
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


func _build_shape() -> void:
	var data := get_data()
	var color: Color = data.color
	match data.shape:
		"generator":
			_add(_cylinder(0.8, 0.9, 1.4, 12), Vector3(0, 0.7, 0), color)
			_add(_cylinder(0.25, 0.25, 1.2, 8), Vector3(0.4, 1.8, 0), Color(0.3, 0.28, 0.26))
		"harvester":
			_add(_cylinder(0.15, 0.2, 3.5, 6), Vector3(0, 1.75, 0), Color(0.5, 0.45, 0.4))
			var balloon := SphereMesh.new()
			balloon.radius = 0.9
			balloon.height = 1.4
			_add(balloon, Vector3(0, 4.0, 0), color)
		"turret":
			_add(_cylinder(0.7, 0.8, 0.6, 6), Vector3(0, 0.3, 0), color)
			var barrel := BoxMesh.new()
			barrel.size = Vector3(0.25, 0.25, 1.4)
			_add(barrel, Vector3(0, 0.85, 0.5), color.darkened(0.3))
		"flak":
			_add(_cylinder(0.8, 0.9, 0.5, 8), Vector3(0, 0.25, 0), color)
			for x in [-0.3, 0.3]:
				var gun := BoxMesh.new()
				gun.size = Vector3(0.2, 1.2, 0.2)
				var part := _add(gun, Vector3(x, 1.0, 0.1), color.darkened(0.3))
				part.rotation.x = -0.5
		"coil":
			_add(_cylinder(0.35, 0.6, 2.4, 8), Vector3(0, 1.2, 0), Color(0.55, 0.4, 0.25))
			var top := TorusMesh.new()
			top.inner_radius = 0.4
			top.outer_radius = 0.8
			_add(top, Vector3(0, 2.5, 0), color)


func _cylinder(top: float, bottom: float, height: float, sides: int) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = sides
	return mesh


func _add(mesh: Mesh, at: Vector3, color: Color) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = at
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.6
	mat.metallic = 0.4
	part.material_override = mat
	_materials.append(mat)
	add_child(part)
	return part
