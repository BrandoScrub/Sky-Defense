## A placed building, or the see-through ghost shown while placing one.
## Placeholder shapes only; combat and power effects come in later milestones.
class_name Building
extends Node3D

const SIZE := 2.0
## Models are drawn a little larger than modelled so they fill their tile.
const MODEL_SCALE := 1.2

var type_id := ""
var hex := Vector2i.ZERO
var platform := ""
## Power this building gives (+) or takes (-) where it stands.
var power := 0

## 0..1, how well this building is powered (consumers dim in a brownout).
var efficiency := 1.0
## "player" or "rival", from the platform's owner when placed. A rival's
## buildings are rebuilt in its colours.
var faction := "player":
	set(value):
		if value == faction:
			return
		faction = value
		if _model:
			_build_shape()
var hp := 100.0
var max_hp := 100.0
var cooldown_left := 0.0
var _health_bar: HealthBar

## Shown over a power-hungry building that the grid can't keep up with.
var _power_warning: Label3D
## The parts of the model (see BuildingModels); rebuilt if the side changes.
var _model: Node3D
var _materials: Array[StandardMaterial3D] = []
var _base_colors: Array[Color] = []
var _base_glow: Array[float] = []


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


## Turns the gun's head (the model's "Head" part, if it has one) to face
## `point`. It swings round over a few frames (see _process).
func aim_at(point: Vector3) -> void:
	var head := _head()
	if head == null:
		return
	var d := point - global_position
	if Vector2(d.x, d.z).length() < 0.01:
		return
	_aim_yaw = atan2(d.x, d.z) - global_rotation.y
	set_process(true)


## How fast a gun head swings round, in radians per second.
const TRAVERSE_SPEED := 7.0
var _aim_yaw := 0.0


func _process(delta: float) -> void:
	var head := _head()
	if head == null:
		set_process(false)
		return
	var diff := wrapf(_aim_yaw - head.rotation.y, -PI, PI)
	var turn := TRAVERSE_SPEED * delta
	if absf(diff) <= turn:
		head.rotation.y = _aim_yaw
		set_process(false)
	else:
		head.rotation.y += signf(diff) * turn


func _head() -> Node3D:
	return _model.get_node_or_null("Head") if _model else null


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
		mat.emission_enabled = false
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


## Dims power-hungry buildings when the grid can't keep up.
func set_efficiency(value: float) -> void:
	if power >= 0 or is_equal_approx(value, efficiency):
		return
	efficiency = value
	var dark := Color(0.15, 0.15, 0.17)
	for i in _materials.size():
		_materials[i].albedo_color = dark.lerp(_base_colors[i], 0.35 + 0.65 * value)
		# Lamps and live parts go out with the power.
		_materials[i].emission_energy_multiplier = _base_glow[i] * value
	_update_power_warning()


## A floating "NO POWER" / "LOW POWER" sign while the grid can't keep up, so
## an unpowered tower doesn't just quietly fire at a crawl.
func _update_power_warning() -> void:
	var text := ""
	if faction != "player":
		pass
	elif efficiency < 0.25:
		text = "NO POWER"
	elif efficiency < 0.75:
		text = "LOW POWER"
	if text == "":
		if _power_warning:
			_power_warning.visible = false
		return
	if _power_warning == null:
		_power_warning = Label3D.new()
		_power_warning.name = "PowerWarning"
		_power_warning.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_power_warning.no_depth_test = true
		_power_warning.font_size = 40
		_power_warning.outline_size = 10
		_power_warning.modulate = Color(1.0, 0.75, 0.2)
		_power_warning.position.y = 4.0
		add_child(_power_warning)
	_power_warning.text = text
	_power_warning.visible = true


## The warning text over this building, or "" when it has enough power.
func power_warning() -> String:
	return _power_warning.text if _power_warning and _power_warning.visible else ""


## Builds the model from the shared parts kit, in this side's colours.
func _build_shape() -> void:
	if _model:
		remove_child(_model)
		_model.queue_free()
	var data := get_data()
	var kit := ModelKit.new(data.color, faction)
	_model = Node3D.new()
	_model.name = "Model"
	_model.scale = Vector3.ONE * MODEL_SCALE
	add_child(_model)
	BuildingModels.build(_model, data.shape, kit)
	_materials = kit.materials()
	_base_colors.clear()
	_base_glow.clear()
	for mat in _materials:
		_base_colors.append(mat.albedo_color)
		_base_glow.append(mat.emission_energy_multiplier if mat.emission_enabled else 0.0)
	# A rebuilt model starts fully lit: dim it again if the grid is short.
	var was := efficiency
	efficiency = 1.0
	set_efficiency(was)
