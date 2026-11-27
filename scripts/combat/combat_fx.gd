## Short-lived combat effects: shells in flight, muzzle flashes, impact
## sparks, smoke puffs when something falls, and shadows where bombs will
## land. Purely visual (nothing here changes a fight), and skipped in
## headless runs so sims stay fast.
class_name CombatFx
extends RefCounted

static var _sphere: SphereMesh
static var _disc: CylinderMesh


static func enabled() -> bool:
	return DisplayServer.get_name() != "headless"


static func _material(color: Color, glow := true) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if glow else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	return mat


static func _sphere_mesh() -> SphereMesh:
	if _sphere == null:
		_sphere = SphereMesh.new()
		_sphere.radius = 0.5
		_sphere.height = 1.0
		_sphere.radial_segments = 8
		_sphere.rings = 4
	return _sphere


static func _disc_mesh() -> CylinderMesh:
	if _disc == null:
		_disc = CylinderMesh.new()
		_disc.top_radius = 1.0
		_disc.bottom_radius = 1.0
		_disc.height = 0.04
		_disc.radial_segments = 20
	return _disc


## A glowing shell to move along its flight. `size` is its diameter.
static func shell(parent: Node3D, at: Vector3, color: Color, size := 0.22) -> MeshInstance3D:
	if not enabled():
		return null
	var m := MeshInstance3D.new()
	m.mesh = _sphere_mesh()
	m.material_override = _material(color.lightened(0.3))
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Stretched along its flight (CombatSystem turns it to face the target),
	# so it reads as a streak rather than a dot.
	m.scale = Vector3(size, size, size * 3.5)
	parent.add_child(m)
	m.global_position = at
	return m


## A ball of light that swells and fades: muzzle flashes, impacts, blasts.
static func flash(parent: Node3D, at: Vector3, color: Color, radius := 0.35, seconds := 0.12) -> void:
	if not enabled():
		return
	var m := MeshInstance3D.new()
	m.mesh = _sphere_mesh()
	var mat := _material(color)
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.scale = Vector3.ONE * radius
	parent.add_child(m)
	m.global_position = at
	var tw := m.create_tween().set_parallel(true)
	tw.tween_property(m, "scale", Vector3.ONE * radius * 2.2, seconds)
	tw.tween_property(mat, "albedo_color:a", 0.0, seconds)
	tw.chain().tween_callback(m.queue_free)


## Dark smoke that billows up and thins out, where a unit or ship goes down.
static func puff(parent: Node3D, at: Vector3, size := 1.0, seconds := 0.9) -> void:
	if not enabled():
		return
	for i in 3:
		var m := MeshInstance3D.new()
		m.mesh = _sphere_mesh()
		var mat := _material(Color(0.22, 0.2, 0.19, 0.8).lightened(0.12 * i), false)
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.scale = Vector3.ONE * size * (0.6 + 0.2 * i)
		parent.add_child(m)
		var drift := Vector3(cos(i * 2.1), 0.0, sin(i * 2.1)) * 0.35 * size
		m.global_position = at + drift
		var tw := m.create_tween().set_parallel(true)
		tw.tween_property(m, "scale", Vector3.ONE * size * (1.6 + 0.3 * i), seconds)
		tw.tween_property(m, "global_position", at + drift * 2.0 + Vector3.UP * size * 1.2, seconds)
		tw.tween_property(mat, "albedo_color:a", 0.0, seconds)
		tw.chain().tween_callback(m.queue_free)
	flash(parent, at, Color(1.0, 0.6, 0.25, 0.9), 0.5 * size, 0.2)


## A dark circle on the deck that fills in over `seconds`: where a bomb or
## a falling wreck is about to land.
static func shadow(parent: Node3D, at: Vector3, radius: float, seconds: float) -> void:
	if not enabled():
		return
	var m := MeshInstance3D.new()
	m.mesh = _disc_mesh()
	var mat := _material(Color(0.05, 0.03, 0.02, 0.25))
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.scale = Vector3(radius * 0.4, 1.0, radius * 0.4)
	parent.add_child(m)
	m.global_position = Vector3(at.x, 0.12, at.z)
	var tw := m.create_tween().set_parallel(true)
	tw.tween_property(m, "scale", Vector3(radius, 1.0, radius), seconds)
	tw.tween_property(mat, "albedo_color:a", 0.6, seconds)
	tw.chain().tween_callback(m.queue_free)


## Something dropping from the sky to the deck over `seconds`: a bomb, or
## (with `tumble`) a downed airship's burning hull.
static func falling(parent: Node3D, from: Vector3, to: Vector3, size: float, seconds: float, color: Color, tumble := false) -> void:
	if not enabled():
		return
	var m := MeshInstance3D.new()
	if tumble:
		var box := BoxMesh.new()
		box.size = Vector3(0.7, 0.45, 1.4)
		m.mesh = box
	else:
		m.mesh = _sphere_mesh()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = tumble
	mat.emission = Color(0.9, 0.35, 0.1)
	mat.emission_energy_multiplier = 0.25
	m.material_override = mat
	m.scale = Vector3.ONE * size
	parent.add_child(m)
	m.global_position = from
	var tw := m.create_tween().set_parallel(true)
	tw.tween_property(m, "global_position", to + Vector3.UP * 0.2, seconds).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	if tumble:
		tw.tween_property(m, "rotation", Vector3(1.2, 0.8, 2.2), seconds)
	tw.chain().tween_callback(m.queue_free)
