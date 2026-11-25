## Root of the prototype scene. Spawns the starting units on the Hub, sets up
## selection and build mode, and runs the HUD.
extends Node3D

const SQUAD_SIZE := 4
## Seconds before a fallen Commander is back on the Hub.
const HERO_RESPAWN_SECONDS := 15.0

const HOW_TO_PLAY := """How to play
Goal: destroy every rival HQ before they destroy your Hub.
Ironbell bridges its way to you and walks; Vesper flies bombers.

1. Islands start unconnected. Build walkways (Economy, W) from a platform you
   own to reach new islands, then park units there to claim them. How you
   expand is up to you: the Foundry gives scrap, the Generator Rig power.
2. Ironbell's crews bridge one span at a time from its HQ toward your Hub
   (red-brown walkways), faster while a wave is out. Its walkers wait at the
   end of the bridge, then march in. Kills pay scrap.
3. Build during the build phase with the menu in the bottom left (Tab
   switches tabs). Rivet Turrets (Defense, Q) guard where the bridge lands.
   Dynamo Generators (Economy, Q) power them; watch the power number at the top.
4. From wave 2 Vesper bombers fly the red air lanes and bomb your buildings:
   Flak Batteries (Defense, W) shred them, Rivet Turrets only scratch them.
   From wave 3 Ironbell troop carriers drop squads onto your platforms (shoot
   them down first), and from wave 4 Vesper gunships hunt your units.
   Airships steer around islands and attack from upwind. The wind (top of
   the screen) turns every 3 waves: the air lanes move and balloon islands drift.
5. Put Cloud Harvesters (Storm, Q) on storm anchors. Hold more harvesters on a storm
   than Ironbell to get its power; if Ironbell holds it, lightning strikes.
6. Right click the Crystal Spire to send units there by airship ferry.
7. Keep platforms under their weight limit or they sag and shed buildings.
8. Dark storm clouds hide the sky you haven't scouted. Glowing islands hint
   at what's inside: crystal, generators, or a rival's HQ.

Click anything to see what it is and what it does."""

@onready var camera: RtsCamera = $RtsCamera
@onready var region: SkyRegion = $Region

var selection: SelectionController
var building: BuildController
var walkways: WalkwayBuilder
var capture: CaptureSystem
var raids: RivalRaids
var loads: LoadSystem
var economy: EconomySystem
var combat: CombatSystem
var defenses: DefenseSystem
var waves: WaveManager
var ferry: FerrySystem
var storms: StormSystem
var recruiter: Recruiter
var fleet: VesperFleet
var bridges: RivalBridges
var drift: DriftSystem
var fog: FogSystem
var wind: WindSystem
var steering: IslandSteering
var _phase_label: Label
var _banner: Label
var resources: PlayerResources
var _status: Label
var top_bar: TopBar
var payout_popup: PayoutPopup
var build_menu: BuildMenu
var info_panel: InfoPanel
var _notice: Label
var _notice_tween: Tween
var _help: PanelContainer
var _legend_entries: VBoxContainer
var _legend_toggle: Button
var _right_column: VBoxContainer
var debug_panel: DebugPanel
var _hero_respawn_left := 0.0
var _game_over := false


func _ready() -> void:
	camera.bounds = region.get_bounds()
	var backdrop := SkyBackdrop.new()
	backdrop.name = "SkyBackdrop"
	backdrop.area = region.get_bounds().grow(140.0)
	add_child(backdrop)
	camera.position = region.get_platform_position("Hub")
	# Balloon platforms join the map before the other systems look at it.
	drift = DriftSystem.new()
	drift.name = "DriftSystem"
	drift.region = region
	add_child(drift)
	_spawn_starting_units()

	selection = SelectionController.new()
	selection.name = "SelectionController"
	selection.camera = camera
	selection.region = region
	add_child(selection)

	resources = PlayerResources.new()
	resources.name = "PlayerResources"
	add_child(resources)

	# Added after selection so it sees mouse clicks first while placing.
	building = BuildController.new()
	building.name = "BuildController"
	building.region = region
	building.camera = camera
	building.resources = resources
	add_child(building)

	walkways = WalkwayBuilder.new()
	walkways.name = "WalkwayBuilder"
	walkways.region = region
	walkways.camera = camera
	walkways.resources = resources
	add_child(walkways)

	# Steering turbine islands with Turbine Engines (Ships tab).
	steering = IslandSteering.new()
	steering.name = "IslandSteering"
	steering.region = region
	steering.camera = camera
	steering.drift = drift
	add_child(steering)

	capture = CaptureSystem.new()
	capture.name = "CaptureSystem"
	capture.region = region
	add_child(capture)

	raids = RivalRaids.new()
	raids.name = "RivalRaids"
	raids.region = region
	raids.capture = capture
	add_child(raids)

	loads = LoadSystem.new()
	loads.name = "LoadSystem"
	loads.region = region
	add_child(loads)

	economy = EconomySystem.new()
	economy.name = "EconomySystem"
	economy.region = region
	economy.resources = resources
	add_child(economy)

	combat = CombatSystem.new()
	combat.name = "CombatSystem"
	combat.region = region
	combat.resources = resources
	combat.loads = loads
	add_child(combat)
	combat.spawn_headquarters()
	raids.combat = combat

	defenses = DefenseSystem.new()
	defenses.name = "DefenseSystem"
	defenses.region = region
	defenses.combat = combat
	add_child(defenses)

	fleet = VesperFleet.new()
	fleet.name = "VesperFleet"
	fleet.region = region
	fleet.combat = combat
	add_child(fleet)

	waves = WaveManager.new()
	waves.name = "WaveManager"
	waves.raids = raids
	waves.fleet = fleet
	waves.combat = combat
	add_child(waves)

	# The wind bends Vesper's air routes and turns every few waves.
	wind = WindSystem.new()
	wind.name = "WindSystem"
	wind.waves = waves
	add_child(wind)
	fleet.wind = wind
	# Balloon islands cast off only when the wind turns.
	drift.wind = wind

	bridges = RivalBridges.new()
	bridges.name = "RivalBridges"
	bridges.region = region
	bridges.waves = waves
	add_child(bridges)
	raids.bridges = bridges
	bridges.reached_player.connect(func(c, p): show_notice("%s's bridge reached %s: expect walkers!" % [c, p]))

	ferry = FerrySystem.new()
	ferry.name = "FerrySystem"
	ferry.region = region
	add_child(ferry)
	selection.ferry = ferry

	storms = StormSystem.new()
	storms.name = "StormSystem"
	storms.region = region
	storms.combat = combat
	storms.waves = waves
	add_child(storms)
	storms.control_changed.connect(_on_storm_control_changed)
	storms.rival_harvester_built.connect(func(p): show_notice("Ironbell built a Cloud Harvester on %s" % p))

	recruiter = Recruiter.new()
	recruiter.name = "Recruiter"
	recruiter.region = region
	recruiter.resources = resources
	recruiter.units_root = get_node("Units")
	add_child(recruiter)
	recruiter.notice.connect(show_notice)
	recruiter.recruited.connect(func(u: Unit): show_notice("A %s is ready on the Hub" % u.display_name))

	fog = FogSystem.new()
	fog.name = "FogSystem"
	fog.region = region
	fog.ferry = ferry
	add_child(fog)

	_build_hud()
	selection.selection_changed.connect(_on_selection_changed)
	_on_selection_changed(selection.selected)
	resources.changed.connect(_refresh_resources)
	region.buildings_changed.connect(_refresh_resources)
	building.notice.connect(show_notice)
	building.mode_changed.connect(_on_build_mode_changed)
	walkways.notice.connect(show_notice)
	steering.notice.connect(show_notice)
	steering.mode_changed.connect(func(on): build_menu.set_hint("Steer Island: click your turbine island, then open sky in the direction to go. Esc or right click: cancel." if on else ""))
	steering.steering_started.connect(func(_p, _n): _refresh_resources())
	steering.arrived.connect(func(_p): _refresh_resources())
	walkways.mode_changed.connect(_on_walkway_mode_changed)
	capture.platform_claimed.connect(_on_platform_claimed)
	raids.raid_sent.connect(func(n): show_notice("Wave %d: Ironbell sent %d walkers toward your Hub" % [waves.wave, n]))
	combat.building_destroyed.connect(func(n, f): show_notice(("Your %s was destroyed" if f == "player" else "Destroyed Ironbell's %s") % n))
	waves.game_over.connect(_on_game_over)
	waves.rival_defeated.connect(func(p): show_notice("%s has fallen! Its attacks stop" % p))
	fleet.flight_sent.connect(func(n): show_notice("Vesper bombers inbound: %d airship%s on the air lane" % [n, "" if n == 1 else "s"]))
	fleet.airships_launched.connect(_on_airships_launched)
	fleet.troops_dropped.connect(func(corp, p, units): show_notice("%s dropped %d troops on %s!" % [corp, units.size(), p]))
	ferry.departed.connect(_on_ferry_departed)
	loads.building_lost.connect(func(b, p): show_notice("%s is overloaded: a %s broke off and fell!" % [p, b]))
	economy.grid_changed.connect(func(_e): _refresh_resources())
	economy.watch(waves)
	wind.wind_changed.connect(func(_i, first):
		if not first:
			show_notice("The wind turned: it now blows from the %s. Vesper's air lanes have moved" % wind.from_name()))
	drift.warning_started.connect(_on_drift_warning)
	drift.cast_off.connect(_on_drift_cast_off)
	_refresh_resources()
	_on_build_mode_changed("")


func _on_storm_control_changed(cloud: String, controller: String) -> void:
	match controller:
		"player":
			show_notice("You control the %s: +%d power" % [cloud, storms.power_per_storm])
		"rival":
			show_notice("Ironbell controls the %s: expect lightning near it" % cloud)
		_:
			show_notice("Nobody controls the %s now" % cloud)
	_refresh_resources()


func _on_airships_launched(corp: String, kind: String, n: int) -> void:
	match kind:
		"carrier":
			show_notice("%s troop carriers inbound: %d airship%s, %d troops each" % [corp, n, "" if n == 1 else "s", VesperFleet.AIRSHIPS.carrier.troops.size()])
		"gunship":
			show_notice("%s gunships inbound: %d escort%s hunting your units" % [corp, n, "" if n == 1 else "s"])


func _on_ferry_departed(from_platform: String, to_platform: String, passengers: int) -> void:
	if passengers > 0:
		show_notice("Ferry left %s for %s with %d aboard" % [from_platform, to_platform, passengers])


func _on_drift_warning(balloon_name: String, platform_name: String, seconds: float, player_units: int) -> void:
	if player_units > 0:
		show_notice("%s casts off from %s in %ds: get your %d unit%s off the walkway!" % [
			balloon_name, platform_name, int(seconds), player_units, "" if player_units == 1 else "s"])
	else:
		show_notice("%s casts off from %s in %ds" % [balloon_name, platform_name, int(seconds)])


func _on_drift_cast_off(balloon_name: String, _platform_name: String, fallen: Array) -> void:
	var lost := fallen.filter(func(u): return u.faction == "player").size()
	if lost > 0:
		show_notice("%d of your unit%s fell when the %s cast off" % [lost, "" if lost == 1 else "s", balloon_name])


func _unhandled_input(event: InputEvent) -> void:
	if _game_over and event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		restart()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_legend") and _legend_entries:
		set_legend_open(not _legend_entries.visible)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("camera_focus_hub"):
		camera.focus_on(region.get_platform_position("Hub"))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("time_pause"):
		set_game_speed(0.0 if Engine.time_scale > 0.0 else 1.0)
	elif event.is_action_pressed("time_normal"):
		set_game_speed(1.0)
	elif event.is_action_pressed("time_double"):
		set_game_speed(2.0)
	elif event.is_action_pressed("time_triple"):
		set_game_speed(3.0)


## 0 pauses; 1, 2 and 3 are normal, double and triple speed.
func set_game_speed(speed: float) -> void:
	Engine.time_scale = speed
	show_notice("Paused" if speed == 0.0 else "Speed %dx" % int(speed))


## Starts a fresh game.
func restart() -> void:
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()


func _process(delta: float) -> void:
	if _hero_respawn_left > 0.0:
		_hero_respawn_left -= delta
		if _hero_respawn_left <= 0.0:
			_spawn_hero()
			show_notice("The Commander is back on the Hub")
	if _phase_label == null or waves == null:
		return
	match waves.phase:
		WaveManager.BUILD:
			_phase_label.text = "Build phase: wave %d in %ds (Space to start now)" % [waves.wave, ceili(waves.time_left)]
		WaveManager.WAVE:
			_phase_label.text = "Wave %d: %d attackers left" % [waves.wave, waves.remaining()]
		_:
			_phase_label.text = ""
	if recruiter and recruiter.queued > 0:
		_phase_label.text += "   Training %d (%ds)" % [recruiter.queued, ceili(recruiter.time_left)]
	if _hero_respawn_left > 0.0:
		_phase_label.text += "   Commander back in %ds" % ceili(_hero_respawn_left)
	if Engine.time_scale != 1.0:
		_phase_label.text += "   [%s]" % ("Paused" if Engine.time_scale == 0.0 else "%dx" % int(Engine.time_scale))


func _on_game_over(won: bool) -> void:
	_game_over = true
	_banner.text = ("Victory! Ironbell and Vesper are grounded." if won else "Defeat. Your Hub has fallen.") + "\nPress Enter to play again"
	_banner.modulate = Color(1.0, 0.85, 0.4) if won else Color(1.0, 0.4, 0.35)
	_banner.visible = true


func _spawn_starting_units() -> void:
	var units := Node3D.new()
	units.name = "Units"
	add_child(units)
	var hub_hex := region.hex_at(region.get_platform_position("Hub"))
	_spawn_hero()

	var spots: Array[Vector2i] = [Vector2i(-1, 2), Vector2i(0, 2), Vector2i(1, 1), Vector2i(-1, 1)]
	for i in SQUAD_SIZE:
		var r := UnitCatalog.make("riveteer")
		r.name = "Riveteer%d" % (i + 1)
		r.position = region.hex_center(hub_hex + spots[i % spots.size()])
		units.add_child(r)


## Puts the Commander (the hero) on the Hub. When they fall, they come back
## after HERO_RESPAWN_SECONDS.
func _spawn_hero() -> Unit:
	var hero := Unit.new()
	hero.name = "Commander"
	hero.display_name = "Commander"
	hero.is_hero = true
	hero.move_speed = 7.0
	hero.weight = 2
	hero.max_hp = 220.0
	hero.damage = 18.0
	hero.attack_range = 6.0
	hero.hits_air = true
	hero.body_color = Color(0.85, 0.65, 0.3)
	# Start just south of the Hub's core, on open deck tiles.
	var hub_hex := region.hex_at(region.get_platform_position("Hub"))
	hero.position = region.snap_to_walkable(region.hex_center(hub_hex + Vector2i(0, 1)))
	get_node("Units").add_child(hero)
	hero.died.connect(_on_hero_died)
	return hero


## The how-to-play panel goes away once the first wave starts.
func _on_phase_changed(phase: String, _wave: int) -> void:
	if phase == WaveManager.WAVE and _help:
		_help.visible = false


func _on_hero_died(_hero: Unit) -> void:
	if _game_over:
		return
	_hero_respawn_left = HERO_RESPAWN_SECONDS
	show_notice("The Commander has fallen! Back in %d seconds" % int(HERO_RESPAWN_SECONDS))


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Hud"
	add_child(layer)
	_status = Label.new()
	_status.name = "Status"
	_status.position = Vector2(16, TopBar.HEIGHT + 10)
	_status.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_status.add_theme_constant_override("shadow_offset_x", 1)
	_status.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(_status)
	# Right-hand column: the legend with the Debug panel under it.
	_right_column = VBoxContainer.new()
	_right_column.name = "RightColumn"
	_right_column.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_right_column.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_right_column.offset_right = -16
	_right_column.offset_top = TopBar.HEIGHT + 10
	layer.add_child(_right_column)
	_right_column.add_child(_build_legend())
	debug_panel = DebugPanel.new()
	debug_panel.fog = fog
	debug_panel.resources = resources
	debug_panel.waves = waves
	debug_panel.notice = show_notice
	debug_panel.resized_by_toggle.connect(_fit_right_column)
	_right_column.add_child(debug_panel)

	top_bar = TopBar.new()
	top_bar.region = region
	top_bar.resources = resources
	top_bar.waves = waves
	top_bar.economy = economy
	layer.add_child(top_bar)

	payout_popup = PayoutPopup.new()
	layer.add_child(payout_popup)
	economy.paid_out.connect(payout_popup.show_income)

	build_menu = BuildMenu.new()
	build_menu.building = building
	build_menu.walkways = walkways
	build_menu.steering = steering
	build_menu.recruiter = recruiter
	build_menu.resources = resources
	layer.add_child(build_menu)

	info_panel = InfoPanel.new()
	info_panel.region = region
	info_panel.camera = camera
	info_panel.selection = selection
	info_panel.building = building
	info_panel.walkways = walkways
	info_panel.combat = combat
	info_panel.storms = storms
	info_panel.loads = loads
	info_panel.defenses = defenses
	info_panel.fog = fog
	info_panel.wind = wind
	layer.add_child(info_panel)

	var vane := WindVane.new()
	vane.wind = wind
	vane.waves = waves
	vane.camera = camera
	vane.set_anchors_preset(Control.PRESET_CENTER_TOP)
	vane.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vane.position.y = 78
	layer.add_child(vane)

	_notice = _hud_label("Notice", 18)
	_notice.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_notice.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_notice.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_notice.offset_top = -76
	_notice.offset_bottom = -48
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.modulate.a = 0.0
	layer.add_child(_notice)

	_phase_label = _hud_label("Phase", 18)
	_phase_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_phase_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_phase_label.position.y = TopBar.HEIGHT + 8
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(_phase_label)

	_help = PanelContainer.new()
	_help.name = "HowToPlay"
	# Top left, under the selection text, so it stays clear of the build menu.
	_help.position = Vector2(16, TopBar.HEIGHT + 90)
	var help_box := VBoxContainer.new()
	_help.add_child(help_box)
	var help_text := Label.new()
	help_text.text = HOW_TO_PLAY
	help_box.add_child(help_text)
	var got_it := Button.new()
	got_it.text = "Got it"
	got_it.pressed.connect(func(): _help.visible = false)
	help_box.add_child(got_it)
	layer.add_child(_help)
	waves.phase_changed.connect(_on_phase_changed)

	_banner = _hud_label("Banner", 48)
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.visible = false
	layer.add_child(_banner)


func _hud_label(node_name: String, font_size: int) -> Label:
	var label := Label.new()
	label.name = node_name
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	return label


## Shows a short message near the bottom of the screen that fades out.
func show_notice(text: String) -> void:
	_notice.text = text
	_notice.modulate.a = 1.0
	if _notice_tween and _notice_tween.is_valid():
		_notice_tween.kill()
	_notice_tween = create_tween()
	_notice_tween.tween_interval(1.5)
	_notice_tween.tween_property(_notice, "modulate:a", 0.0, 0.6)


func _refresh_resources() -> void:
	if top_bar:
		top_bar.refresh()


## The build menu's hint line shows how to place while a build mode is on.
func _on_build_mode_changed(type_id: String) -> void:
	if type_id != "":
		var data := BuildingCatalog.get_data(type_id)
		build_menu.set_hint("Placing %s (weight %d). Left click: place. Shift: keep placing. R: rotate. Esc or right click: cancel." % [data.name, data.weight])
	else:
		build_menu.set_hint("")


func _on_walkway_mode_changed(active: bool) -> void:
	if active:
		build_menu.set_hint("Walkway: click a tile on your platform, then a tile on another platform. Esc or right click: cancel.")
	else:
		build_menu.set_hint("")


func _on_platform_claimed(platform_name: String, new_owner: String) -> void:
	if new_owner == "player":
		show_notice("You claimed %s" % platform_name)
	else:
		show_notice("Ironbell claimed %s" % platform_name)


## Colour key for the placeholder tiles, top right. Click its title (or
## press L) to fold it away.
func _build_legend() -> Control:
	var panel := PanelContainer.new()
	panel.name = "Legend"
	var outer := VBoxContainer.new()
	panel.add_child(outer)
	var toggle := Button.new()
	toggle.name = "Toggle"
	toggle.flat = true
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.tooltip_text = "Show or hide the legend (L)"
	outer.add_child(toggle)
	var box := VBoxContainer.new()
	box.name = "Entries"
	outer.add_child(box)
	for entry in SkyRegion.LEGEND:
		var row := HBoxContainer.new()
		var swatch := ColorRect.new()
		var c: Color = SkyRegion.COLORS[entry[0]]
		swatch.color = Color(c.r, c.g, c.b)
		swatch.custom_minimum_size = Vector2(14, 14)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(swatch)
		var label := Label.new()
		label.text = entry[1]
		row.add_child(label)
		box.add_child(row)
	_legend_entries = box
	_legend_toggle = toggle
	toggle.pressed.connect(func(): set_legend_open(not box.visible))
	set_legend_open(true)
	return panel


## Shows or folds away the legend's list.
func set_legend_open(open: bool) -> void:
	_legend_entries.visible = open
	_legend_toggle.text = ("v  Legend" if open else ">  Legend")
	_fit_right_column()


## Shrinks the legend and Debug column to fit after either folds or opens.
func _fit_right_column() -> void:
	if _right_column == null:
		return
	# Zero the size: with the right edge pinned, the column then grows left and
	# down to exactly fit what is showing. Both panels match the wider one.
	_right_column.offset_left = _right_column.offset_right
	_right_column.offset_bottom = _right_column.offset_top


func _on_selection_changed(units: Array[Unit]) -> void:
	var help := "Left click or drag to select, right click to move, Alt + right click to attack-move.\nCtrl + A: all on screen   H: hero   Ctrl + 1-5: save group   1-5: recall group"
	if units.is_empty():
		_status.text = "Nothing selected\n" + help
		return
	var counts := {}
	for u in units:
		counts[u.display_name] = counts.get(u.display_name, 0) + 1
	var parts := PackedStringArray()
	for n in counts:
		parts.append("%s x%d" % [n, counts[n]] if counts[n] > 1 else n)
	_status.text = "Selected: " + ", ".join(parts) + "\n" + help
