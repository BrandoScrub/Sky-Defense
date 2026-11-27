## Root of the prototype scene. Spawns the starting units on the Hub, sets up
## selection and build mode, and runs the HUD.
extends Node3D

const SQUAD_SIZE := 4
## Seconds before a fallen Commander is back on the Hub.
const HERO_RESPAWN_SECONDS := 15.0

## The how-to-play guide, one short card at a time (top left, under the
## selection line). Players page through with Next / Back, close it with x,
## and bring it back with the Tips button or the / key.
const TIPS := [
	"Welcome, Tycoon. Your charter is fresh and your rivals want it. Wreck every rival headquarters, or hold the Hub until the last wave.",
	"Left click or drag to select, right click to move. Alt + right click attacks on the way. H finds your Commander. Ctrl + 1-5 saves a squad, 1-5 calls it back.",
	"Islands start cut off. Lay a walkway (Industry, W) from an island you own, then park units on the far island to claim it. The Foundry has scrap, the Generator Rig has power.",
	"Ironbell's crews build a bridge toward you one span at a time, and their walkers wait at its end. Park units beside a span for 8 quiet seconds to cut it down.",
	"Rivet Turrets (Defense, Q) hold the spot where the bridge lands. Every tower needs spare power to build: add Dynamos (Industry, Q), best on gold generator sockets.",
	"From wave 3 Vesper bombers fly the red air lanes. Flak Batteries (Defense, A) shred them, ground guns can't. The wind turns every 3 waves and moves the lanes.",
	"Cloud Harvesters (Industry, R) sit on storm anchors. Outnumber a rival's harvesters to take the storm's power, or its lightning hits you. Crystals buy Hum powers.",
	"Every island can only lift so much: when it's full, a Lift Engine (Industry, E) carries 10 more. Each island you hold pays %d scrap a wave.",
	"Storm clouds hide the sky you haven't scouted, but glowing islands hint at what's inside. Click anything to learn what it is.",
]
## Width of the tips card, in pixels.
const TIPS_WIDTH := 360.0

@onready var camera: RtsCamera = $RtsCamera
@onready var region: SkyRegion = $Region

var selection: SelectionController
var building: BuildController
var walkways: WalkwayBuilder
var capture: CaptureSystem
## The first walking rival's raids (Ironbell); every one is in all_raids.
var raids: RivalRaids
## corp -> RivalRaids, one per rival that sends ground parties.
var all_raids := {}
var economy: EconomySystem
var combat: CombatSystem
var defenses: DefenseSystem
var waves: WaveManager
var storms: StormSystem
var recruiter: Recruiter
var fleet: VesperFleet
var bridges: RivalBridges
var drift: DriftSystem
var fog: FogSystem
var wind: WindSystem
var steering: IslandSteering
var patrols: AirPatrols
var powers: CompanyPowers
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
var _help_text: Label
var _help_page: Label
var _help_button: Button
var _tip := 0
var _legend_entries: VBoxContainer
var _legend_toggle: Button
var _right_column: VBoxContainer
var debug_panel: DebugPanel
var _hero_respawn_left := 0.0
var _game_over := false


func _ready() -> void:
	HudTheme.apply()
	camera.bounds = region.get_bounds()
	var backdrop := SkyBackdrop.new()
	backdrop.name = "SkyBackdrop"
	backdrop.area = region.get_bounds().grow(140.0)
	add_child(backdrop)
	# Start looking a little past the Hub toward the Foundry, the first
	# island worth claiming, so it isn't hidden under the command grid.
	var hub_at := region.get_platform_position("Hub")
	camera.position = hub_at
	if region.platforms.has("Foundry"):
		camera.position = hub_at.lerp(region.get_platform_position("Foundry"), 0.4)
	# Balloon platforms join the map before the other systems look at it.
	drift = DriftSystem.new()
	drift.name = "DriftSystem"
	drift.region = region
	add_child(drift)
	_spawn_starting_units()
	_place_starting_dynamo()

	selection = SelectionController.new()
	selection.name = "SelectionController"
	selection.camera = camera
	selection.region = region
	add_child(selection)

	resources = PlayerResources.new()
	resources.name = "PlayerResources"
	resources.scrap = Difficulty.get_data().scrap
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

	# Steering turbine islands with Turbine Engines (Industry tab).
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

	# One raiding-party driver per rival that walks (RivalCatalog).
	for corp in region.layout.paths:
		var data := RivalCatalog.get_data(corp)
		if data.get("party_mix", []).is_empty():
			continue
		var r := RivalRaids.new()
		r.name = "RivalRaids" if all_raids.is_empty() else "RivalRaids%s" % corp
		r.region = region
		r.capture = capture
		r.corp = corp
		r.rival_platform = data.hq
		r.party_mix.assign(data.party_mix)
		add_child(r)
		all_raids[corp] = r
		if raids == null:
			raids = r

	economy = EconomySystem.new()
	economy.name = "EconomySystem"
	economy.region = region
	economy.resources = resources
	add_child(economy)

	combat = CombatSystem.new()
	combat.name = "CombatSystem"
	combat.region = region
	combat.resources = resources
	add_child(combat)
	combat.spawn_headquarters()
	for r in all_raids.values():
		r.combat = combat

	# Your patrol airships (Army tab; hangars and masts on the Defense tab).
	patrols = AirPatrols.new()
	patrols.name = "AirPatrols"
	patrols.region = region
	patrols.combat = combat
	patrols.resources = resources
	patrols.camera = camera
	add_child(patrols)

	# Company powers, bought with crystals (Hum tab).
	powers = CompanyPowers.new()
	powers.name = "CompanyPowers"
	powers.resources = resources
	powers.combat = combat
	add_child(powers)

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
	waves.raids_by_corp = all_raids
	waves.corps = region.layout.paths.keys()
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
	for r in all_raids.values():
		r.bridges = bridges
	bridges.combat = combat
	waves.bridges = bridges
	bridges.cutting_started.connect(func(c): show_notice("Cutting %s's bridge. Hold your ground %d seconds" % [c, int(bridges.cut_seconds)]))
	bridges.span_cut.connect(func(c, _n): show_notice("%s's bridge is cut! Their crew must rebuild the span" % c))
	combat.headquarters_damaged.connect(_on_hq_damaged)
	bridges.reached_player.connect(func(c, p): show_notice("%s's bridge reached %s: expect walkers!" % [c, p]))


	storms = StormSystem.new()
	storms.name = "StormSystem"
	storms.region = region
	storms.combat = combat
	add_child(storms)
	storms.control_changed.connect(_on_storm_control_changed)
	storms.rival_harvester_built.connect(func(p): show_notice("A rival built a Cloud Harvester on %s" % p))

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
	patrols.notice.connect(show_notice)
	powers.notice.connect(show_notice)
	powers.changed.connect(build_menu.refresh)
	economy.grid_changed.connect(func(_e): build_menu.refresh())
	patrols.mode_changed.connect(func(on): build_menu.set_hint("Patrol route: click a Hangar, then Mooring Masts in order. Right click finishes, Esc cancels." if on else ""))
	patrols.ship_launched.connect(func(s): show_notice("%s cast off from the hangar" % s.display_name))
	region.buildings_changed.connect(patrols.mark_routes_dirty)
	steering.mode_changed.connect(func(on): build_menu.set_hint("Steer Island: click your turbine island, then open sky to head for. Esc or right click cancels." if on else ""))
	steering.steering_started.connect(func(_p, _n): _refresh_resources())
	steering.arrived.connect(func(_p): _refresh_resources())
	walkways.mode_changed.connect(_on_walkway_mode_changed)
	capture.platform_claimed.connect(_on_platform_claimed)
	for corp in all_raids:
		all_raids[corp].raid_sent.connect(func(n): show_notice(
			("Wave %d: %s sends %d raiders at your Hub" if waves.has_contact(corp)
			else "Wave %d: %s sends %d raiders to wait at its bridgehead") % [waves.wave, corp, n]))
	combat.building_destroyed.connect(func(n, f): show_notice(("We lost a %s" if f == "player" else "Rival %s wrecked") % n))
	waves.game_over.connect(_on_game_over)
	waves.rival_defeated.connect(func(p): show_notice("%s has fallen! Its attacks stop" % p))
	fleet.flight_sent.connect(func(n): show_notice("Vesper bombers inbound: %d on the air lane" % n))
	fleet.airships_launched.connect(_on_airships_launched)
	fleet.troops_dropped.connect(func(corp, p, units): show_notice("%s dropped %d troops on %s!" % [corp, units.size(), p]))
	economy.grid_changed.connect(func(_e): _refresh_resources())
	economy.watch(waves)
	wind.wind_changed.connect(func(_i, first):
		if not first:
			show_notice("The wind has turned and blows from the %s. Vesper's lanes have shifted" % wind.from_name()))
	drift.warning_started.connect(_on_drift_warning)
	drift.cast_off.connect(_on_drift_cast_off)
	_refresh_resources()
	_on_build_mode_changed("")


## The Hub is being hit: say so at most every few seconds, with its health.
var _hub_warned_msec := -100000

func _on_hq_damaged(faction: String, platform: String, _amount: float) -> void:
	if faction != "player" or _game_over:
		return
	var now := Time.get_ticks_msec()
	if now - _hub_warned_msec < 8000:
		return
	_hub_warned_msec = now
	var hq := combat.headquarters_on(platform)
	if hq:
		show_notice("The Hub is under fire! %d%% plating left" % roundi(100.0 * hq.hp / hq.max_hp))


func _on_storm_control_changed(cloud: String, controller: String) -> void:
	match controller:
		"player":
			show_notice("The %s is ours: +%d power" % [cloud, storms.power_per_storm])
		"rival":
			show_notice("A rival controls the %s: expect lightning near it" % cloud)
		_:
			show_notice("The %s answers to no one now" % cloud)
	_refresh_resources()


func _on_airships_launched(corp: String, kind: String, n: int) -> void:
	match kind:
		"carrier":
			show_notice("%s troop carriers inbound: %d airship%s, %d troops each" % [corp, n, "" if n == 1 else "s", VesperFleet.AIRSHIPS.carrier.troops.size()])
		"gunship":
			show_notice("%s gunships inbound: %d escort%s hunting your units" % [corp, n, "" if n == 1 else "s"])


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
	elif event.is_action_pressed("toggle_tips") and _help:
		set_tips_open(not _help.visible)
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
			_phase_label.text = "Wave %d%s inbound in %s  ·  Space to ring the alarm" % [waves.wave, _of_final(), TopBar.clock(waves.time_left)]
			if waves.is_push_wave():
				_phase_label.text = "Big push! Wave %d%s in %s, every rival sends 40%% more" % [waves.wave, _of_final(), TopBar.clock(waves.time_left)]
			elif waves.camped() > 0:
				_phase_label.text += "   %d raiders camped" % waves.camped()
		WaveManager.WAVE:
			_phase_label.text = "Wave %d%s  ·  %d raider%s left" % [waves.wave, _of_final(), waves.remaining(), "" if waves.remaining() == 1 else "s"]
		_:
			_phase_label.text = ""
	if recruiter and recruiter.queued > 0:
		_phase_label.text += "   Training %d (%ds)" % [recruiter.queued, ceili(recruiter.time_left)]
	if _hero_respawn_left > 0.0:
		_phase_label.text += "   Commander back in %ds" % ceili(_hero_respawn_left)
	if Engine.time_scale != 1.0:
		_phase_label.text += "   [%s]" % ("Paused" if Engine.time_scale == 0.0 else "%dx" % int(Engine.time_scale))


## " of N" once the match's last wave is known, else "".
func _of_final() -> String:
	var last := waves.final_wave()
	return " of %d" % last if last > 0 else ""


func _on_game_over(won: bool) -> void:
	_game_over = true
	var grounded := waves.rivals_grounded()
	var text := "The Hub has fallen.\nYour charter is lost."
	if won and grounded[0] == grounded[1]:
		text = "Every rival grounded.\nThe sky is yours, Tycoon."
	elif won:
		text = "You held the sky for %d waves.\nThe charter is yours, Tycoon." % waves.match_waves
		text += (" and grounded %d of %d rivals." % grounded) if grounded[0] > 0 else "."
	_banner.text = text + "\n\nPress Enter to play again"
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


## The Hub starts with one Dynamo Generator on a generator socket, so the
## first towers you build have power.
func _place_starting_dynamo() -> void:
	for hex in region.tiles_of_platform("Hub"):
		if region.tiles[hex].type == "generator_socket" and not region.buildings.has(hex):
			region.place_building(Building.new().setup("dynamo"), hex)
			return


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


## The tips card folds down to its button once the first wave starts.
func _on_phase_changed(phase: String, _wave: int) -> void:
	if phase == WaveManager.WAVE and _help:
		set_tips_open(false)


## A small card with one tip at a time, so the screen stays playable from the
## first second. It never blocks anything outside its own small rect.
func _build_tips(layer: CanvasLayer) -> void:
	var pos := Vector2(16, TopBar.HEIGHT + 40)
	_help_button = Button.new()
	_help_button.name = "TipsButton"
	_help_button.text = "Foreman's Notes (/)"
	_help_button.focus_mode = Control.FOCUS_NONE
	_help_button.position = pos
	_help_button.tooltip_text = "Show the how-to-play notes (/)"
	_help_button.pressed.connect(set_tips_open.bind(true))
	layer.add_child(_help_button)

	_help = PanelContainer.new()
	_help.name = "HowToPlay"
	_help.position = pos
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_help.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	_help_page = Label.new()
	_help_page.theme_type_variation = "Title"
	_help_page.add_theme_font_size_override("font_size", 15)
	_help_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_help_page)
	var close := Button.new()
	close.text = "x"
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.tooltip_text = "Hide the notes (/)"
	close.pressed.connect(set_tips_open.bind(false))
	header.add_child(close)
	_help_text = Label.new()
	_help_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_help_text.custom_minimum_size.x = TIPS_WIDTH
	_help_text.add_theme_font_size_override("font_size", 16)
	box.add_child(_help_text)
	var nav := HBoxContainer.new()
	nav.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(nav)
	for step in [[-1, "<  Back"], [1, "Next  >"]]:
		var b := Button.new()
		b.text = step[1]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(show_tip.bind(step[0], true))
		nav.add_child(b)
	layer.add_child(_help)
	show_tip(0)
	set_tips_open(true)


## Shows tip i (or steps by i when relative), wrapping around the ends.
func show_tip(i: int, relative := false) -> void:
	_tip = posmod(_tip + i if relative else i, TIPS.size())
	_help_page.text = "Foreman's Notes  %d / %d" % [_tip + 1, TIPS.size()]
	var text: String = TIPS[_tip]
	# Tips quote live numbers so they can't go stale.
	if text.contains("%d"):
		text = text % (economy.scrap_per_island_per_round if economy else 15)
	_help_text.text = text
	# Shrink to fit the new text.
	_help.size = Vector2.ZERO


func set_tips_open(open: bool) -> void:
	_help.visible = open
	_help_button.visible = not open


func _on_hero_died(_hero: Unit) -> void:
	if _game_over:
		return
	_hero_respawn_left = HERO_RESPAWN_SECONDS
	show_notice("The Commander is down! Back in %d seconds" % int(HERO_RESPAWN_SECONDS))


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
	top_bar.combat = combat
	layer.add_child(top_bar)

	payout_popup = PayoutPopup.new()
	layer.add_child(payout_popup)
	economy.paid_out.connect(payout_popup.show_income)

	build_menu = BuildMenu.new()
	build_menu.building = building
	build_menu.region = region
	build_menu.walkways = walkways
	build_menu.steering = steering
	build_menu.patrols = patrols
	build_menu.recruiter = recruiter
	build_menu.resources = resources
	build_menu.powers = powers
	layer.add_child(build_menu)

	info_panel = InfoPanel.new()
	info_panel.region = region
	info_panel.camera = camera
	info_panel.selection = selection
	info_panel.building = building
	info_panel.walkways = walkways
	info_panel.combat = combat
	info_panel.storms = storms
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

	_phase_label = _hud_label("Phase", 20)
	_phase_label.add_theme_font_override("font", load(HudTheme.FONT_BOLD))
	_phase_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_phase_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_phase_label.position.y = TopBar.HEIGHT + 8
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(_phase_label)

	_build_tips(layer)
	waves.phase_changed.connect(_on_phase_changed)

	_banner = _hud_label("Banner", 46)
	_banner.theme_type_variation = "Title"
	_banner.add_theme_constant_override("outline_size", 10)
	_banner.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.04, 0.9))
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.visible = false
	layer.add_child(_banner)

	_build_difficulty_picker(layer)


## Easy / Normal / Hard, bottom centre, until wave 1 starts.
var _difficulty_row: HBoxContainer
var _difficulty_buttons := {}

func _build_difficulty_picker(layer: CanvasLayer) -> void:
	var panel := PanelContainer.new()
	panel.name = "Difficulty"
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_bottom = -96
	_difficulty_row = HBoxContainer.new()
	_difficulty_row.add_theme_constant_override("separation", 6)
	panel.add_child(_difficulty_row)
	var label := Label.new()
	label.text = "Difficulty"
	_difficulty_row.add_child(label)
	var group := ButtonGroup.new()
	for level in Difficulty.ORDER:
		var b := Button.new()
		b.text = level
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.button_pressed = level == Difficulty.level
		var d: Dictionary = Difficulty.LEVELS[level]
		b.tooltip_text = "%s: %d%% attackers, %d%% health, %d starting scrap" % [level, roundi(d.count * 100), roundi(d.hp * 100), d.scrap]
		b.pressed.connect(set_difficulty.bind(level))
		_difficulty_row.add_child(b)
		_difficulty_buttons[level] = b
	layer.add_child(panel)
	waves.phase_changed.connect(func(_p, _w): panel.visible = waves.wave == 1 and waves.phase == WaveManager.BUILD)


## Switches difficulty before wave 1, adjusting starting scrap by the
## difference (so scrap already spent stays spent).
func set_difficulty(level: String) -> void:
	if waves.wave != 1 or waves.phase != WaveManager.BUILD or not Difficulty.LEVELS.has(level):
		return
	var before: int = Difficulty.get_data().scrap
	Difficulty.level = level
	resources.add_scrap(Difficulty.get_data().scrap - before)
	if _difficulty_buttons.has(level):
		_difficulty_buttons[level].button_pressed = true
	show_notice("Difficulty set to %s" % level)


func _hud_label(node_name: String, font_size: int) -> Label:
	var label := Label.new()
	label.name = node_name
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	# A dark outline keeps text readable over bright sky and pale islands.
	label.add_theme_constant_override("outline_size", 5)
	label.add_theme_color_override("font_outline_color", Color(0.06, 0.05, 0.04, 0.85))
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
		build_menu.set_hint("Placing %s (weight %d). Click to build, Shift + click to keep going, R rotates, Esc or right click cancels." % [data.name, data.weight])
	else:
		build_menu.set_hint("")
	region.set_show_loads(type_id != "")


func _on_walkway_mode_changed(active: bool) -> void:
	if active:
		build_menu.set_hint("Walkway: click your island, then the island to reach. Esc or right click cancels.")
	else:
		build_menu.set_hint("")


func _on_platform_claimed(platform_name: String, new_owner: String) -> void:
	if new_owner == "player":
		show_notice("%s is ours" % platform_name)
	else:
		# Losing an island costs what you built there.
		var wrecked := 0
		for b in region.buildings_on(platform_name):
			if b.faction == "player":
				region.remove_building(b.hex)
				b.queue_free()
				wrecked += 1
		var corp := ""
		for u in region.units_on_platform(platform_name, Unit.ENEMY_GROUP):
			corp = u.get_meta("corp", corp)
		var who := corp if corp != "" else "A rival"
		if wrecked > 0:
			show_notice("%s seized %s and wrecked %d of our building%s" % [who, platform_name, wrecked, "" if wrecked == 1 else "s"])
		else:
			show_notice("%s seized %s" % [who, platform_name])


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
	toggle.tooltip_text = "Show or hide the map key (L)"
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
	# The legend starts folded so it never covers map labels; L opens it.
	set_legend_open(false)
	return panel


## Shows or folds away the legend's list.
func set_legend_open(open: bool) -> void:
	_legend_entries.visible = open
	_legend_toggle.text = ("v  Map key" if open else ">  Map key")
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
	# Controls live in the tips card; this line only names the selection.
	if units.is_empty():
		_status.text = ""
		return
	var counts := {}
	for u in units:
		counts[u.display_name] = counts.get(u.display_name, 0) + 1
	var parts := PackedStringArray()
	for n in counts:
		parts.append("%s x%d" % [n, counts[n]] if counts[n] > 1 else n)
	_status.text = ", ".join(parts)
