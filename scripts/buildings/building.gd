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

## 0..1, how well this building is powered (consumers dim in a brownout).
var efficiency := 1.0
## "player" or "rival", from the platform's owner when placed.
var faction := "player"
var hp := 100.0
var max_hp := 100.0
var cooldown_left := 0.0
var _health_bar: HealthBar

var _materials: Array[StandardMaterial3D] = []
var _base_colors: Array[Color] = []


func setup(id: String) -> Building:
	type_id = id
	name = BuildingCatalog.get_data(id).name.replace(" ", "")
	max_hp = BuildingCatalog.get_data(id).get("hp", 100.0)
	hp = max_hp
	_build_shape()
	_health_bar = HealthBar.new()
	_health_bar.position.y = 3.2
	add_child(_health_bar)
	return self


## Attack stats, or an empty dictionary for buildings that don't shoot.
func get_attack() -> Dictionary:
	return get_data().get("attack", {})


func is_alive() -> bool:
	return hp > 0.0 and is_inside_tree()


## Lowers hit points. Returns true if this destroyed the building; the caller
## (CombatSystem) removes it from the region.
func take_damage(amount: float) -> bool:
	if hp <= 0.0:
		return false
	hp -= amount
	_health_bar.set_ratio(hp / max_hp)
	return hp <= 0.0


## Restores hit points, up to the maximum (Sappers do this).
func repair(amount: float) -> void:
	if hp <= 0.0:
		return
	hp = minf(max_hp, hp + amount)
	_health_bar.set_ratio(hp / max_hp)


func get_data() -> Dictionary:
	return BuildingCatalog.get_data(type_id)


## Turns this into a placement preview tinted green (valid) or red (invalid).
func set_ghost(valid: bool) -> void:
	var tint := Color(0.4, 1.0, 0.5, 0.55) if valid else Color(1.0, 0.3, 0.25, 0.55)
	for mat in _materials:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = tint
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


## Dims power-hungry buildings when the grid can't keep up.
func set_efficiency(value: float) -> void:
	if power >= 0 or is_equal_approx(value, efficiency):
		return
	efficiency = value
	var dark := Color(0.15, 0.15, 0.17)
	for i in _materials.size():
		_materials[i].albedo_color = dark.lerp(_base_colors[i], 0.35 + 0.65 * value)


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
		"horn":
			_add(_cylinder(0.5, 0.7, 0.5, 8), Vector3(0, 0.25, 0), Color(0.4, 0.32, 0.25))
			_add(_cylinder(0.12, 0.12, 2.0, 6), Vector3(0, 1.4, 0), Color(0.35, 0.3, 0.28))
			var bell := _add(_cylinder(0.6, 0.12, 1.0, 10), Vector3(0, 2.4, 0.35), color)
			bell.rotation.x = PI / 2.0
		"mender":
			_add(_cylinder(0.75, 0.85, 0.9, 8), Vector3(0, 0.45, 0), Color(0.85, 0.85, 0.8))
			for size in [Vector3(1.1, 0.3, 0.35), Vector3(0.35, 0.3, 1.1)]:
				var cross := BoxMesh.new()
				cross.size = size
				_add(cross, Vector3(0, 1.05, 0), color)
			_add(_cylinder(0.15, 0.15, 0.8, 6), Vector3(0.45, 1.3, -0.3), Color(0.5, 0.5, 0.5))
		"skyhook":
			_add(_cylinder(0.7, 0.85, 0.6, 8), Vector3(0, 0.3, 0), color)
			var cannon := BoxMesh.new()
			cannon.size = Vector3(0.35, 0.35, 2.2)
			var gun := _add(cannon, Vector3(0, 1.3, 0.3), color.darkened(0.35))
			gun.rotation.x = -0.9
			_add(_cylinder(0.22, 0.22, 0.25, 8), Vector3(0, 2.05, 0.95), Color(0.75, 0.7, 0.6))
		"hangar":
			var shed := BoxMesh.new()
			shed.size = Vector3(1.8, 1.0, 1.6)
			_add(shed, Vector3(0, 0.5, 0), color)
			var roof := _add(_cylinder(0.8, 0.8, 1.6, 12), Vector3(0, 1.0, 0), color.darkened(0.25))
			roof.rotation.x = PI / 2.0
			var door := BoxMesh.new()
			door.size = Vector3(1.0, 0.7, 0.05)
			_add(door, Vector3(0, 0.4, 0.82), Color(0.15, 0.14, 0.13))
		"engine":
			# A brass turbine on a stand, propeller facing out.
			_add(_cylinder(0.55, 0.75, 0.5, 8), Vector3(0, 0.25, 0), Color(0.3, 0.28, 0.26))
			var housing := _add(_cylinder(0.55, 0.7, 1.5, 12), Vector3(0, 1.1, 0), color)
			housing.rotation.x = PI / 2.0
			for k in 3:
				var blade := BoxMesh.new()
				blade.size = Vector3(0.18, 1.6, 0.06)
				var part := _add(blade, Vector3(0, 1.1, 0.85), Color(0.2, 0.19, 0.18))
				part.rotation.z = k * TAU / 3.0
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
	_base_colors.append(color)
	add_child(part)
	return part
