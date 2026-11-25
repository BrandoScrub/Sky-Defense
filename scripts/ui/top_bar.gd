## The bar along the top of the screen. On the left it shows your resources
## (scrap, power, crystals and the weight on your platforms). On the right it
## has one card per rival corporation with a countdown to its next wave.
## Hover a rival's card to see what that wave will send: each unit type and
## how many. The contents come from WaveManager.wave_plan(), so new unit types
## and airships show up here without changes to this file.
class_name TopBar
extends PanelContainer

const HEIGHT := 44.0

## Colour swatch for each rival corp's card (matches the platform colours).
const CORP_COLORS := {
	"Ironbell": "rival",
	"Vesper": "vesper",
}

var region: SkyRegion
var resources: PlayerResources
var waves: WaveManager
## Optional: shows next round's income next to scrap and crystals.
var economy: EconomySystem

var _scrap: Label
var _power: Label
var _crystals: Label
var _weight: Label
var _rivals: HBoxContainer
## corp -> {"card": PanelContainer, "status": Label}
var _cards := {}


func _init() -> void:
	name = "TopBar"
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	offset_bottom = HEIGHT
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12, 0.85)
	style.border_color = Color(0.75, 0.6, 0.3, 0.8)
	style.border_width_bottom = 2
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 20)
	add_child(row)

	var res := HBoxContainer.new()
	res.name = "Resources"
	res.add_theme_constant_override("separation", 22)
	row.add_child(res)
	_scrap = _stat(res, "Scrap", "Scrap: the main currency. Spend it on buildings, walkways and troops. Kills pay scrap on the spot; scrap heaps on your platforms pay at the end of each wave (shown as +N).")
	_power = _stat(res, "Power", "Power: used / made. Towers need power; if they use more than your generators and storms make, they brown out and slow down.")
	_crystals = _stat(res, "Crystals", "Crystals: an advanced resource. Your Cloud Harvesters pay crystals at the end of each wave (shown as +N).")
	_weight = _stat(res, "Weight", "Weight: load / capacity across all your platforms. Overloaded platforms sway, sag and drop buildings. Click a platform to see its own load.")

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

	_rivals = HBoxContainer.new()
	_rivals.name = "Rivals"
	_rivals.add_theme_constant_override("separation", 8)
	row.add_child(_rivals)
	refresh()


func _stat(parent: Control, stat_name: String, tip: String) -> Label:
	var label := Label.new()
	label.name = stat_name
	label.add_theme_font_size_override("font_size", 18)
	label.tooltip_text = tip
	# Labels ignore the mouse by default; this lets their tooltips show.
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(label)
	return label


func _process(_delta: float) -> void:
	refresh()


func refresh() -> void:
	if resources and region:
		var income := economy.round_income() if economy else {}
		_scrap.text = "Scrap %d" % resources.scrap + _income_text(income.get("scrap", 0))
		var supply := region.power_supply()
		var demand := region.power_demand()
		_power.text = "Power %d / %d" % [demand, supply]
		if demand > supply:
			_power.text += " (brownout: towers at %d%%)" % int(region.grid_efficiency() * 100)
		_power.modulate = Color(1.0, 0.55, 0.45) if demand > supply else Color.WHITE
		_crystals.text = "Crystals %d" % resources.crystals + _income_text(income.get("crystals", 0))
		var load := 0
		var capacity := 0
		for platform_name in region.platforms:
			if region.platform_owner(platform_name) == "player":
				load += region.platform_load(platform_name)
				capacity += region.platform_capacity(platform_name)
		_weight.text = "Weight %d / %d" % [load, capacity]
	if waves:
		_refresh_rivals()


## " (+N)" for next round's income, or "" when there is none.
static func _income_text(amount: int) -> String:
	return "  (+%d)" % amount if amount > 0 else ""


func _refresh_rivals() -> void:
	var plan := waves.wave_plan()
	for entry in plan:
		if not _cards.has(entry.corp):
			_add_card(entry.corp)
		var card: Dictionary = _cards[entry.corp]
		card.status.text = status_text(entry)
		card.card.tooltip_text = wave_tooltip(entry)
		card.card.modulate.a = 0.55 if entry.defeated else 1.0


## The one-line status under a rival's name.
func status_text(entry: Dictionary) -> String:
	if entry.defeated:
		return "Defeated"
	match waves.phase:
		WaveManager.BUILD:
			if entry.units.is_empty():
				return "Wave %d: sits it out" % waves.wave
			return "Wave %d in %s" % [waves.wave, clock(waves.time_left)]
		WaveManager.WAVE:
			var left := waves.remaining_for(entry.corp)
			return "Attacking: %d left" % left if left > 0 else "Waiting for next wave"
	return ""


## Hover text listing what a rival's wave sends.
func wave_tooltip(entry: Dictionary) -> String:
	if entry.defeated:
		return "%s is defeated. Its headquarters has fallen." % entry.corp
	var attacking := waves.phase == WaveManager.WAVE
	var lines := PackedStringArray()
	lines.append("%s, wave %d%s:" % [entry.corp, waves.wave, " (attacking now)" if attacking else ""])
	if entry.units.is_empty():
		lines.append("  Nothing this wave")
	for u in entry.units:
		lines.append("  %d x %s" % [u[1], u[0]])
	var bonus := waves.health_bonus()
	if bonus > 0.005 and not entry.units.is_empty():
		lines.append("Health +%d%%" % roundi(bonus * 100))
	return "\n".join(lines)


func _add_card(corp: String) -> void:
	var card := PanelContainer.new()
	card.name = corp
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	var swatch := ColorRect.new()
	var c: Color = SkyRegion.COLORS.get(CORP_COLORS.get(corp, "rival"), Color.DARK_RED)
	swatch.color = Color(c.r, c.g, c.b)
	swatch.custom_minimum_size = Vector2(6, 0)
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(swatch)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", -4)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	var title := Label.new()
	title.text = corp
	title.add_theme_font_size_override("font_size", 14)
	text.add_child(title)
	var status := Label.new()
	status.add_theme_font_size_override("font_size", 12)
	status.modulate = Color(1.0, 0.85, 0.45)
	text.add_child(status)
	_rivals.add_child(card)
	_cards[corp] = {"card": card, "status": status}


## Seconds as m:ss.
static func clock(seconds: float) -> String:
	var s := maxi(ceili(seconds), 0)
	return "%d:%02d" % [s / 60, s % 60]
