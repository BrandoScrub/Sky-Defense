## The build menu in the bottom-left corner: a row of tabs (Army, Defense,
## Economy, Storm) above a 3 x 3 grid of buttons. Clicking a button does the
## same thing as its hotkey, which is shown in the button's corner. Tab cycles
## the tabs. Pressing a hotkey also jumps to the tab that holds it.
class_name BuildMenu
extends PanelContainer

const COLUMNS := 3
const SLOTS := 9
const BUTTON_SIZE := Vector2(120, 72)

## Tab name -> entries. An entry is either a building type id from
## BuildingCatalog, or one of the special actions "walkway" and "recruit".
const TABS := {
	"Army": ["recruit"],
	"Defense": ["rivet_turret", "flak_battery", "arc_coil"],
	"Economy": ["dynamo", "walkway"],
	"Storm": ["harvester"],
}

const DEFAULT_HINT := "Del: demolish   G: start wave   P: pause   F1-F3: speed   Tab: next tab"

var building: BuildController
var walkways: WalkwayBuilder
var recruiter: Recruiter
var resources: PlayerResources

## Name of the tab being shown.
var current_tab := ""

var _tab_buttons := {}
var _grid: GridContainer
var _hint: Label
## Entry id -> Button, for the tab being shown.
var _entry_buttons := {}


func _init() -> void:
	name = "BuildMenu"
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	# Pin the panel's bottom edge 12 px above the screen's; it grows upward
	# to fit its contents.
	offset_left = 12
	offset_top = -12
	offset_bottom = -12

	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 6)
	add_child(box)

	var tabs := HBoxContainer.new()
	tabs.name = "Tabs"
	tabs.add_theme_constant_override("separation", 4)
	box.add_child(tabs)
	var group := ButtonGroup.new()
	for tab_name in TABS:
		var tab := Button.new()
		tab.name = tab_name
		tab.text = tab_name
		tab.toggle_mode = true
		tab.button_group = group
		tab.focus_mode = Control.FOCUS_NONE
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.pressed.connect(show_tab.bind(tab_name))
		tabs.add_child(tab)
		_tab_buttons[tab_name] = tab

	_grid = GridContainer.new()
	_grid.name = "Grid"
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	box.add_child(_grid)

	_hint = Label.new()
	_hint.name = "Hint"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size.x = BUTTON_SIZE.x * COLUMNS + 4 * (COLUMNS - 1)
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.modulate = Color(1, 1, 1, 0.8)
	box.add_child(_hint)
	set_hint("")

	if building:
		building.mode_changed.connect(_on_build_mode_changed)
	if walkways:
		walkways.mode_changed.connect(_on_walkway_mode_changed)
	if resources:
		resources.changed.connect(refresh)
	show_tab(TABS.keys()[0])


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("build_menu_next_tab"):
		var names: Array = TABS.keys()
		show_tab(names[(names.find(current_tab) + 1) % names.size()])
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("recruit_unit"):
		# The Recruiter handles the key itself; just show where it lives.
		show_tab(tab_of("recruit"))


func _process(_delta: float) -> void:
	# The training count changes over time, so keep the Recruit button live.
	if _entry_buttons.has("recruit"):
		_update_button("recruit")


## Shows the short instructions under the grid; "" shows the default keys.
func set_hint(text: String) -> void:
	if _hint:
		_hint.text = text if text != "" else DEFAULT_HINT


## The tab that holds an entry, or "" if none does.
static func tab_of(entry: String) -> String:
	for tab_name in TABS:
		if entry in TABS[tab_name]:
			return tab_name
	return ""


func show_tab(tab_name: String) -> void:
	if tab_name == current_tab or not TABS.has(tab_name):
		return
	current_tab = tab_name
	_tab_buttons[tab_name].set_pressed_no_signal(true)
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_entry_buttons.clear()
	var entries: Array = TABS[tab_name]
	for i in SLOTS:
		if i < entries.size():
			var button := _make_button(entries[i])
			_grid.add_child(button)
			_entry_buttons[entries[i]] = button
		else:
			var empty := Panel.new()
			empty.custom_minimum_size = BUTTON_SIZE
			empty.modulate = Color(1, 1, 1, 0.35)
			empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_grid.add_child(empty)
	refresh()


## Runs a button's action, exactly as its hotkey would.
func activate(entry: String) -> void:
	match entry:
		"walkway":
			if building:
				building.cancel_placing()
			if walkways.active:
				walkways.cancel()
			else:
				walkways.begin()
		"recruit":
			var problem := recruiter.queue_one()
			recruiter.notice.emit(problem if problem != "" else "Riveteer queued (%d in training)" % recruiter.queued)
		_:
			if walkways and walkways.active:
				walkways.cancel()
			if building.placing == entry:
				building.cancel_placing()
			else:
				building.start_placing(entry)
	refresh()


## Updates costs, affordability and which button is lit.
func refresh() -> void:
	for entry in _entry_buttons:
		_update_button(entry)


func _make_button(entry: String) -> Button:
	var button := Button.new()
	button.name = entry
	button.custom_minimum_size = BUTTON_SIZE
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_NONE
	button.clip_text = true
	button.add_theme_font_size_override("font_size", 13)
	button.pressed.connect(activate.bind(entry))

	var key := Label.new()
	key.name = "Key"
	key.text = _hotkey(entry)
	key.position = Vector2(6, 2)
	key.add_theme_font_size_override("font_size", 12)
	key.modulate = Color(1.0, 0.85, 0.45)
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(key)
	return button


func _update_button(entry: String) -> void:
	var button: Button = _entry_buttons[entry]
	var title := ""
	var cost := 0
	var details := ""
	var active := false
	match entry:
		"walkway":
			title = "Walkway"
			cost = SkyRegion.WALKWAY_COST_PER_TILE
			details = "Link one of your platforms to another.\nCosts %d scrap per tile." % cost
			active = walkways != null and walkways.active
		"recruit":
			title = "Riveteer"
			cost = recruiter.cost if recruiter else 0
			details = "Train a Riveteer at the Hub (%ds).\nUp to %d in the queue." % [int(recruiter.train_seconds), recruiter.max_queue]
			if recruiter and recruiter.queued > 0:
				title += " (%d)" % recruiter.queued
		_:
			var data := BuildingCatalog.get_data(entry)
			title = data.name
			cost = data.cost
			details = _building_details(data)
			active = building != null and building.placing == entry
	var per_tile := " / tile" if entry == "walkway" else ""
	button.text = "\n%s\n%d scrap%s" % [title, cost, per_tile]
	button.tooltip_text = "%s  [%s]\n%s" % [title, _hotkey(entry), details]
	button.set_pressed_no_signal(active)
	var affordable := resources == null or resources.scrap >= cost
	if active:
		button.modulate = Color(1.0, 0.85, 0.4)
	else:
		button.modulate = Color.WHITE if affordable else Color(1.0, 0.6, 0.6, 0.8)


func _building_details(data: Dictionary) -> String:
	var lines := PackedStringArray()
	if data.power > 0:
		var extra := " (%d on a generator socket)" % data.power_on_socket if data.has("power_on_socket") else ""
		lines.append("Makes %d power%s" % [data.power, extra])
	elif data.power < 0:
		lines.append("Uses %d power" % -data.power)
	lines.append("Weight %d" % data.weight)
	if data.has("attack"):
		var attack: Dictionary = data.attack
		lines.append("Damage %d, range %d" % [int(attack.damage), int(attack.range)])
	var tiles := PackedStringArray()
	for t in data.tiles:
		tiles.append(String(t).replace("_", " "))
	lines.append("Goes on: " + ", ".join(tiles))
	return "\n".join(lines)


func _hotkey(entry: String) -> String:
	match entry:
		"walkway":
			return "T"
		"recruit":
			return "Y"
	var i := BuildingCatalog.HOTKEY_ORDER.find(entry)
	return BuildingCatalog.HOTKEY_LABELS[i] if i >= 0 else ""


func _on_build_mode_changed(type_id: String) -> void:
	if type_id != "":
		show_tab(tab_of(type_id))
	refresh()


func _on_walkway_mode_changed(active: bool) -> void:
	if active:
		show_tab(tab_of("walkway"))
	refresh()
