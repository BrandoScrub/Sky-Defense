## Building new walkways. Pick Walkway in the build menu, click a tile on a platform you own, then
## click a tile on another platform. Harpoons fire across and the walkway is
## laid one tile at a time (WalkwayCrew). A preview shows the planned tiles in green
## (or red if it can't be built) with the scrap cost. Esc or right click cancels.
class_name WalkwayBuilder
extends Node

signal notice(text: String)
signal mode_changed(active: bool)

@export var region: SkyRegion
@export var camera: RtsCamera
@export var resources: PlayerResources

var active := false
## First click, or null while waiting for it.
var start_hex = null

var _preview: Node3D
var _preview_key := ""


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event.is_action_pressed("select"):
		var hex = _hex_under_mouse()
		if start_hex == null:
			var tile := region.get_tile(hex) if hex != null else {}
			if tile.is_empty() or tile.platform == "" or region.platform_owner(tile.platform) != "player":
				notice.emit("Start the walkway on an island you own")
			else:
				start_hex = hex
		else:
			var err := try_build(start_hex, hex)
			if err != "":
				notice.emit(err)
			else:
				cancel()
		_handled()
	elif event.is_action_released("select"):
		_handled()
	elif event.is_action_pressed("command") or event.is_action_pressed("building_cancel"):
		cancel()
		_handled()


func _process(_delta: float) -> void:
	if active and start_hex != null:
		var hex = _hex_under_mouse()
		if hex != null:
			_show_preview(region.plan_walkway(start_hex, hex))


func begin() -> void:
	active = true
	start_hex = null
	mode_changed.emit(true)


func cancel() -> void:
	active = false
	start_hex = null
	_clear_preview()
	mode_changed.emit(false)


## Builds the walkway if the plan works and the player can pay. Returns "" or
## the reason it failed.
func try_build(from_hex: Vector2i, to_hex) -> String:
	if to_hex == null:
		return "Point at another island"
	var plan := region.plan_walkway(from_hex, to_hex)
	if plan.problem != "":
		return plan.problem
	if not resources.spend_scrap(plan.cost):
		return "Not enough scrap (%d needed)" % plan.cost
	region.build_walkway(plan.tiles, "player", region.hex_center(from_hex), region.hex_center(to_hex))
	notice.emit("Harpoons away! Laying %d tiles of walkway  (-%d scrap)" % [plan.tiles.size(), plan.cost])
	return ""


func _show_preview(plan: Dictionary) -> void:
	var key: String = str(plan.tiles) + plan.problem + str(resources.scrap)
	if key == _preview_key:
		return
	_clear_preview()
	_preview_key = key
	_preview = Node3D.new()
	_preview.name = "WalkwayPreview"
	region.add_child(_preview)
	var ok: bool = plan.problem == "" and resources.can_afford(plan.cost)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.4, 1.0, 0.5, 0.5) if ok else Color(1.0, 0.3, 0.25, 0.5)
	var mesh := CylinderMesh.new()
	mesh.top_radius = region.tile_size * 0.9
	mesh.bottom_radius = mesh.top_radius
	mesh.height = 0.3
	mesh.radial_segments = 6
	for hex in plan.tiles:
		var tile := MeshInstance3D.new()
		tile.mesh = mesh
		tile.material_override = mat
		tile.position = region.hex_center(hex) + Vector3.DOWN * 0.15
		_preview.add_child(tile)
	if plan.problem != "":
		notice.emit(plan.problem)
	elif not plan.tiles.is_empty():
		notice.emit("%d tiles, %d scrap" % [plan.tiles.size(), plan.cost])


func _clear_preview() -> void:
	_preview_key = ""
	if _preview:
		_preview.queue_free()
		_preview = null


func _hex_under_mouse():
	var cam := camera.camera
	var screen := get_viewport().get_mouse_position()
	var hit = Plane(Vector3.UP, 0.0).intersects_ray(cam.project_ray_origin(screen), cam.project_ray_normal(screen))
	return region.hex_at(hit) if hit != null else null


func _handled() -> void:
	get_viewport().set_input_as_handled()
