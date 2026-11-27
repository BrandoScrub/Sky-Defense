## Build mode. The build menu (scripts/ui/build_menu.gd) picks a building and show a ghost that snaps to the
## hex under the mouse (green if it can go there, red if not). Left click
## places, Shift + left click keeps placing, R rotates, Esc or right click
## cancels. Delete demolishes the building under the mouse for a partial refund.
class_name BuildController
extends Node

## Emitted with a short message for the HUD, e.g. why a placement failed.
signal notice(text: String)
signal mode_changed(type_id: String)

@export var region: SkyRegion
@export var camera: RtsCamera
@export var resources: PlayerResources

## Type being placed, or "" when not in build mode.
var placing := ""
var facing := 0

var _ghost: Building
var _ghost_hex := Vector2i(999999, 999999)


func _unhandled_input(event: InputEvent) -> void:
	if placing != "":
		if event.is_action_pressed("building_rotate", true):
			facing = (facing + 1) % 6
			_update_ghost(true)
			_handled()
		elif event.is_action_pressed("select"):
			var err := try_place(placing, _hex_under_mouse(), facing)
			if err != "":
				notice.emit(err)
			elif not Input.is_action_pressed("modifier_additive"):
				cancel_placing()
			_handled()
		elif event.is_action_pressed("command") or event.is_action_pressed("building_cancel"):
			cancel_placing()
			_handled()
		elif event.is_action_released("select"):
			# Keep the release from reaching selection as a click.
			_handled()
	elif event.is_action_pressed("demolish"):
		var hex = _hex_under_mouse()
		if hex != null and region.buildings.has(hex):
			demolish(hex)
			_handled()


func _process(_delta: float) -> void:
	if placing != "":
		_update_ghost()


func start_placing(type_id: String) -> void:
	cancel_placing()
	placing = type_id
	_ghost = Building.new().setup(type_id)
	_ghost.name = "Ghost"
	region.add_child(_ghost)
	_ghost.visible = false
	_update_ghost(true)
	mode_changed.emit(placing)


func cancel_placing() -> void:
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	if placing != "":
		placing = ""
		mode_changed.emit(placing)


## Why this building can't go on this tile right now, or "".
func placement_problem(type_id: String, hex) -> String:
	if hex == null:
		return "Point at an island deck"
	var problem := region.build_problem(type_id, hex)
	if problem != "":
		return problem
	if _unit_on(hex):
		return "Units are standing there"
	if type_id == "lift_engine":
		var platform: String = region.get_tile(hex).get("platform", "")
		for b in region.buildings_on(platform):
			if b.type_id == "lift_engine":
				return "One Lift Engine per island"
	return resources.shortfall(BuildingCatalog.get_data(type_id).cost, BuildingCatalog.crystals_of(type_id))


## Places a building if allowed. Returns "" on success, or the reason it failed.
func try_place(type_id: String, hex, rotation_steps := 0) -> String:
	var problem := placement_problem(type_id, hex)
	if problem != "":
		return problem
	var data := BuildingCatalog.get_data(type_id)
	var crystals := BuildingCatalog.crystals_of(type_id)
	resources.pay(data.cost, crystals)
	region.place_building(Building.new().setup(type_id), hex, rotation_steps)
	notice.emit("%s built  (-%d scrap%s)" % [data.name, data.cost, ", -%d crystals" % crystals if crystals > 0 else ""])
	return ""


## Removes a building and refunds part of its cost.
func demolish(hex: Vector2i) -> int:
	var existing: Building = region.buildings.get(hex)
	if existing == null or existing.faction != "player":
		# Ironbell's buildings have to be destroyed in a fight.
		return 0
	var building := region.remove_building(hex)
	var refund := BuildingCatalog.refund_for(building.type_id)
	var crystal_refund := BuildingCatalog.crystal_refund_for(building.type_id)
	resources.add_scrap(refund)
	if crystal_refund > 0:
		resources.add_crystals(crystal_refund)
	notice.emit("%s torn down for parts  (+%d scrap%s)" % [building.get_data().name, refund, ", +%d crystals" % crystal_refund if crystal_refund > 0 else ""])
	building.queue_free()
	return refund


func _update_ghost(force := false) -> void:
	if _ghost == null:
		return
	var hex = _hex_under_mouse()
	if hex == null or region.get_tile(hex).is_empty():
		_ghost.visible = false
		return
	if not force and hex == _ghost_hex:
		return
	_ghost_hex = hex
	_ghost.visible = true
	_ghost.position = region.hex_center(hex)
	_ghost.rotation.y = facing * PI / 3.0
	_ghost.set_ghost(placement_problem(placing, hex) == "")


func _unit_on(hex: Vector2i) -> bool:
	for node in get_tree().get_nodes_in_group(Unit.GROUP) + get_tree().get_nodes_in_group(Unit.ENEMY_GROUP):
		if region.hex_at((node as Node3D).global_position) == hex:
			return true
	return false


func _hex_under_mouse():
	var viewport := get_viewport()
	var cam := camera.camera
	var screen := viewport.get_mouse_position()
	var hit = Plane(Vector3.UP, 0.0).intersects_ray(cam.project_ray_origin(screen), cam.project_ray_normal(screen))
	if hit == null:
		return null
	return region.hex_at(hit)


func _handled() -> void:
	get_viewport().set_input_as_handled()
