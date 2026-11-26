## The shared parts kit every model in the game is built from, so buildings,
## troops, airships and headquarters all look like they came out of the same
## foundry: dark riveted iron plate, brass trim, copper pipework, cream canvas
## gas bags and warm lamps.
##
## A kit is a small palette of materials plus functions that bolt standard
## parts (bedplate, pipe, smokestack, lamp, balloon, propeller, gun barrel,
## hatch, tank...) onto a parent node. The models themselves live in
## BuildingModels, UnitModels and HqModels and only arrange these parts.
##
## Sides: your side has brass trim and warm lamps; a rival has red-oxide trim,
## blackened plate, maroon canvas and its own lamp colour (a corporation's
## "glow" in RivalCatalog). Change a colour here and every model follows.
class_name ModelKit
extends RefCounted

const SKIN := Color(0.85, 0.68, 0.54)
const HUM := Color(0.45, 0.85, 1.0)

## Material names -> [colour, metallic, roughness] for each side.
const PALETTE := {
	"player": {
		"iron": [Color(0.2, 0.2, 0.21), 0.6, 0.55],
		"steel": [Color(0.47, 0.49, 0.52), 0.6, 0.45],
		"brass": [Color(0.8, 0.59, 0.28), 0.85, 0.32],
		"copper": [Color(0.72, 0.4, 0.24), 0.8, 0.38],
		"canvas": [Color(0.86, 0.78, 0.6), 0.0, 0.9],
		"wood": [Color(0.42, 0.28, 0.16), 0.0, 0.8],
		"leather": [Color(0.33, 0.22, 0.15), 0.0, 0.75],
		"rubber": [Color(0.08, 0.08, 0.09), 0.1, 0.8],
		"ceramic": [Color(0.88, 0.86, 0.8), 0.0, 0.5],
	},
	"rival": {
		"iron": [Color(0.14, 0.13, 0.14), 0.6, 0.55],
		"steel": [Color(0.36, 0.33, 0.34), 0.6, 0.45],
		# A rival's "brass" is red-oxide painted iron.
		"brass": [Color(0.6, 0.15, 0.11), 0.4, 0.5],
		"copper": [Color(0.45, 0.24, 0.18), 0.8, 0.4],
		"canvas": [Color(0.5, 0.22, 0.19), 0.0, 0.9],
		"wood": [Color(0.28, 0.17, 0.12), 0.0, 0.8],
		"leather": [Color(0.2, 0.13, 0.11), 0.0, 0.75],
		"rubber": [Color(0.08, 0.08, 0.09), 0.1, 0.8],
		"ceramic": [Color(0.7, 0.66, 0.62), 0.0, 0.5],
	},
}
## Lamp colour per side when a corporation doesn't set its own.
const LAMP := {"player": Color(1.0, 0.76, 0.4), "rival": Color(1.0, 0.33, 0.18)}

## Meshes are shared between every model (keyed by shape and size).
static var _meshes := {}
## Kits shared by things that never recolour their parts (units, props).
static var _shared := {}

var side := "player"
## The model's own paint colour (a building's catalog colour, a unit's coat).
var accent := Color(0.5, 0.5, 0.5)
var lamp_color := LAMP.player
var _mats := {}


func _init(accent_color := Color(0.5, 0.5, 0.5), faction := "player", corp := "") -> void:
	side = "rival" if faction == "rival" else "player"
	accent = accent_color
	lamp_color = LAMP[side]
	if corp != "" and RivalCatalog.has(corp):
		lamp_color = RivalCatalog.get_data(corp).glow[0]


## A kit that is reused by every model with the same colours. Don't change
## its materials: for a model that dims or ghosts, make its own with new().
static func shared(accent_color: Color, faction := "player", corp := "") -> ModelKit:
	var key := [accent_color, faction, corp]
	if not _shared.has(key):
		_shared[key] = ModelKit.new(accent_color, faction, corp)
	return _shared[key]


# --- Materials ---------------------------------------------------------------

## A named material: a PALETTE name, or "accent", "accent_dark", "lamp", "hum",
## "glass", "skin", "shadow".
func mat(mat_name: String) -> StandardMaterial3D:
	if _mats.has(mat_name):
		return _mats[mat_name]
	var m: StandardMaterial3D
	match mat_name:
		"accent":
			m = _make(accent, 0.35, 0.55)
		"accent_dark":
			m = _make(accent.darkened(0.4), 0.35, 0.6)
		"lamp":
			m = _glow(lamp_color, 2.6)
		"hum":
			m = _glow(HUM, 2.2)
		"glass":
			m = _glow(lamp_color.lerp(Color.WHITE, 0.25), 1.2)
		"skin":
			m = _make(SKIN, 0.0, 0.7)
		_:
			var spec: Array = PALETTE[side][mat_name]
			m = _make(spec[0], spec[1], spec[2])
	_mats[mat_name] = m
	return m


## A flat painted colour (cached per kit).
func paint(color: Color, glow := 0.0) -> StandardMaterial3D:
	var key := "paint:%s:%s" % [color.to_html(), glow]
	if not _mats.has(key):
		_mats[key] = _glow(color, glow) if glow > 0.0 else _make(color, 0.2, 0.6)
	return _mats[key]


## Every material this kit has made so far (Building dims and ghosts them).
func materials() -> Array[StandardMaterial3D]:
	var out: Array[StandardMaterial3D] = []
	for m in _mats.values():
		out.append(m)
	return out


func _make(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m


func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var m := _make(color, 0.0, 0.4)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


# --- Basic shapes -------------------------------------------------------------

func add(parent: Node3D, mesh: Mesh, at: Vector3, material: Variant) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = at
	part.material_override = mat(material) if material is String else material
	parent.add_child(part)
	return part


func box(parent: Node3D, size: Vector3, at: Vector3, material: Variant) -> MeshInstance3D:
	return add(parent, box_mesh(size), at, material)


## An upright cylinder or cone (centre at `at`).
func drum(parent: Node3D, top: float, bottom: float, height: float, at: Vector3, material: Variant, sides := 12) -> MeshInstance3D:
	return add(parent, cyl_mesh(top, bottom, height, sides), at, material)


func ball(parent: Node3D, radius: float, at: Vector3, material: Variant, squash := 1.0) -> MeshInstance3D:
	return add(parent, sphere_mesh(radius, squash, false), at, material)


## A half-sphere sitting on `at`.
func dome(parent: Node3D, radius: float, at: Vector3, material: Variant, squash := 1.0) -> MeshInstance3D:
	return add(parent, sphere_mesh(radius, squash, true), at, material)


## A flat ring (a hoop, a band around a boiler, a tyre).
func ring(parent: Node3D, radius: float, thickness: float, at: Vector3, material: Variant = "brass") -> MeshInstance3D:
	return add(parent, torus_mesh(radius, thickness), at, material)


## A straight rod between two points: pipes, struts, masts, barrels, cables.
func rod(parent: Node3D, from: Vector3, to: Vector3, radius: float, material: Variant = "iron", sides := 8) -> MeshInstance3D:
	var part := add(parent, cyl_mesh(radius, radius, maxf(0.01, from.distance_to(to)), sides), (from + to) / 2.0, material)
	aim(part, to - from)
	return part


## A cone between two points (wide at `from`).
func cone(parent: Node3D, from: Vector3, to: Vector3, wide: float, narrow: float, material: Variant, sides := 12) -> MeshInstance3D:
	var part := add(parent, cyl_mesh(narrow, wide, maxf(0.01, from.distance_to(to)), sides), (from + to) / 2.0, material)
	aim(part, to - from)
	return part


## Turns a part so its own up (+Y) axis points along `dir`.
static func aim(part: Node3D, dir: Vector3) -> void:
	if dir.length() < 0.0001:
		return
	var y := dir.normalized()
	var ref := Vector3.RIGHT if absf(y.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x := ref.cross(y).normalized()
	part.basis = Basis(x, y, x.cross(y))


## An empty node to hang a sub-assembly on (a turret head, a rotor).
func group(parent: Node3D, at := Vector3.ZERO, node_name := "") -> Node3D:
	var node := Node3D.new()
	if node_name != "":
		node.name = node_name
	node.position = at
	parent.add_child(node)
	return node


## Spins a node around its own Y axis forever, one turn per `seconds`.
static func spin(node: Node3D, seconds: float) -> void:
	var start := func() -> void:
		var tween := node.create_tween().set_loops()
		tween.tween_property(node, "rotation:y", TAU * signf(seconds), absf(seconds)).from(0.0)
	if node.is_inside_tree():
		start.call()
	else:
		node.tree_entered.connect(start, CONNECT_ONE_SHOT)


# --- Standard parts -----------------------------------------------------------

## The riveted iron footing every building stands on: a six-sided plate with
## a trim ring and a bolt at each corner. Returns the height of its top.
func bedplate(parent: Node3D, radius := 1.2, height := 0.18) -> float:
	var plate := drum(parent, radius * 0.94, radius, height, Vector3(0, height / 2.0, 0), "iron", 6)
	plate.rotation.y = PI / 6.0
	var trim := drum(parent, radius * 0.8, radius * 0.8, 0.05, Vector3(0, height + 0.02, 0), "brass", 6)
	trim.rotation.y = PI / 6.0
	for i in 6:
		var a := TAU * i / 6.0
		drum(parent, 0.07, 0.07, 0.07, Vector3(cos(a), 0, sin(a)) * radius * 0.84 + Vector3(0, height + 0.03, 0), "brass", 6)
	return height + 0.045


## A ring of rivet heads around an upright drum.
func rivets(parent: Node3D, radius: float, y: float, count := 8, material: Variant = "brass") -> void:
	for i in count:
		var a := TAU * (i + 0.5) / count
		ball(parent, 0.05, Vector3(cos(a) * radius, y, sin(a) * radius), material)


## Pipework through a list of points, with a ball joint at every bend.
func pipe(parent: Node3D, points: Array, radius := 0.07, material: Variant = "copper") -> void:
	for i in points.size() - 1:
		rod(parent, points[i], points[i + 1], radius, material)
		if i > 0:
			ball(parent, radius * 1.35, points[i], material)


## An exhaust stack: iron flue, trim collar, sooty cap.
func stack(parent: Node3D, at: Vector3, height := 1.0, radius := 0.14) -> void:
	drum(parent, radius, radius * 1.2, height, at + Vector3(0, height / 2.0, 0), "iron", 10)
	ring(parent, radius * 1.1, radius * 0.3, at + Vector3(0, height * 0.72, 0), "brass")
	drum(parent, radius * 1.3, radius * 1.05, height * 0.12, at + Vector3(0, height, 0), "rubber", 10)


## A lamp on a short post. `on_post` 0 puts the bulb right at `at`.
func lamp(parent: Node3D, at: Vector3, on_post := 0.3, size := 0.11, material: Variant = "lamp") -> MeshInstance3D:
	if on_post > 0.0:
		rod(parent, at, at + Vector3(0, on_post, 0), size * 0.3, "iron", 6)
		drum(parent, size * 0.7, size * 0.9, size * 0.5, at + Vector3(0, on_post, 0), "brass", 8)
	return ball(parent, size, at + Vector3(0, on_post + size * 0.9, 0), material)


## A gas bag lying along Z, with trim hoops and nose caps. `length` is the
## whole bag; `material` is usually "canvas" or the model's accent.
func balloon(parent: Node3D, at: Vector3, radius: float, length: float, material: Variant = "canvas", hoops := 3) -> Node3D:
	var bag := group(parent, at)
	var stretch := length / (radius * 2.0)
	var envelope := add(bag, sphere_mesh(radius, 1.0, false, 20), Vector3.ZERO, material)
	envelope.scale = Vector3(1, 1, stretch)
	for i in hoops:
		var t := (i + 1.0) / (hoops + 1.0) * 2.0 - 1.0
		var r := radius * sqrt(maxf(0.05, 1.0 - t * t * 0.78))
		var hoop := ring(bag, r * 1.01, radius * 0.045, Vector3(0, 0, t * length * 0.44), "brass")
		hoop.rotation.x = PI / 2.0
	for end in [-1.0, 1.0]:
		ball(bag, radius * 0.2, Vector3(0, 0, end * length * 0.485), "brass")
	return bag


## A propeller facing along `axis`. Returns the hub; the blades spin.
func propeller(parent: Node3D, at: Vector3, axis: Vector3, radius: float, blades := 3, seconds := 0.35, material: Variant = "iron") -> Node3D:
	var hub := group(parent, at)
	aim(hub, axis)
	var rotor := group(hub)
	cone(rotor, Vector3.ZERO, Vector3(0, radius * 0.35, 0), radius * 0.16, radius * 0.04, "brass", 8)
	for i in blades:
		var arm := group(rotor)
		arm.rotation.y = TAU * i / blades
		var blade := box(arm, Vector3(radius, 0.03, radius * 0.22), Vector3(radius * 0.5, 0, 0), material)
		blade.rotation.x = 0.35
	if seconds != 0.0:
		spin(rotor, seconds)
	return hub


## A gun barrel from `from` along `dir`: breech sleeve, barrel, muzzle ring.
func barrel(parent: Node3D, from: Vector3, dir: Vector3, length: float, radius := 0.08) -> void:
	var d := dir.normalized()
	rod(parent, from, from + d * length * 0.35, radius * 1.7, "iron", 8)
	rod(parent, from, from + d * length, radius, "steel", 8)
	rod(parent, from + d * (length - radius * 1.6), from + d * length, radius * 1.45, "brass", 8)


## A round hatch with a hand wheel, lying flat on `at`.
func hatch(parent: Node3D, at: Vector3, radius := 0.22) -> void:
	drum(parent, radius, radius, 0.05, at + Vector3(0, 0.025, 0), "steel", 10)
	ring(parent, radius * 0.5, 0.025, at + Vector3(0, 0.07, 0), "brass")


## A pressure tank with bands. `along` is the direction it lies in.
func tank(parent: Node3D, at: Vector3, radius: float, length: float, along := Vector3.UP, material: Variant = "accent") -> Node3D:
	var body := group(parent, at)
	aim(body, along)
	drum(body, radius, radius, length, Vector3.ZERO, material, 12)
	for end in [-1.0, 1.0]:
		add(body, sphere_mesh(radius, 0.5, false), Vector3(0, end * length / 2.0, 0), material)
		ring(body, radius * 1.0, radius * 0.07, Vector3(0, end * length * 0.3, 0), "brass")
	return body


## A louvred vent: a dark opening with slats, facing `normal`.
func vent(parent: Node3D, at: Vector3, normal: Vector3, width := 0.5, height := 0.35) -> void:
	var grille := group(parent, at)
	grille.basis = Basis.looking_at(-normal, Vector3.UP) if absf(normal.y) < 0.9 else Basis.looking_at(-normal, Vector3.FORWARD)
	box(grille, Vector3(width, height, 0.04), Vector3.ZERO, "rubber")
	for i in 3:
		box(grille, Vector3(width, height * 0.12, 0.07), Vector3(0, (i - 1) * height * 0.3, 0.01), "brass")


## A small pennant on a mast, in the side's trim colour, so you can tell whose
## building it is from above.
func pennant(parent: Node3D, at: Vector3, height := 0.9) -> void:
	rod(parent, at, at + Vector3(0, height, 0), 0.025, "iron", 6)
	box(parent, Vector3(0.03, 0.2, 0.38), at + Vector3(0, height - 0.12, 0.2), "accent" if side == "player" else "brass")


## A soft round shadow on the deck under something that flies.
func drop_shadow(parent: Node3D, radius: float, drop: float) -> MeshInstance3D:
	var key := "shadow"
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0, 0, 0, 0.35)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mats[key] = m
	var shadow := drum(parent, radius, radius, 0.02, Vector3(0, -drop + 0.08, 0), _mats[key], 16)
	shadow.name = "Shadow"
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return shadow


# --- Shared meshes --------------------------------------------------------------

static func box_mesh(size: Vector3) -> BoxMesh:
	var key := ["box", size.snapped(Vector3.ONE * 0.001)]
	if not _meshes.has(key):
		var m := BoxMesh.new()
		m.size = size
		_meshes[key] = m
	return _meshes[key]


static func cyl_mesh(top: float, bottom: float, height: float, sides := 12) -> CylinderMesh:
	var key := ["cyl", snappedf(top, 0.001), snappedf(bottom, 0.001), snappedf(height, 0.001), sides]
	if not _meshes.has(key):
		var m := CylinderMesh.new()
		m.top_radius = top
		m.bottom_radius = bottom
		m.height = height
		m.radial_segments = sides
		m.rings = 1
		_meshes[key] = m
	return _meshes[key]


static func sphere_mesh(radius: float, squash := 1.0, half := false, segments := 14) -> SphereMesh:
	var key := ["sphere", snappedf(radius, 0.001), snappedf(squash, 0.001), half, segments]
	if not _meshes.has(key):
		var m := SphereMesh.new()
		m.radius = radius
		m.height = radius * squash * (1.0 if half else 2.0)
		m.is_hemisphere = half
		m.radial_segments = segments
		m.rings = maxi(4, segments / 2)
		_meshes[key] = m
	return _meshes[key]


static func torus_mesh(radius: float, thickness: float) -> TorusMesh:
	var key := ["torus", snappedf(radius, 0.001), snappedf(thickness, 0.001)]
	if not _meshes.has(key):
		var m := TorusMesh.new()
		m.inner_radius = maxf(0.001, radius - thickness)
		m.outer_radius = radius + thickness
		m.rings = 20
		m.ring_segments = 8
		_meshes[key] = m
	return _meshes[key]
