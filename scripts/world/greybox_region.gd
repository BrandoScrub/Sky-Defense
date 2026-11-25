## Builds a gray-box sky region for the prototype: a Hub, neutral platforms,
## a rival HQ, walkways between them and one storm cloud. Real platform scenes
## and the connection graph replace this in milestone 4.
extends Node3D

const PLATFORM_HEIGHT := 2.0
const WALKWAY_WIDTH := 2.5

## name, position on the XZ plane, radius, kind
const PLATFORMS := [
	["Hub", Vector2(0, 0), 12.0, "hub"],
	["NeutralA", Vector2(-30, -22), 8.0, "neutral"],
	["NeutralB", Vector2(28, -26), 8.0, "neutral"],
	["NeutralC", Vector2(-34, 24), 7.0, "neutral"],
	["NeutralD", Vector2(8, -58), 9.0, "neutral"],
	["RivalHQ", Vector2(40, -84), 11.0, "rival"],
]

## Pairs of platform names joined by a walkway.
const WALKWAYS := [
	["Hub", "NeutralA"],
	["Hub", "NeutralB"],
	["Hub", "NeutralC"],
	["NeutralB", "NeutralD"],
	["NeutralD", "RivalHQ"],
]

const STORM_CLOUD := Vector2(-6, -36)

const COLORS := {
	"hub": Color(0.78, 0.6, 0.3),
	"neutral": Color(0.55, 0.55, 0.58),
	"rival": Color(0.6, 0.22, 0.2),
	"walkway": Color(0.4, 0.4, 0.42),
	"storm": Color(0.35, 0.55, 0.95, 0.45),
}

var platforms := {}


func _ready() -> void:
	for p in PLATFORMS:
		_add_platform(p[0], p[1], p[2], p[3])
	for w in WALKWAYS:
		_add_walkway(w[0], w[1])
	_add_storm_cloud(STORM_CLOUD)


func get_platform_position(platform_name: String) -> Vector3:
	var node: Node3D = platforms.get(platform_name)
	return node.global_position if node else Vector3.ZERO


func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled = true
		mat.emission = Color(color.r, color.g, color.b)
		mat.emission_energy_multiplier = 0.6
	return mat


func _add_platform(platform_name: String, at: Vector2, radius: float, kind: String) -> void:
	var platform := CSGCylinder3D.new()
	platform.name = platform_name
	platform.radius = radius
	platform.height = PLATFORM_HEIGHT
	platform.sides = 24
	platform.position = Vector3(at.x, -PLATFORM_HEIGHT / 2.0, at.y)
	platform.material = _material(COLORS[kind])
	platform.use_collision = true
	platform.set_meta("kind", kind)
	platform.set_meta("radius", radius)
	add_child(platform)
	platforms[platform_name] = platform


func _add_walkway(from_name: String, to_name: String) -> void:
	var a: CSGCylinder3D = platforms[from_name]
	var b: CSGCylinder3D = platforms[to_name]
	var a2 := Vector2(a.position.x, a.position.z)
	var b2 := Vector2(b.position.x, b.position.z)
	var dir := (b2 - a2).normalized()
	# Run from rim to rim, overlapping each platform slightly.
	var start := a2 + dir * (a.radius - 1.0)
	var end := b2 - dir * (b.radius - 1.0)
	var walkway := CSGBox3D.new()
	walkway.name = "Walkway_%s_%s" % [from_name, to_name]
	walkway.size = Vector3(WALKWAY_WIDTH, 0.4, start.distance_to(end))
	var mid := (start + end) / 2.0
	walkway.position = Vector3(mid.x, -0.2, mid.y)
	walkway.rotation.y = atan2(dir.x, dir.y)
	walkway.material = _material(COLORS["walkway"])
	walkway.use_collision = true
	add_child(walkway)


func _add_storm_cloud(at: Vector2) -> void:
	var cloud := CSGSphere3D.new()
	cloud.name = "StormCloud"
	cloud.radius = 7.0
	cloud.radial_segments = 16
	cloud.rings = 8
	cloud.scale = Vector3(1.6, 0.6, 1.2)
	cloud.position = Vector3(at.x, 4.0, at.y)
	cloud.material = _material(COLORS["storm"])
	add_child(cloud)
