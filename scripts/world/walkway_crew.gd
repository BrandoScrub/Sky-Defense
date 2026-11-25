## Builds walkways the way the sky companies do it. Two harpoons fire from
## the starting island, trailing cables, and bite into the far island. Then
## the walkway is laid along the cables one tile at a time, starting from the
## near end. When the last tile is down the cables are reeled in.
##
## Both your walkways and Ironbell's bridges are built this way (Ironbell's
## crews lay tiles a little slower). Units can walk on each tile as soon as it
## is down. Set SkyRegion.instant_walkways to lay walkways in one go instead.
class_name WalkwayCrew
extends Node3D

## A walkway finished: its tiles are all down.
signal finished(job: Dictionary)

@export var region: SkyRegion
## Seconds for the harpoons to fly across.
@export var harpoon_seconds := 0.7
## Seconds per tile laid.
@export var player_tile_seconds := 0.3
@export var rival_tile_seconds := 0.5

const CABLE_SIDE := 0.7
const CABLE_HEIGHT := 0.5

## Each job: {tiles: Array[Vector2i] (near end first), builder, from: Vector3,
## to: Vector3, t: seconds since start, laid: int, nodes: Node3D,
## harpoons: [Node3D, Node3D], cables: [MeshInstance3D, MeshInstance3D],
## on_done: Callable or null}
var jobs: Array[Dictionary] = []
var _cable_mesh: CylinderMesh
var _mats := {}


func _ready() -> void:
	_cable_mesh = CylinderMesh.new()
	_cable_mesh.top_radius = 0.08
	_cable_mesh.bottom_radius = 0.08
	_cable_mesh.height = 1.0
	_cable_mesh.radial_segments = 4


func _process(delta: float) -> void:
	step(delta)


## Starts building a walkway over `new_tiles` from the point `from` to `to`
## (both on deck level). Returns the job.
func start(new_tiles: Array, builder: String, from: Vector3, to: Vector3, on_done = null) -> Dictionary:
	var ordered: Array[Vector2i] = []
	ordered.assign(new_tiles)
	ordered.sort_custom(func(a, b): return region.hex_center(a).distance_to(from) < region.hex_center(b).distance_to(from))
	for hex in ordered:
		region.pending_hexes[hex] = true
	var job := {
		"tiles": ordered, "builder": builder, "from": from, "to": to, "t": 0.0, "laid": 0,
		"on_done": on_done,
	}
	_build_rig(job)
	jobs.append(job)
	return job


## Seconds a job takes from firing to its last tile.
func job_seconds(job: Dictionary) -> float:
	return harpoon_seconds + job.tiles.size() * _tile_seconds(job)


## Advances every job by `delta` seconds. Public so tests can drive it.
func step(delta: float) -> void:
	for job in jobs.duplicate():
		job.t += delta
		_update_rig(job)
		var due := int(floor((job.t - harpoon_seconds) / _tile_seconds(job))) + 1 if job.t >= harpoon_seconds else 0
		while job.laid < mini(due, job.tiles.size()):
			_lay(job, job.tiles[job.laid])
			job.laid += 1
		if job.laid >= job.tiles.size() and job.t >= harpoon_seconds:
			_finish(job)


## Lays every remaining tile of every job right now.
func finish_all() -> void:
	for job in jobs.duplicate():
		while job.laid < job.tiles.size():
			_lay(job, job.tiles[job.laid])
			job.laid += 1
		_finish(job)


func is_busy() -> bool:
	return not jobs.is_empty()


func _tile_seconds(job: Dictionary) -> float:
	return rival_tile_seconds if job.builder == "rival" else player_tile_seconds


func _lay(job: Dictionary, hex: Vector2i) -> void:
	region.pending_hexes.erase(hex)
	if not region.tiles.has(hex):
		region.add_walkway_tile(hex, job.builder)
		# Each tile swings into place under the cables.
		var node := region.tile_node(hex)
		if node and is_inside_tree():
			var rest := node.position
			node.scale = Vector3(0.3, 1.0, 0.3)
			node.position = rest + Vector3.UP * 0.6
			var tween := node.create_tween().set_parallel()
			tween.tween_property(node, "scale", Vector3.ONE, 0.2)
			tween.tween_property(node, "position", rest, 0.2)


func _finish(job: Dictionary) -> void:
	jobs.erase(job)
	if is_instance_valid(job.nodes):
		job.nodes.queue_free()
	region.finish_walkway()
	finished.emit(job)
	if job.on_done is Callable:
		job.on_done.call()


# --- Harpoons and cables ----------------------------------------------------

func _build_rig(job: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "WalkwayRig"
	# Positioned at the start so the fog of war treats it like the island.
	root.position = job.from
	add_child(root)
	job.nodes = root
	var metal := _mat(Color(0.25, 0.24, 0.24) if job.builder != "rival" else Color(0.4, 0.15, 0.12))
	var brass := _mat(Color(0.75, 0.56, 0.25))
	job.harpoons = []
	job.cables = []
	for side in [-1.0, 1.0]:
		# The launcher on the near island.
		var launcher := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.5, 0.4, 0.5)
		launcher.mesh = box
		launcher.material_override = brass
		launcher.position = _anchor(job, side, job.from) - root.position
		root.add_child(launcher)
		# The harpoon: a shaft and a barbed head.
		var harpoon := Node3D.new()
		var shaft := MeshInstance3D.new()
		var rod := CylinderMesh.new()
		rod.top_radius = 0.06
		rod.bottom_radius = 0.06
		rod.height = 1.0
		shaft.mesh = rod
		shaft.rotation.x = PI / 2.0
		shaft.material_override = metal
		harpoon.add_child(shaft)
		var head := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.2
		cone.height = 0.45
		head.mesh = cone
		head.rotation.x = -PI / 2.0
		head.position = Vector3(0, 0, -0.65)
		head.material_override = metal
		harpoon.add_child(head)
		root.add_child(harpoon)
		job.harpoons.append(harpoon)
		var cable := MeshInstance3D.new()
		cable.mesh = _cable_mesh
		cable.material_override = metal
		root.add_child(cable)
		job.cables.append(cable)
	_update_rig(job)


## Where one side's cable is fixed at a point: off to the left or right.
func _anchor(job: Dictionary, side: float, at: Vector3) -> Vector3:
	var dir: Vector3 = job.to - job.from
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	var across := Vector3(-dir.z, 0.0, dir.x)
	return at + across * side * CABLE_SIDE + Vector3.UP * CABLE_HEIGHT


func _update_rig(job: Dictionary) -> void:
	var flight := clampf(job.t / harpoon_seconds, 0.0, 1.0)
	var root: Node3D = job.nodes
	for i in 2:
		var side: float = [-1.0, 1.0][i]
		var start := _anchor(job, side, job.from)
		var end := _anchor(job, side, job.to)
		# The harpoon arcs across; once it lands it stays put.
		var tip := start.lerp(end, flight) + Vector3.UP * sin(flight * PI) * 1.5
		var harpoon: Node3D = job.harpoons[i]
		harpoon.position = tip - root.position
		var ahead := start.lerp(end, minf(flight + 0.05, 1.0)) + Vector3.UP * sin(minf(flight + 0.05, 1.0) * PI) * 1.5
		if ahead.distance_to(tip) > 0.001:
			harpoon.look_at_from_position(harpoon.position, ahead - root.position, Vector3.UP)
		_stretch(job.cables[i], start - root.position, tip - root.position)


## Points a unit-length cable from `a` to `b`.
func _stretch(cable: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var length := a.distance_to(b)
	if length < 0.01:
		cable.visible = false
		return
	cable.visible = true
	var mid := (a + b) / 2.0
	var y := (b - a) / length
	var x := y.cross(Vector3.UP)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(y).normalized()
	cable.transform = Transform3D(Basis(x, y * length, z), mid)


func _mat(color: Color) -> StandardMaterial3D:
	if not _mats.has(color):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.5
		m.metallic = 0.4
		_mats[color] = m
	return _mats[color]
