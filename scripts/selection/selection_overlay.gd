## Draws the drag-selection box on screen.
class_name SelectionOverlay
extends Control

const FILL := Color(0.4, 1.0, 0.55, 0.12)
const EDGE := Color(0.4, 1.0, 0.55, 0.9)

var _rect := Rect2()
var _visible_box := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_box(rect: Rect2) -> void:
	_rect = rect
	_visible_box = true
	queue_redraw()


func hide_box() -> void:
	_visible_box = false
	queue_redraw()


func _draw() -> void:
	if not _visible_box:
		return
	draw_rect(_rect, FILL, true)
	draw_rect(_rect, EDGE, false, 1.5)
