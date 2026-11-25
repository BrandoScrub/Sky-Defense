## Top-of-screen wind readout: a small compass with an arrow showing which
## way the wind blows (turned to match the camera), the direction it comes
## from, and how many waves until it turns. Flashes when the wind changes.
class_name WindVane
extends HBoxContainer

const DIAL := 44.0

var wind: WindSystem
var waves: WaveManager
var camera: RtsCamera

var _dial: Control
var _label: Label
var _flash := 0.0


func _ready() -> void:
	name = "WindVane"
	add_theme_constant_override("separation", 8)
	_dial = Control.new()
	_dial.custom_minimum_size = Vector2(DIAL, DIAL)
	_dial.draw.connect(_draw_dial)
	add_child(_dial)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(_label)
	tooltip_text = "Vesper's airships attack from upwind. The wind turns every %d waves." % (wind.shift_every if wind else 3)
	if wind:
		wind.wind_changed.connect(func(_i, first): if not first: _flash = 4.0)


func _process(delta: float) -> void:
	if wind == null:
		return
	_flash = maxf(0.0, _flash - delta)
	var left := wind.waves_until_shift(waves.wave) if waves else wind.shift_every
	_label.text = "Wind from the %s\nTurns in %d wave%s" % [wind.from_name(), left, "" if left == 1 else "s"]
	if _flash > 0.0:
		_label.text = "Wind turned! From the %s\nAirship routes changed" % wind.from_name()
	var pulse := 0.5 + 0.5 * sin(_flash * 10.0)
	_label.modulate = Color(1, 1, 1).lerp(Color(1.0, 0.85, 0.3), pulse if _flash > 0.0 else 0.0)
	_dial.queue_redraw()


## Screen direction the wind blows toward, taking the camera's turn into account.
func screen_direction() -> Vector2:
	var blow := wind.blowing()
	if camera and camera.camera:
		var at := camera.position
		var a := camera.camera.unproject_position(at)
		var b := camera.camera.unproject_position(at + blow * 10.0)
		if a.distance_to(b) > 0.01:
			return (b - a).normalized()
	return Vector2(blow.x, blow.z).normalized()


func _draw_dial() -> void:
	var c := Vector2(DIAL, DIAL) / 2.0
	var r := DIAL / 2.0 - 2.0
	_dial.draw_circle(c, r, Color(0.08, 0.1, 0.14, 0.75))
	_dial.draw_arc(c, r, 0, TAU, 32, Color(0.85, 0.7, 0.4), 2.0)
	if wind == null:
		return
	var d := screen_direction()
	var tail := c - d * (r - 6)
	var tip := c + d * (r - 5)
	var col := Color(0.6, 0.85, 1.0) if _flash <= 0.0 else Color(1.0, 0.85, 0.3)
	_dial.draw_line(tail, tip, col, 3.0)
	var side := Vector2(-d.y, d.x)
	_dial.draw_colored_polygon(PackedVector2Array([tip + d * 2, tip - d * 9 + side * 6, tip - d * 9 - side * 6]), col)
