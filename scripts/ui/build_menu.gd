## The build menu in the bottom-left corner: a row of tabs (Army, Defense,
## Economy, Storm, Ships) above a 4 x 4 command grid, like a classic RTS. Each grid
## slot has a fixed key that matches its place on the keyboard:
##   Q W E R
##   A S D F
##   Z X C V
##   T G B N
## What a slot does depends on the tab, so Q is a Rivet Turret on the Defense
## tab and a Dynamo on the Economy tab. On the Defense tab each row is one
## role: ground defenses on Q W E R, flak on A S D F, hangars on Z X C V. Tab cycles the tabs. Keys pressed with
## Shift, Ctrl or Alt are left alone (Shift + W A S D pans the camera).
class_name BuildMenu
extends PanelContainer

const COLUMNS := 4
const SLOTS := 16
const BUTTON_SIZE := Vector2(100, 64)
## The key for each slot, left to right and top to bottom. The real bindings
## are the grid_slot_1 to grid_slot_16 actions in tools/input_bindings.gd.
const SLOT_KEYS := ["Q", "W", "E", "R", "A", "S", "D", "F", "Z", "X", "C", "V", "T", "G", "B", "N"]

## Tab name -> what is in each slot, in slot order ("" leaves a slot empty).
## An entry is a building type id from BuildingCatalog, the special action
## "walkway", or "unit:<id>" to train a unit from UnitCatalog.
const TABS := {
	"Army": ["unit:riveteer", "unit:shieldbearer", "unit:rifleman", "unit:sapper", "unit:lancer", "unit:medic"],
	"Defense": [
		"rivet_turret", "arc_coil", "rally_horn", "mending_post",
		"flak_battery", "skyhook_cannon", "", "",
		"drone_hangar",
	],
	"Economy": ["dynamo", "walkway"],
	"Storm": ["harvester"],
	# Turbine Engines, and the order to steer a turbine island with 4 of them.
	"Ships": ["turbine_engine", "steer"],
}

const DEFAULT_HINT := "Tab: next tab   Shift + WASD: move camera   Del: demolish   Space: start wave   P: pause   F1-F3: speed"

var building: BuildController
var walkways: WalkwayBuilder
var steering: IslandSteering
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
	if steering:
		steering.mode_changed.connect(func(_a): refresh())
	if resources:
		resources.changed.connect(refresh)
	show_tab(TABS.keys()[0])


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("build_menu_next_tab"):
		var names: Array = TABS.keys()
		show_tab(names[(names.find(current_tab) + 1) % names.size()])
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.shift_pressed or event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
		return
	# While placing, R rotates the building instead.
	if building and building.placing != "" and event.is_action_pressed("building_rotate"):
		return
	for i in SLOTS:
		if event.is_action_pressed("grid_slot_%d" % (i + 1)):
			var entry := entry_at(current_tab, i)
			if entry != "":
				activate(entry)
			get_viewport().set_input_as_handled()
			return


## What is in a slot of a tab, or "" if the slot is empty.
static func entry_at(tab_name: String, slot: int) -> String:
	var entries: Array = TABS[tab_name]
	return entries[slot] if slot < entries.size() else ""


func _process(_delta: float) -> void:
	# The training counts change over time, so keep the Army buttons live.
	if current_tab == "Army":
		for entry in _entry_buttons:
			_update_button(entry)


## Shows the short instructions under the grid; "" shows the default keys.
func set_hint(text: String) -> void:
	if _hint:
		_hint.text = text if text != "" else DEFAULT_HINT


## The tab that holds an entry, or "" if none does.
static func tab_of(entry: String) -> String:
	for tab_name in TABS:
		if entry != "" and entry in TABS[tab_name]:
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
	for i in SLOTS:
		var entry := entry_at(tab_name, i)
		if entry != "":
			var button := _make_button(entry, SLOT_KEYS[i])
			_grid.add_child(button)
			_entry_buttons[entry] = button
		else:
			var empty := Panel.new()
			empty.custom_minimum_size = BUTTON_SIZE
			empty.modulate = Color(1, 1, 1, 0.35)
			empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var key := _key_label(SLOT_KEYS[i])
			key.modulate.a = 0.5
			empty.add_child(key)
			_grid.add_child(empty)
	refresh()


## Runs a button's action, exactly as its hotkey would.
func activate(entry: String) -> void:
	if entry.begins_with("unit:"):
		var type_id := entry.trim_prefix("unit:")
		var problem := recruiter.queue_one(type_id)
		var unit_name: String = UnitCatalog.get_data(type_id).name
		recruiter.notice.emit(problem if problem != "" else "%s queued (%d in training)" % [unit_name, recruiter.queued])
		refresh()
		return
	match entry:
		"walkway":
			if building:
				building.cancel_placing()
			if steering and steering.active:
				steering.cancel()
			if walkways.active:
				walkways.cancel()
			else:
				walkways.begin()
		"steer":
			if building:
				building.cancel_placing()
			if walkways and walkways.active:
				walkways.cancel()
			if steering:
				if steering.active:
					steering.cancel()
				else:
					steering.begin()
		_:
			if walkways and walkways.active:
				walkways.cancel()
			if steering and steering.active:
				steering.cancel()
			if building.placing == entry:
				building.cancel_placing()
			else:
				building.start_placing(entry)
	refresh()


## Updates costs, affordability and which button is lit.
func refresh() -> void:
	for entry in _entry_buttons:
		_update_button(entry)


func _make_button(entry: String, key_text: String) -> Button:
	var button := Button.new()
	button.name = entry
	button.custom_minimum_size = BUTTON_SIZE
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_NONE
	button.clip_text = true
	button.add_theme_font_size_override("font_size", 13)
	button.pressed.connect(activate.bind(entry))

	button.add_child(_key_label(key_text))
	return button


func _key_label(key_text: String) -> Label:
	var key := Label.new()
	key.name = "Key"
	key.text = key_text
	key.position = Vector2(6, 2)
	key.add_theme_font_size_override("font_size", 12)
	key.modulate = Color(1.0, 0.85, 0.45)
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return key


func _update_button(entry: String) -> void:
	var button: Button = _entry_buttons[entry]
	var title := ""
	var cost := 0
	var details := ""
	var active := false
	if entry.begins_with("unit:"):
		var type_id := entry.trim_prefix("unit:")
		var unit := UnitCatalog.get_data(type_id)
		title = unit.name
		cost = unit.cost
		details = "Train at the Hub (%ds). Up to %d in the queue.\n%s\n%s" % [int(unit.train_seconds), recruiter.max_queue if recruiter else 0, _unit_stats(unit), unit.blurb]
		if recruiter and recruiter.queued_of(type_id) > 0:
			title += " (%d)" % recruiter.queued_of(type_id)
	else:
		match entry:
			"walkway":
				title = "Walkway"
				cost = SkyRegion.WALKWAY_COST_PER_TILE
				details = "Link one of your platforms to another.\nCosts %d scrap per tile." % cost
				active = walkways != null and walkways.active
			"steer":
				title = "Steer Island"
				details = "Move one of your turbine islands with %d Turbine Engines up to %d hexes.\nClick the island, then open sky in the direction to go.\nIts walkways break off after a %d second warning.\nDraws %d power while it moves." % [IslandSteering.ENGINES_NEEDED, IslandSteering.MAX_HEXES, 6, IslandSteering.STEER_POWER]
				active = steering != null and steering.active
			_:
				var data := BuildingCatalog.get_data(entry)
				title = data.name
				cost = data.cost
				details = _building_details(data)
				active = building != null and building.placing == entry
	var per_tile := " / tile" if entry == "walkway" else ""
	button.text = "\n%s\n%d scrap%s" % [title, cost, per_tile]
	if entry == "steer":
		button.text = "\n%s\n%d power" % [title, IslandSteering.STEER_POWER]
	button.tooltip_text = "%s  [%s]\n%s" % [title, _hotkey(entry), details]
	button.set_pressed_no_signal(active)
	var affordable := resources == null or resources.scrap >= cost
	if active:
		button.modulate = Color(1.0, 0.85, 0.4)
	else:
		button.modulate = Color.WHITE if affordable else Color(1.0, 0.6, 0.6, 0.8)


func _unit_stats(unit: Dictionary) -> String:
	var parts := PackedStringArray(["Health %d" % int(unit.hp)])
	if unit.heal > 0.0:
		parts.append("Heals %d/s" % int(unit.heal))
	else:
		parts.append("Damage %d, range %s" % [int(unit.damage), str(unit.range)])
	if unit.shield > 0.0:
		parts.append("Shield blocks %d%%" % int(unit.shield * 100))
	if unit.vs_armor > 1.0:
		parts.append("x%s vs armor" % str(unit.vs_armor))
	if unit.repair > 0.0:
		parts.append("Repairs %d/s" % int(unit.repair))
	return ", ".join(parts)


func _building_details(data: Dictionary) -> String:
	var lines := PackedStringArray()
	if data.power > 0:
		var extra := " (%d on a generator socket)" % data.power_on_socket if data.has("power_on_socket") else ""
		lines.append("Makes %d power%s" % [data.power, extra])
	elif data.power < 0:
		lines.append("Uses %d power" % -data.power)
	lines.append("Weight %d" % data.weight)
	if data.has("role"):
		lines.append(BuildingCatalog.ROLES[data.role])
	lines.append_array(BuildMenu.defense_lines(data))
	var tiles := PackedStringArray()
	for t in data.tiles:
		tiles.append(String(t).replace("_", " "))
	lines.append("Goes on: " + ", ".join(tiles) + (" (%s islands only)" % data.island_style if data.has("island_style") else ""))
	if data.has("island_style"):
		lines.append("%d on one island let you steer it (Steer Island)" % IslandSteering.ENGINES_NEEDED)
	return "\n".join(lines)


## Short stat lines for a defense's attack, aura and drones. Shared with
## the info card.
static func defense_lines(data: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	if data.has("attack"):
		var attack: Dictionary = data.attack
		if attack.get("air_only", false):
			lines.append("Anti-air damage %d, range %d" % [int(attack.air), int(attack.range)])
		else:
			lines.append("Damage %d, range %d" % [int(attack.damage), int(attack.range)])
	if data.has("aura"):
		var aura: Dictionary = data.aura
		var parts := PackedStringArray()
		if aura.has("damage_mult"):
			parts.append("+%d%% damage" % roundi((aura.damage_mult - 1.0) * 100))
		if aura.has("cooldown_mult"):
			parts.append("+%d%% fire rate" % roundi((1.0 / aura.cooldown_mult - 1.0) * 100))
		if aura.has("armor"):
			parts.append("%d%% armor" % roundi(aura.armor * 100))
		if aura.has("heal"):
			parts.append("heals %d/s" % int(aura.heal))
		lines.append("Allies within %d: %s" % [int(aura.radius), ", ".join(parts)])
	if data.has("hangar"):
		var h: Dictionary = data.hangar
		lines.append("%d drones, one rebuilt every %ds, patrol range %d" % [int(h.drones), int(h.rebuild), int(h.leash)])
	return lines


## The key for an entry on its own tab.
func _hotkey(entry: String) -> String:
	var tab_name := tab_of(entry)
	return SLOT_KEYS[TABS[tab_name].find(entry)] if tab_name != "" else ""


func _on_build_mode_changed(type_id: String) -> void:
	if type_id != "":
		show_tab(tab_of(type_id))
	refresh()


func _on_walkway_mode_changed(active: bool) -> void:
	if active:
		show_tab(tab_of("walkway"))
	refresh()
