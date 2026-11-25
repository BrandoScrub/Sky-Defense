## Developer tools, in a folded panel under the legend. These exist only to
## help build and test the game; put any new testing switch or cheat here.
## Click the "Debug" title to open or fold it.
class_name DebugPanel
extends PanelContainer

## Emitted when the panel opens or folds, so the HUD can re-fit its column.
signal resized_by_toggle

var fog: FogSystem
var resources: PlayerResources
var waves: WaveManager
var notice: Callable

var _toggle: Button
var _body: VBoxContainer
var _fog_check: CheckButton


func _init() -> void:
	name = "Debug"


func _ready() -> void:
	var outer := VBoxContainer.new()
	add_child(outer)
	_toggle = Button.new()
	_toggle.name = "Toggle"
	_toggle.flat = true
	_toggle.focus_mode = Control.FOCUS_NONE
	_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_toggle.tooltip_text = "Testing tools for developing the game"
	_toggle.pressed.connect(func(): set_open(not _body.visible))
	outer.add_child(_toggle)
	_body = VBoxContainer.new()
	_body.name = "Body"
	outer.add_child(_body)

	_fog_check = CheckButton.new()
	_fog_check.name = "Fog"
	_fog_check.text = "Fog of war"
	_fog_check.focus_mode = Control.FOCUS_NONE
	_fog_check.button_pressed = fog == null or fog.enabled
	_fog_check.toggled.connect(set_fog)
	_body.add_child(_fog_check)

	_add_button("+500 scrap", func():
		resources.add_scrap(500)
		_say("Debug: +500 scrap"))
	_add_button("+50 crystals", func():
		resources.add_crystals(50)
		_say("Debug: +50 crystals"))
	_add_button("Start next wave now", func():
		if waves.phase == WaveManager.BUILD:
			waves.start_wave()
			_say("Debug: wave %d started" % waves.wave)
		else:
			_say("Debug: a wave is already under way"))
	_add_button("Destroy all attackers", func():
		var n := 0
		for node in get_tree().get_nodes_in_group(Unit.ENEMY_GROUP):
			var u := node as Unit
			if u and u.is_alive():
				u.take_damage(u.hp + 1.0)
				n += 1
		_say("Debug: destroyed %d attackers" % n))
	set_open(false)


func _add_button(label: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(action)
	_body.add_child(b)
	return b


func set_open(open: bool) -> void:
	_body.visible = open
	_toggle.text = ("v  Debug" if open else ">  Debug")
	resized_by_toggle.emit()


func is_open() -> bool:
	return _body.visible


## Turns fog of war on or off.
func set_fog(on: bool) -> void:
	if fog:
		fog.set_enabled(on)
	_fog_check.set_pressed_no_signal(on)
	_say("Debug: fog of war " + ("on" if on else "off"))


func _say(text: String) -> void:
	if notice.is_valid():
		notice.call(text)
