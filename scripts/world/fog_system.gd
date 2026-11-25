## Fog of war: a bank of dark storm clouds over everything the player hasn't
## scouted yet. The sky between corporations stays hidden until your units
## or platforms get close; once a patch of sky is cleared it stays clear.
##
## - Explored sky shows its platforms, walkways and buildings for good.
## - Rival units are only shown where you can see right now (near your units
##   or the platforms you own). Out of sight they vanish back into the murk.
## - Some islands glow through the clouds: crystal seams, generator sockets
##   and rival HQs give off a coloured glow with a vague hint, so you know
##   something is out there before you know the way to it.
##
## The fog is only visual. It never changes what units, towers or rivals can
## do, so the rest of the game works the same with it switched off.
class_name FogSystem
extends Node3D

signal platform_revealed(platform_name: String)

@export var region: SkyRegion
@export var ferry: FerrySystem
## Side of one square fog cell in world units.
@export var cell_size := 6.0
## How far a player unit sees.
@export var unit_sight := 13.0
## How far past its own edge a player-owned platform sees.
@export var platform_sight := 12.0
## Seconds between visibility updates.
@export var tick := 0.2

const PUFFS_PER_CELL := 3
const FADE_SECONDS := 0.8
const FOG_COLOR := Color(0.06, 0.065, 0.1)

## What glows through the fog: feature type -> [colour, hint]. Rival HQs use
## their corporation's colour instead.
const GLOWS := {
	"rival_core": [Color(1.0, 0.35, 0.15), "Furnace glare"],
	"crystal_seam": [Color(0.35, 0.95, 1.0), "Crystal glow"],
	"generator_socket": [Color(1.0, 0.8, 0.3), "Electric hum"],
}
const CORP_GLOWS := {
	"Ironbell": [Color(1.0, 0.35, 0.15), "Furnace glare"],
	"Vesper": [Color(0.8, 0.4, 1.0), "Signal lamps"],
}

## Cell -> true once it has been seen.
var explored := {}
## Cell -> true while something of yours can see it.
var visible_cells := {}
var _area := Rect2i()
var _cell_index := {}
var _puff_base: Array[Transform3D] = []
## Cell -> seconds of fade left.
var _fading := {}
var _multimesh: MultiMesh
## [node, cell] for scenery that appears once its cell is explored.
var _scenery: Array = []
var _tracked := {}
## platform name -> beacon node (until the platform is revealed)
var beacons := {}
var _revealed_platforms := {}
var _timer := 0.0
var _flash_timer := 2.0
var _flash: OmniLight3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 7
	var bounds := region.get_bounds().grow(cell_size * 2.0)
	var from := _cell_of(Vector3(bounds.position.x, 0, bounds.position.y))
	var to := _cell_of(Vector3(bounds.end.x, 0, bounds.end.y))
	_area = Rect2i(from, to - from + Vector2i.ONE)
	_build_fog()
	_build_beacons()
	_collect_scenery()
	region.walkways_changed.connect(_collect_scenery)
	update_visibility()
	for cell in _fading.keys():
		_set_cell_scale(cell, 0.0)
	_fading.clear()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = tick
		update_visibility()
	_animate(delta)


# --- Queries ----------------------------------------------------------------

func is_explored(point: Vector3) -> bool:
	return explored.has(_cell_of(point))


func is_visible_now(point: Vector3) -> bool:
	return visible_cells.has(_cell_of(point))


func is_platform_revealed(platform_name: String) -> bool:
	return _revealed_platforms.has(platform_name)


## Clears the whole map (for testing, or a future scouting ability).
func reveal_all() -> void:
	for x in range(_area.position.x, _area.end.x):
		for y in range(_area.position.y, _area.end.y):
			_explore(Vector2i(x, y))
	_refresh_nodes()


## Recomputes what the player can see. Public so tests can drive it.
func update_visibility() -> void:
	visible_cells.clear()
	for p in region.layout.platforms:
		if region.platform_owner(p.name) == "player":
			var reach: float = region.tile_size * HexGrid.SQRT3 * (p.radius + 0.5) + platform_sight
			_see(region.get_platform_position(p.name), reach)
	for node in get_tree().get_nodes_in_group(Unit.GROUP):
		var unit := node as Unit
		if unit and unit.is_alive():
			_see(unit.position, unit_sight)
	_refresh_nodes()


# --- Visibility -------------------------------------------------------------

func _cell_of(point: Vector3) -> Vector2i:
	return Vector2i(floori(point.x / cell_size), floori(point.z / cell_size))


func _cell_center(cell: Vector2i) -> Vector3:
	return Vector3((cell.x + 0.5) * cell_size, 0.0, (cell.y + 0.5) * cell_size)


func _see(point: Vector3, radius: float) -> void:
	var c := _cell_of(point)
	var reach := ceili(radius / cell_size)
	for x in range(c.x - reach, c.x + reach + 1):
		for y in range(c.y - reach, c.y + reach + 1):
			var cell := Vector2i(x, y)
			var d := _cell_center(cell) - point
			if Vector2(d.x, d.z).length() <= radius + cell_size * 0.5:
				visible_cells[cell] = true
				_explore(cell)


func _explore(cell: Vector2i) -> void:
	if explored.has(cell):
		return
	explored[cell] = true
	if _cell_index.has(cell):
		_fading[cell] = FADE_SECONDS


func _refresh_nodes() -> void:
	# Scenery: shown for good once its cell is explored.
	var still_hidden: Array = []
	for entry in _scenery:
		var node = entry[0]
		if not is_instance_valid(node):
			continue
		if explored.has(entry[1]):
			node.visible = true
		else:
			still_hidden.append(entry)
	_scenery = still_hidden

	# Buildings (they come and go) follow explored sky.
	var root := region.get_node_or_null("Buildings")
	if root:
		for b in root.get_children():
			if b is Node3D:
				b.visible = is_explored(b.global_position)

	# Rival units only show where you can see them right now.
	for node in get_tree().get_nodes_in_group(Unit.ENEMY_GROUP):
		if node is Node3D:
			node.visible = is_visible_now(node.global_position)

	# Ferries are neutral traffic: shown over explored sky.
	if ferry:
		for f in ferry.ferries:
			f.ship.visible = is_explored(f.ship.global_position)

	for p in layout_platforms():
		if _revealed_platforms.has(p.name):
			continue
		if explored.has(_cell_of(region.get_platform_position(p.name))):
			_revealed_platforms[p.name] = true
			if beacons.has(p.name):
				beacons[p.name].queue_free()
				beacons.erase(p.name)
			platform_revealed.emit(p.name)


func layout_platforms() -> Array:
	return region.layout.platforms


## Hides every piece of map scenery that sits in unexplored sky.
func _collect_scenery() -> void:
	var ships := []
	if ferry:
		for f in ferry.ferries:
			ships.append(f.ship)
	for child in region.get_children():
		if not child is Node3D or child == self or ships.has(child) or child.name == "Buildings":
			continue
		var n := String(child.name)
		var is_group := n == "Tiles" or n.begins_with("Cloud_") or n.begins_with("AirLane_") or n.begins_with("Ferry_")
		if is_group:
			for part in child.get_children():
				_track(part)
		else:
			_track(child)


func _track(node: Node) -> void:
	if not node is Node3D or _tracked.has(node):
		return
	_tracked[node] = true
	var cell := _cell_of(node.global_position)
	if not explored.has(cell):
		node.visible = false
		_scenery.append([node, cell])


# --- Fog bank ---------------------------------------------------------------

func _build_fog() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = cell_size * 0.78
	sphere.height = cell_size * 0.9
	sphere.radial_segments = 12
	sphere.rings = 6
	var mat := StandardMaterial3D.new()
	mat.albedo_color = FOG_COLOR
	mat.roughness = 1.0
	_no_distance_haze(mat)
	sphere.material = mat

	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	# The headless test runner has no renderer to draw the puffs with.
	if DisplayServer.get_name() != "headless":
		_multimesh.mesh = sphere
	_multimesh.instance_count = _area.size.x * _area.size.y * PUFFS_PER_CELL
	var i := 0
	for x in range(_area.position.x, _area.end.x):
		for y in range(_area.position.y, _area.end.y):
			var cell := Vector2i(x, y)
			_cell_index[cell] = i
			var center := _cell_center(cell)
			for k in PUFFS_PER_CELL:
				# A high lumpy top that hides decks and air lanes, and a low
				# layer that hides the rock and engines under the platforms.
				var height: float = [6.5, 4.0, -3.0][k] + _rng.randf_range(-1.0, 1.2)
				var jitter := Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)) * cell_size * 0.3
				var s := _rng.randf_range(0.9, 1.35)
				var t := Transform3D(Basis.from_scale(Vector3(s, s * 0.8, s)).rotated(Vector3.UP, _rng.randf() * TAU), center + jitter + Vector3.UP * height)
				_puff_base.append(t)
				_multimesh.set_instance_transform(i, t)
				i += 1

	var fog := MultiMeshInstance3D.new()
	fog.name = "FogBank"
	fog.multimesh = _multimesh
	fog.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fog)

	_flash = OmniLight3D.new()
	_flash.name = "FogLightning"
	_flash.light_color = Color(0.75, 0.8, 1.0)
	_flash.omni_range = 26.0
	_flash.light_energy = 0.0
	add_child(_flash)


func _set_cell_scale(cell: Vector2i, amount: float) -> void:
	var base: int = _cell_index[cell]
	for k in PUFFS_PER_CELL:
		var t: Transform3D = _puff_base[base + k]
		var scaled := Transform3D(t.basis.scaled(Vector3.ONE * maxf(amount, 0.0001)), t.origin + Vector3.UP * (1.0 - amount) * 3.0)
		_multimesh.set_instance_transform(base + k, scaled)


func _animate(delta: float) -> void:
	for cell in _fading.keys():
		_fading[cell] -= delta
		var left: float = _fading[cell]
		_set_cell_scale(cell, clampf(left / FADE_SECONDS, 0.0, 1.0))
		if left <= 0.0:
			_fading.erase(cell)

	# Lightning flickering somewhere inside the unexplored murk.
	_flash_timer -= delta
	_flash.light_energy = maxf(0.0, _flash.light_energy - delta * 14.0)
	if _flash_timer <= 0.0:
		_flash_timer = _rng.randf_range(1.5, 4.0)
		var cell := Vector2i(_rng.randi_range(_area.position.x, _area.end.x - 1), _rng.randi_range(_area.position.y, _area.end.y - 1))
		if not explored.has(cell):
			_flash.position = _cell_center(cell) + Vector3.UP * 5.0
			_flash.light_energy = 6.0

	var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() / 400.0)
	for b in beacons.values():
		b.get_node("Light").light_energy = 2.2 * pulse


# --- Glowing islands --------------------------------------------------------

func _build_beacons() -> void:
	for p in layout_platforms():
		var glow := _glow_for(p)
		if glow.is_empty():
			continue
		var beacon := Node3D.new()
		beacon.name = "Glow_" + p.name.replace(" ", "")
		beacon.position = region.get_platform_position(p.name) + Vector3.UP * 10.0
		add_child(beacon)

		var halo := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 3.0 + p.radius * 1.0
		sphere.height = sphere.radius * 1.2
		halo.mesh = sphere
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(glow[0], 0.6)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.emission_enabled = true
		mat.emission = glow[0]
		mat.emission_energy_multiplier = 1.5
		_no_distance_haze(mat)
		halo.material_override = mat
		halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		beacon.add_child(halo)

		var light := OmniLight3D.new()
		light.name = "Light"
		light.light_color = glow[0]
		light.omni_range = 12.0 + p.radius * 3.0
		light.light_energy = 2.2
		light.position = Vector3.UP * 1.5
		beacon.add_child(light)

		var hint := Label3D.new()
		hint.text = glow[1] + "?"
		hint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		hint.no_depth_test = true
		hint.font_size = 64
		hint.outline_size = 12
		hint.pixel_size = 0.04
		hint.modulate = glow[0].lightened(0.4)
		hint.position = Vector3.UP * (5.0 + p.radius)
		beacon.add_child(hint)
		beacons[p.name] = beacon


## The colour and hint an island shows through the fog, or [] for none.
## Rival HQs first, then crystal, then generator sockets.
func _glow_for(p: Dictionary) -> Array:
	var types: Array = []
	for f in p.features:
		types.append(f[0])
	if types.has("rival_core"):
		return CORP_GLOWS.get(p.get("corp", ""), GLOWS.rival_core)
	for type in ["crystal_seam", "generator_socket"]:
		if types.has(type):
			return GLOWS[type]
	return []


## Keeps the scene's distance haze from washing the storm out to grey when
## the camera is zoomed far out.
func _no_distance_haze(mat: BaseMaterial3D) -> void:
	if "disable_fog" in mat:
		mat.set("disable_fog", true)
