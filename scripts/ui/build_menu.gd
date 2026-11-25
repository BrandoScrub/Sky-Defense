## The build panel in the bottom-left corner. Tabs along the top pick a
## category (Army, Defense, Economy, Storm); Tab cycles them. Below is a grid
## of buttons for that category. Click a button or press its hotkey
## (Z, X, C, V, B for slots 1 to 5) to build, recruit or lay a walkway.
class_name BuildMenu
extends PanelContainer

signal notice(text: String)

## Each item is a building id, "walkway" or "recruit".
const CATEGORIES := [
	{"name": "Army", "items": ["recruit"]},
	{"name": "Defense", "items": ["rivet_turret", "flak_battery", "arc_coil"]},
	{"name": "Economy", "items": ["dynamo", "walkway"]},
	{"name": "Storm", "items": ["harvester"]},
]
const SLOT_KEYS := ["Z", "X", "C", "V", "B"]
const SLOTS := 9
const COLUMNS := 3

## Short descriptions shown as button tooltips.
const BLURBS := {
	"recruit": "Train a Riveteer at the Hub. Riflemen who claim platforms and fight walkers.",
	"walkway": "Lay a metal walkway from one of your platforms to another (15 scrap per tile).",
	"dynamo": "Makes power for your towers. More on a yellow generator socket.",
	"harvester": "Taps a storm cloud from a blue anchor: lots of power, crystals, and storm control.",
	"rivet_turret": "All-round gun tower. Weak against aircraft.",
	"flak_battery": "Anti-air. Shreds Vesper bombers; weak against walkers.",
	"arc_coil": "Chain lightning that jumps between walkers. Power hungry; can't hit aircraft.",
}

var building: BuildController
var walkways: WalkwayBuilder
var recruiter: Recruiter
var resources: PlayerResources

var tab := 1
var _tab_buttons: Array[Button] = []
var _slot_buttons: Array[Button] = []


func _ready() -> void:
	name = "BuildMenu"
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	position = Vector2(16, -16)
	offset_left = 16
	offset_bottom = -16
	var box := VBoxContainer.new()
	add_child(box)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 2)
	box.add_child(tabs)
	for i in CATEGORIES.size():
		var b := Button.new()
		b.text = CATEGORIES[i].name
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(84, 30)
		b.pressed.connect(set_tab.bind(i))
		tabs.add_child(b)
		_tab_buttons.append(b)
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	box.add_child(grid)
	for i in SLOTS:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(112, 62)
		b.clip_text = true
		b.pressed.connect(activate.bind(i))
		grid.add_child(b)
		_slot_buttons.append(b)
	var hint := Label.new()
	hint.text = "Tab: next category"
	hint.add_theme_font_size_override("font_size", 13)
	hint.modulate = Color(1, 1, 1, 0.7)
	box.add_child(hint)
	if resources:
		resources.changed.connect(refresh)
	set_tab(tab)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("build_tab_next"):
		set_tab((tab + 1) % CATEGORIES.size())
		get_viewport().set_input_as_handled()
		return
	for i in SLOT_KEYS.size():
		if event.is_action_pressed("context_hotkey_%d" % (i + 1)):
			activate(i)
			get_viewport().set_input_as_handled()
			return


func set_tab(index: int) -> void:
	tab = index
	for i in _tab_buttons.size():
		_tab_buttons[i].button_pressed = i == tab
	refresh()


## Items in the current tab, slot by slot.
func items() -> Array:
	return CATEGORIES[tab].items


## Runs the item in a slot of the current tab. Returns false for an empty slot.
func activate(slot: int) -> bool:
	if slot >= items().size():
		return false
	var item: String = items()[slot]
	match item:
		"recruit":
			var problem := recruiter.queue_one()
			notice.emit(problem if problem != "" else "Riveteer queued (%d in training)" % recruiter.queued)
		"walkway":
			building.cancel_placing()
			walkways.begin()
		_:
			walkways.cancel()
			building.start_placing(item)
	refresh()
	return true


## Updates button labels, costs and which ones you can afford.
func refresh() -> void:
	if _slot_buttons.is_empty():
		return
	for i in SLOTS:
		var b := _slot_buttons[i]
		if i >= items().size():
			b.text = ""
			b.disabled = true
			b.tooltip_text = ""
			continue
		var item: String = items()[i]
		var key: String = SLOT_KEYS[i] if i < SLOT_KEYS.size() else ""
		var cost := 0
		var label := ""
		match item:
			"recruit":
				label = "Riveteer"
				cost = recruiter.cost if recruiter else 0
			"walkway":
				label = "Walkway"
				cost = SkyRegion.WALKWAY_COST_PER_TILE
			_:
				label = BuildingCatalog.get_data(item).name
				cost = BuildingCatalog.get_data(item).cost
		var per := "/tile" if item == "walkway" else ""
		b.text = "%s\n%s  %d%s" % [label, key, cost, per]
		b.disabled = false
		b.modulate = Color(1, 1, 1) if resources == null or resources.can_afford(cost) else Color(1, 0.6, 0.6)
		b.tooltip_text = BLURBS.get(item, "")
		b.button_pressed = false
		b.toggle_mode = true
		b.set_pressed_no_signal(building != null and building.placing == item or (item == "walkway" and walkways != null and walkways.active))
