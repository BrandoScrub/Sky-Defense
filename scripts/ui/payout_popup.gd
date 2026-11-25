## The "wave cleared" card that pops up near the top of the screen when a
## round's income is paid out (EconomySystem.paid_out). It lists where the
## income came from, then fades away after a few seconds.
class_name PayoutPopup
extends PanelContainer

const SHOW_SECONDS := 5.0

var _title: Label
var _lines: Label
var _tween: Tween


func _init() -> void:
	name = "PayoutPopup"
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	offset_top = TopBar.HEIGHT + 90
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12, 0.9)
	style.border_color = Color(0.75, 0.6, 0.3, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_title = Label.new()
	_title.name = "Title"
	_title.add_theme_font_size_override("font_size", 20)
	_title.modulate = Color(1.0, 0.85, 0.45)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_lines = Label.new()
	_lines.name = "Lines"
	_lines.add_theme_font_size_override("font_size", 16)
	_lines.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_lines)
	visible = false


## Shows a payout from EconomySystem.pay_round().
func show_income(income: Dictionary) -> void:
	var wave: int = income.get("wave", 0)
	_title.text = ("Wave %d cleared! Round income" % wave) if wave > 0 else "Round income"
	var lines := PackedStringArray()
	for source in income.get("sources", []):
		lines.append("%s from %s" % [source[1], source[0]])
	if lines.is_empty():
		lines.append("Nothing this round. Claim scrap heaps and build Cloud Harvesters to earn more.")
	_lines.text = "\n".join(lines)
	# Re-fit around the new text, centred.
	offset_left = 0
	offset_right = 0
	offset_bottom = offset_top
	visible = true
	modulate.a = 1.0
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_interval(SHOW_SECONDS)
	_tween.tween_property(self, "modulate:a", 0.0, 0.8)
	_tween.tween_callback(func(): visible = false)
