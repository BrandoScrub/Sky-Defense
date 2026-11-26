## The stormy world under the sky city: layers of drifting cloud far below
## the platforms, with lightning that flickers through them now and then.
## Purely decoration; it doesn't affect play.
class_name SkyBackdrop
extends Node3D

const SHADER := preload("res://shaders/cloud_sea.gdshader")
const PUFF_SHADER := preload("res://shaders/cloud_puff.gdshader")

## Area the cloud sea covers, in world units (it's centred on the region).
@export var area := Rect2(-150, -170, 300, 300)
## Seconds between lightning flashes (random within this range).
@export var flash_interval := Vector2(2.5, 7.0)

## Each layer: depth below the deck, density, opacity, scroll speed, colours.
const LAYERS := [
	{"y": -38.0, "density": 1.0, "opacity": 1.0, "scroll": Vector2(0.002, 0.001),
		"dark": Color(0.05, 0.06, 0.12), "light": Color(0.17, 0.2, 0.32), "sun": 0.2},
	{"y": -26.0, "density": 0.7, "opacity": 0.95, "scroll": Vector2(0.005, 0.002),
		"dark": Color(0.11, 0.13, 0.22), "light": Color(0.36, 0.4, 0.55), "sun": 0.4},
	{"y": -16.0, "density": 0.45, "opacity": 0.85, "scroll": Vector2(0.009, 0.004),
		"dark": Color(0.2, 0.22, 0.34), "light": Color(0.58, 0.6, 0.72), "sun": 0.65},
]

var rng := RandomNumberGenerator.new()
var _materials: Array[ShaderMaterial] = []
var _flash := 0.0
var _flash_timer := 3.0
var _flicker_left := 0
var _light: OmniLight3D


func _ready() -> void:
	rng.seed = 77
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = noise
	tex.generate_mipmaps = true

	for layer in LAYERS:
		var plane := MeshInstance3D.new()
		plane.name = "CloudLayer%d" % _materials.size()
		var mesh := PlaneMesh.new()
		mesh.size = area.size
		plane.mesh = mesh
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		mat.set_shader_parameter("noise_tex", tex)
		mat.set_shader_parameter("density", layer.density)
		mat.set_shader_parameter("opacity", layer.opacity)
		mat.set_shader_parameter("scroll", layer.scroll)
		mat.set_shader_parameter("dark_color", layer.dark)
		mat.set_shader_parameter("light_color", layer.light)
		mat.set_shader_parameter("sun_strength", layer.sun)
		mat.render_priority = _materials.size()
		plane.material_override = mat
		plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		plane.position = Vector3(area.get_center().x, layer.y, area.get_center().y)
		add_child(plane)
		_materials.append(mat)

	_add_storm_towers()

	_light = OmniLight3D.new()
	_light.name = "Lightning"
	_light.light_color = Color(0.75, 0.82, 1.0)
	_light.omni_range = 45.0
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	add_child(_light)


func _process(delta: float) -> void:
	_flash_timer -= delta
	if _flash_timer <= 0.0:
		strike()
	_flash = maxf(0.0, _flash - delta * 4.0)
	if _flash <= 0.05 and _flicker_left > 0:
		_flicker_left -= 1
		_flash = rng.randf_range(0.5, 0.9)
	_apply_flash()


## Flashes lightning somewhere in the cloud sea (public for screenshots).
func strike(at = null) -> void:
	_flash_timer = rng.randf_range(flash_interval.x, flash_interval.y)
	var pos: Vector3
	if at is Vector3:
		pos = at
	else:
		pos = Vector3(rng.randf_range(area.position.x, area.end.x) * 0.6, -22.0,
			rng.randf_range(area.position.y, area.end.y) * 0.6 + area.get_center().y * 0.4)
	_light.position = pos
	_flash = 1.0
	_flicker_left = rng.randi_range(0, 2)
	for mat in _materials:
		mat.set_shader_parameter("flash_pos", pos)
	_apply_flash()


func _apply_flash() -> void:
	for mat in _materials:
		mat.set_shader_parameter("flash", _flash)
	if _light:
		_light.light_energy = _flash * 6.0


## Billowing columns of storm cloud rising from the sea between platforms.
func _add_storm_towers() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = PUFF_SHADER
	var root := Node3D.new()
	root.name = "StormTowers"
	add_child(root)
	for i in 26:
		var base := Vector3(rng.randf_range(area.position.x, area.end.x), -24.0,
			rng.randf_range(area.position.y, area.end.y))
		var puffs := rng.randi_range(3, 6)
		for j in puffs:
			var puff := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			var r := rng.randf_range(4.0, 9.0) * (1.0 - j * 0.12)
			sphere.radius = r
			sphere.height = r * 1.5
			sphere.radial_segments = 24
			sphere.rings = 12
			puff.mesh = sphere
			puff.material_override = mat
			puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			puff.position = base + Vector3(rng.randf_range(-4, 4), minf(j * r * 0.7, 8.0), rng.randf_range(-4, 4))
			root.add_child(puff)
