## Angled top-down RTS camera.
##
## The node itself is a pivot that sits on the play plane; the Camera3D child
## orbits it. Zooming out raises the pitch and widens the field of view so a
## whole sky region fits on screen; zooming in tilts toward the horizon.
class_name RtsCamera
extends Node3D

@export_group("Pan")
## World units per second at the closest zoom.
@export var pan_speed_near := 12.0
## World units per second at the furthest zoom.
@export var pan_speed_far := 60.0
## Pan when the mouse is within this fraction of the screen edge.
@export_range(0.0, 0.2) var edge_scroll_margin := 0.02
@export var edge_scroll_enabled := true
## Pivot is kept inside this rectangle on the XZ plane (position, size).
@export var bounds := Rect2(-100, -100, 200, 200)

@export_group("Zoom")
@export var distance_min := 12.0
@export var distance_max := 120.0
## Fraction of the zoom range moved per wheel step.
@export_range(0.01, 0.5) var zoom_step := 0.1
@export var zoom_smoothing := 10.0
## Downward pitch in degrees at the closest and furthest zoom.
@export var pitch_near := 35.0
@export var pitch_far := 65.0
@export var fov_near := 50.0
@export var fov_far := 60.0

@export_group("Rotate")
## Degrees of yaw per pixel of mouse movement while the rotate button is held.
@export var rotate_speed := 0.3

@export_group("Focus")
@export var focus_duration := 0.4

var camera: Camera3D

## 0 = closest, 1 = furthest.
var zoom := 0.5
var _target_zoom := 0.5
var _yaw := 0.0
var _rotating := false
var _focus_tween: Tween


func _ready() -> void:
	camera = get_node_or_null("Camera3D")
	if camera == null:
		camera = Camera3D.new()
		camera.name = "Camera3D"
		add_child(camera)
	_yaw = rotation_degrees.y
	_apply_zoom()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_zoom_in"):
		_target_zoom = clampf(_target_zoom - zoom_step, 0.0, 1.0)
	elif event.is_action_pressed("camera_zoom_out"):
		_target_zoom = clampf(_target_zoom + zoom_step, 0.0, 1.0)
	elif event.is_action_pressed("camera_rotate"):
		_rotating = true
	elif event.is_action_released("camera_rotate"):
		_rotating = false
	elif event is InputEventMouseMotion and _rotating:
		_yaw -= event.relative.x * rotate_speed
		rotation_degrees.y = _yaw


func _process(delta: float) -> void:
	var move := _keyboard_pan() + _edge_pan()
	if move != Vector2.ZERO:
		_cancel_focus()
		var speed := lerpf(pan_speed_near, pan_speed_far, zoom)
		var dir := (basis * Vector3(move.x, 0.0, move.y))
		dir.y = 0.0
		position += dir.normalized() * speed * delta * minf(move.length(), 1.0)
		_clamp_to_bounds()

	if not is_equal_approx(zoom, _target_zoom):
		zoom = lerpf(zoom, _target_zoom, 1.0 - exp(-zoom_smoothing * delta))
		if absf(zoom - _target_zoom) < 0.001:
			zoom = _target_zoom
		_apply_zoom()


## Smoothly moves the pivot to a world position, e.g. the Hub or the hero.
func focus_on(world_position: Vector3) -> void:
	_cancel_focus()
	var target := Vector3(world_position.x, position.y, world_position.z)
	_focus_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_focus_tween.tween_property(self, "position", target, focus_duration)


func get_distance() -> float:
	return lerpf(distance_min, distance_max, zoom)


func get_pitch_degrees() -> float:
	return lerpf(pitch_near, pitch_far, zoom)


func _keyboard_pan() -> Vector2:
	var pan := Input.get_vector("camera_pan_left", "camera_pan_right", "camera_pan_up", "camera_pan_down")
	# W A S D double as build-grid keys, so they only pan while Shift is held.
	if Input.is_action_pressed("modifier_additive"):
		pan += Input.get_vector("camera_shift_pan_left", "camera_shift_pan_right", "camera_shift_pan_up", "camera_shift_pan_down")
	return pan.limit_length(1.0)


func _edge_pan() -> Vector2:
	if not edge_scroll_enabled or _rotating:
		return Vector2.ZERO
	var viewport := get_viewport()
	if viewport == null or DisplayServer.get_name() == "headless":
		return Vector2.ZERO
	if not DisplayServer.window_is_focused():
		return Vector2.ZERO
	var size := viewport.get_visible_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return Vector2.ZERO
	var m := viewport.get_mouse_position() / size
	if m.x < 0.0 or m.y < 0.0 or m.x > 1.0 or m.y > 1.0:
		return Vector2.ZERO
	var out := Vector2.ZERO
	if m.x < edge_scroll_margin:
		out.x = -1.0
	elif m.x > 1.0 - edge_scroll_margin:
		out.x = 1.0
	if m.y < edge_scroll_margin:
		out.y = -1.0
	elif m.y > 1.0 - edge_scroll_margin:
		out.y = 1.0
	return out


func _apply_zoom() -> void:
	if camera == null:
		return
	var pitch := deg_to_rad(get_pitch_degrees())
	var distance := get_distance()
	camera.position = Vector3(0.0, sin(pitch) * distance, cos(pitch) * distance)
	camera.rotation = Vector3(-pitch, 0.0, 0.0)
	camera.fov = lerpf(fov_near, fov_far, zoom)


func _clamp_to_bounds() -> void:
	position.x = clampf(position.x, bounds.position.x, bounds.end.x)
	position.z = clampf(position.z, bounds.position.y, bounds.end.y)


func _cancel_focus() -> void:
	if _focus_tween and _focus_tween.is_valid():
		_focus_tween.kill()
