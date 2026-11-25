## RTS selection and orders: click and box select, Shift to add, right-click to
## move (Alt + right-click to attack-move), Q for all units on screen, H for the
## hero, and control groups 1 to 5 (Ctrl + number assigns, double-tap focuses).
class_name SelectionController
extends Node

signal selection_changed(units: Array[Unit])

## Mouse travel in pixels before a left drag becomes a box select.
@export var box_threshold := 6.0
## Click radius in pixels for picking a single unit.
@export var pick_radius := 28.0
## Two presses within this many seconds count as a double-tap.
@export var double_tap_time := 0.3
## Distance between units when a group is ordered to one spot.
@export var formation_spacing := 1.8

@export var camera: RtsCamera
@export var region: SkyRegion
## Optional: lets orders to places walkways don't reach go by airship.
var ferry: FerrySystem

var selected: Array[Unit] = []
var control_groups := {}

var _drag_start := Vector2.ZERO
var _dragging := false
var _box_active := false
var _last_tap := {}

var _overlay: SelectionOverlay


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.name = "SelectionLayer"
	add_child(layer)
	_overlay = SelectionOverlay.new()
	_overlay.name = "SelectionOverlay"
	layer.add_child(_overlay)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("select"):
		_dragging = true
		_box_active = false
		_drag_start = _mouse_position()
	elif event.is_action_released("select") and _dragging:
		_dragging = false
		var additive := Input.is_action_pressed("modifier_additive")
		if _box_active:
			select_units(units_in_screen_rect(_drag_rect()), additive)
		else:
			var unit := unit_at_screen_point(_mouse_position())
			if unit:
				select_units([unit], additive)
			elif not additive:
				select_units([])
		_box_active = false
		_overlay.hide_box()
	elif event is InputEventMouseMotion and _dragging:
		if _mouse_position().distance_to(_drag_start) > box_threshold:
			_box_active = true
		if _box_active:
			_overlay.show_box(_drag_rect())
	elif event.is_action_pressed("command"):
		var point = ground_point_under_mouse()
		if point != null:
			order_move(point, Input.is_action_pressed("modifier_attack_move"))
	elif event.is_action_pressed("select_units_on_screen"):
		select_units(units_in_screen_rect(get_viewport().get_visible_rect()))
	elif event.is_action_pressed("select_hero"):
		var hero := find_hero()
		if hero:
			select_units([hero])
			if _is_double_tap("hero"):
				camera.focus_on(hero.global_position)
	else:
		for i in range(1, 6):
			if event.is_action_pressed("control_group_%d" % i):
				_handle_control_group(i)
				break


## Replaces the selection, or adds to it when `additive` is true.
func select_units(units: Array, additive := false) -> void:
	var next: Array[Unit] = []
	if additive:
		next.assign(selected)
	for u in units:
		if is_instance_valid(u) and not next.has(u):
			next.append(u)
	for u in selected:
		if is_instance_valid(u):
			u.selected = false
	for u in next:
		u.selected = true
	selected = next
	selection_changed.emit(selected)


## Sends the selection to a point, spreading them into a loose formation.
## Returns false if the point isn't reachable over walkways.
func order_move(point: Vector3, attack_move := false) -> bool:
	_prune()
	if selected.is_empty():
		return false
	if not region.is_walkable(point):
		return false
	var offsets := formation_offsets(selected.size())
	var ordered := false
	# The hero takes the centre spot; others fill outward.
	var units := selected.duplicate()
	units.sort_custom(func(a: Unit, b: Unit): return a.is_hero and not b.is_hero)
	for i in units.size():
		var unit: Unit = units[i]
		var target: Vector3 = region.snap_to_walkable(point + offsets[i])
		var clicked := region.platform_at(point)
		if clicked != "":
			target = region.snap_to_platform(point + offsets[i], clicked)
		if ferry:
			ferry.cancel(unit)
			if ferry.is_riding(unit):
				ordered = ferry.send(unit, target, attack_move) or ordered
				continue
		var route: PackedVector3Array = region.find_route(unit.position, target)
		if route.is_empty():
			# Somewhere a walkway doesn't reach: take the airship ferry.
			if ferry and ferry.send(unit, target, attack_move):
				ordered = true
			continue
		unit.set_route(route, attack_move)
		ordered = true
	if ordered:
		_overlay_marker(point, attack_move)
	return ordered


## Grid offsets around the click point, centre first.
func formation_offsets(count: int) -> Array[Vector3]:
	return formation_offsets_for(count, formation_spacing)


static func formation_offsets_for(count: int, formation_spacing: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var side := int(ceil(sqrt(float(count))))
	var cells: Array[Vector2] = []
	for row in side:
		for col in side:
			cells.append(Vector2(col - (side - 1) / 2.0, row - (side - 1) / 2.0))
	cells.sort_custom(func(a: Vector2, b: Vector2): return a.length_squared() < b.length_squared())
	for i in count:
		var c: Vector2 = cells[i] * formation_spacing
		out.append(Vector3(c.x, 0.0, c.y))
	return out


func all_units() -> Array[Unit]:
	var out: Array[Unit] = []
	for node in get_tree().get_nodes_in_group(Unit.GROUP):
		out.append(node as Unit)
	return out


func find_hero() -> Unit:
	for u in all_units():
		if u.is_hero:
			return u
	return null


func unit_at_screen_point(screen: Vector2) -> Unit:
	var best: Unit = null
	var best_dist := pick_radius
	for u in all_units():
		var p = _screen_position(u)
		if p == null:
			continue
		var d: float = screen.distance_to(p)
		if d < best_dist:
			best_dist = d
			best = u
	return best


func units_in_screen_rect(rect: Rect2) -> Array[Unit]:
	var out: Array[Unit] = []
	for u in all_units():
		var p = _screen_position(u)
		if p != null and rect.has_point(p):
			out.append(u)
	return out


## The point on the deck plane (y = 0) under the mouse, or null.
func ground_point_under_mouse():
	return ground_point_at(_mouse_position())


func ground_point_at(screen: Vector2):
	var cam := camera.camera
	var origin := cam.project_ray_origin(screen)
	var normal := cam.project_ray_normal(screen)
	return Plane(Vector3.UP, 0.0).intersects_ray(origin, normal)


func assign_control_group(index: int) -> void:
	_prune()
	control_groups[index] = selected.duplicate()


func recall_control_group(index: int) -> void:
	var group: Array = control_groups.get(index, [])
	select_units(group.filter(func(u): return is_instance_valid(u)))


func _handle_control_group(index: int) -> void:
	if Input.is_action_pressed("control_group_assign"):
		assign_control_group(index)
		return
	recall_control_group(index)
	if _is_double_tap("group_%d" % index) and not selected.is_empty():
		var centre := Vector3.ZERO
		for u in selected:
			centre += u.global_position
		camera.focus_on(centre / selected.size())


func _is_double_tap(key: String) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	var last: float = _last_tap.get(key, -10.0)
	_last_tap[key] = now
	return now - last <= double_tap_time


func _screen_position(u: Unit):
	var cam := camera.camera
	var world := u.global_position + Vector3.UP
	if cam.is_position_behind(world):
		return null
	return cam.unproject_position(world)


func _mouse_position() -> Vector2:
	return get_viewport().get_mouse_position()


func _drag_rect() -> Rect2:
	return Rect2(_drag_start, Vector2.ZERO).expand(_mouse_position())


func _prune() -> void:
	selected = selected.filter(func(u): return is_instance_valid(u))


func _overlay_marker(point: Vector3, attack_move: bool) -> void:
	var marker := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.6
	torus.outer_radius = 0.8
	marker.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.35, 0.3) if attack_move else Color(0.4, 1.0, 0.55)
	marker.material_override = mat
	region.add_child(marker)
	marker.global_position = point + Vector3.UP * 0.05
	var tween := marker.create_tween()
	tween.set_parallel(true)
	tween.tween_property(marker, "scale", Vector3.ONE * 0.2, 0.5)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.5)
	tween.chain().tween_callback(marker.queue_free)
