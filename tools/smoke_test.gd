## Headless smoke test: loads the main scene, checks the input map and the
## camera's zoom behaviour, then exits non-zero on any failure.
## Run: godot --headless --path . --script res://tools/smoke_test.gd
extends SceneTree

const Bindings = preload("res://tools/input_bindings.gd")

var _failures := 0


func _initialize() -> void:
	# Fail instead of hanging if a script error stops the test part-way.
	create_timer(120.0).timeout.connect(func():
		printerr("Smoke test timed out (likely a script error above)")
		quit(1))
	_check_input_map()
	_check_hex_math()
	_check_models()
	# A fixed map so results repeat (seed 3: Ironbell northwest, Vesper east).
	SkyRegion.seed_override = 3
	_check_layout_rules()
	await _check_open_map()
	# The rest of the checks use a map with every planned walkway built.
	SkyRegion.prebuilt_walkways = true
	SkyRegion.instant_walkways = true
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	# Balloon platforms only move when _check_drifting_islands drives them.
	main.drift.set_process(false)
	await process_frame
	_check_scene(main)
	_check_fog(main)
	_check_camera(main.get_node("RtsCamera"))
	_check_routing(main.get_node("Region"))
	await _check_drifting_islands(main)
	await _check_selection_and_orders(main)
	_check_building(main)
	_check_build_menu(main)
	_check_info_panel(main)
	_check_bomb_target(main)
	_check_top_bar(main)
	_check_debug_panel(main)
	_check_ferry(main)
	await _check_claiming_walkways_and_raids(main)
	_check_weight_power_income(main)
	_check_storms(main)
	await _check_hero_respawn(main)
	await _check_unit_roster(main)
	await _check_defense_roles(main)
	_check_air_routes(main)
	await _check_rival_airships(main)
	await _check_combat_and_waves(main)
	await _check_island_steering(main)
	await _check_air_patrols(main)
	main.queue_free()
	await process_frame
	await process_frame
	await _check_four_rivals()
	if _failures == 0:
		print("Smoke test passed")
	else:
		printerr("Smoke test failed: %d problem(s)" % _failures)
	quit(1 if _failures > 0 else 0)


## A real game's map: islands start unconnected, the player builds walkways
## to expand, and Ironbell bridges its way to the Hub.
func _check_open_map() -> void:
	SkyRegion.prebuilt_walkways = false
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.drift.set_process(false)
	main.waves.set_process(false)
	main.bridges.set_process(false)
	var region: SkyRegion = main.get_node("Region")
	for w in region.layout.walkways:
		_expect(not region.platforms_linked(w[0], w[1]), "%s and %s should start unconnected" % [w[0], w[1]])
	_expect(main.bridges.crews.has("Ironbell"), "Ironbell should bridge")
	_expect(not main.bridges.crews.has("Vesper"), "Vesper flies, it shouldn't bridge")
	# Waves count from first contact: until Ironbell's bridge lands, a late
	# wave still sends its first-size party and no carriers, and its top bar
	# card shows the bridge instead of a countdown.
	var waves: WaveManager = main.waves
	_expect(not waves.has_contact("Ironbell") and waves.has_contact("Vesper"), "Ironbell has no contact at the start; Vesper flies so it always does")
	_expect(waves.count_for("Ironbell", "ground", 6) == RivalCatalog.count_for("Ironbell", "ground", 1), "before contact Ironbell's party stays at its first size")
	_expect(waves.count_for("Ironbell", "carrier", 6) == 0, "no carriers before contact")
	_expect(waves.count_for("Vesper", "bomber", 3) == 1, "Vesper's first bomber still comes in wave 3")
	var bar_status: String = main.top_bar.status_text(waves.wave_plan()[0])
	_expect(bar_status.begins_with("Bridge: 0 of"), "Ironbell's card should show its bridge progress, got '%s'" % bar_status)
	waves.wave = 6
	waves.contact_wave["Ironbell"] = 6
	_expect(waves.count_for("Ironbell", "ground", 6) == RivalCatalog.count_for("Ironbell", "ground", 1), "first contact in wave 6 brings the wave-1 party")
	_expect(is_zero_approx(waves.health_bonus(6, "Ironbell")), "first contact has no extra health")
	_expect(waves.count_for("Ironbell", "ground", 8) == RivalCatalog.count_for("Ironbell", "ground", 3), "it grows from contact")
	waves.contact_wave.erase("Ironbell")
	waves.wave = 1

	# Expanding: a walkway from the Hub to the Foundry.
	var hub: Dictionary = region.platforms["Hub"]
	var foundry: Dictionary = region.platforms["Foundry"]
	main.resources.add_scrap(200)
	region.crew.set_process(false)
	var err: String = main.walkways.try_build(region.rim_toward(hub, foundry.center, true), region.rim_toward(foundry, hub.center, true))
	_expect(err == "", "the player should be able to bridge to the Foundry (%s)" % err)
	# Harpoons first, then the tiles one at a time.
	_expect(region.crew.jobs.size() == 1, "building a walkway should start a harpoon crew job")
	var job: Dictionary = region.crew.jobs[0] if not region.crew.jobs.is_empty() else {}
	_expect(not region.platforms_linked("Hub", "Foundry"), "the walkway shouldn't be there before the harpoons land")
	_expect(region.get_node("WalkwayCrew").get_child_count() == 1, "the harpoon rig should be in the scene")
	if not job.is_empty():
		region.crew.step(region.crew.harpoon_seconds + region.crew.player_tile_seconds * 0.5)
		_expect(job.laid == 1, "one tile should be down just after the harpoons land, got %d" % job.laid)
		_expect(main.walkways.try_build(region.rim_toward(hub, foundry.center, true), region.rim_toward(foundry, hub.center, true)) != "",
			"a second walkway can't go up over one being built")
		region.crew.step(region.crew.job_seconds(job))
	_expect(region.crew.jobs.is_empty(), "the walkway should finish")
	_expect(region.platforms_linked("Hub", "Foundry"), "the new walkway should join the Hub and Foundry")

	# Ironbell's crews: a span every span_seconds, starting at its HQ.
	var path: Array = region.layout.paths["Ironbell"]
	main.bridges.step(main.bridges.span_seconds + 0.1)
	_expect(main.bridges.spans_built("Ironbell") == 0, "Ironbell's span should still be going up")
	region.crew.step(30.0)
	_expect(main.bridges.spans_built("Ironbell") == 1, "Ironbell should finish one span after span_seconds")
	_expect(region.platforms_linked("Ironbell HQ", path[path.size() - 2]), "the first span should leave Ironbell HQ")
	_expect(main.bridges.frontier("Ironbell") == path[path.size() - 2], "the bridge should end at the next platform")
	var rival_tiles := 0
	for hex in region.tiles:
		if region.tiles[hex].get("builder", "") == "rival":
			rival_tiles += 1
	_expect(rival_tiles > 0, "Ironbell's bridge tiles should be marked as rival-built")

	# Raiders head for the end of the bridge while it's unfinished.
	var party: Array[Unit] = main.raids.send_party(2)
	main.raids._process(0.05)
	for u in party:
		_expect(u.is_moving(), "a raider should walk to the end of Ironbell's bridge")
	# Once there, they camp: they don't hold the wave open.
	var front: String = main.bridges.frontier("Ironbell")
	for u in party:
		u.position = region.snap_to_walkable(region.get_platform_position(front))
		u.set_route(PackedVector3Array(), true)
	_expect(main.bridges.is_waiting_at_frontier("Ironbell", party[0]), "a raider at the end of the bridge is camped")
	_expect(main.waves._alive(party) == 0, "camped raiders don't count toward ending the wave")
	_expect(main.waves.camped() == 2, "both raiders are camped, got %d" % main.waves.camped())
	for u in party:
		u.free()

	var reached := []
	main.bridges.reached_player.connect(func(_c, p): reached.append(p))
	var guard := 0
	while main.bridges.build_next_span("Ironbell") and guard < 20:
		region.crew.finish_all()
		guard += 1
	_expect(main.bridges.is_done("Ironbell"), "Ironbell's bridge should finish")
	_expect(region.platforms_linked("Ironbell HQ", "Hub"), "the finished bridge should reach the Hub")
	_expect(reached.has("Hub"), "the bridge reaching the Hub should be announced")

	# Cutting the bridge: the Commander parks beside where it lands on the Hub.
	var landing := Vector2i(999999, 0)
	for hex in region.tiles_of_platform("Hub"):
		for d in HexGrid.DIRECTIONS:
			if main.bridges._is_rival_walkway(hex + d) and region.is_hex_walkable(hex):
				landing = hex
	_expect(landing.x != 999999, "Ironbell's bridge should land beside a Hub tile")
	var hero: Unit = main.selection.find_hero()
	for u in main.selection.all_units():
		if u != hero:
			u.position = region.get_platform_position("Hub")
	hero.position = region.hex_center(landing)
	hero.set_route(PackedVector3Array(), true)
	var cut := []
	main.bridges.span_cut.connect(func(_c, n): cut.append(n))
	main.bridges.step_cutting(main.bridges.cut_seconds * 0.5)
	_expect(cut.is_empty() and main.bridges.cut_progress() > 0.0, "cutting takes a while")
	main.bridges.step_cutting(main.bridges.cut_seconds * 0.5 + 0.1)
	_expect(cut.size() == 1 and cut[0] > 0, "after cut_seconds the span falls")
	_expect(not region.platforms_linked("Ironbell HQ", "Hub"), "the cut bridge no longer reaches the Hub")
	_expect(not main.bridges.is_done("Ironbell"), "Ironbell's crew has a span to rebuild")
	_expect(main.bridges.build_next_span("Ironbell"), "the crew starts rebuilding the cut span")
	region.crew.finish_all()
	_expect(main.bridges.is_done("Ironbell") and region.platforms_linked("Ironbell HQ", "Hub"), "rebuilt, the bridge reaches the Hub again")
	main.queue_free()
	await process_frame
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)


## Every building, unit, airship and headquarters has its own model made of
## shared kit parts, and a rival's copy uses the rival palette.
func _check_models() -> void:
	var known := ["generator", "harvester", "lift", "turret", "coil", "horn", "mender", "flak", "skyhook", "engine", "airship_hangar", "mast"]
	for id in BuildingCatalog.BUILDINGS:
		var shape: String = BuildingCatalog.get_data(id).shape
		_expect(known.has(shape), "building %s needs a model in BuildingModels (shape %s)" % [id, shape])
		var b := Building.new().setup(id)
		_expect(b.get_node("Model").get_child_count() >= 12, "%s should be built from kit parts" % id)
		var before := b._materials.size()
		b.faction = "rival"
		_expect(b.get_node("Model").get_child_count() >= 12 and b._materials.size() == before, "%s rebuilds in rival colours" % id)
		b.set_ghost(true)
		b.free()
	_expect(ModelKit.new(Color.WHITE, "rival").mat("brass").albedo_color != ModelKit.new(Color.WHITE, "player").mat("brass").albedo_color,
		"rival trim differs from player brass")
	var parts := {}
	for type in UnitCatalog.UNITS:
		var u := UnitCatalog.make(type, "rival" if type == "walker" else "player")
		parts[type] = UnitModels.build(u).get_child_count()
		_expect(parts[type] >= 15, "%s should be built from kit parts" % type)
		u.free()
	for corp in ["", "Ironbell", "Vesper", "Nimbus", "Aurum"]:
		var plinth := Node3D.new()
		HqModels.build(plinth, corp, 0.6)
		_expect(plinth.get_node("Headquarters").get_child_count() >= 20, "the %s headquarters has a model" % (corp if corp != "" else "player"))
		plinth.free()
	var boat := UnitModels.ferry()
	_expect(boat.get_child_count() >= 15, "the ferry has a model")
	boat.free()


func _check_input_map() -> void:
	for action in Bindings.bindings():
		_expect(InputMap.has_action(action), "input action '%s' missing; run tools/generate_input_map.gd" % action)
		if InputMap.has_action(action):
			_expect(InputMap.action_get_events(action).size() > 0, "input action '%s' has no events" % action)


func _check_scene(main: Node) -> void:
	var region: SkyRegion = main.get_node("Region")
	for p in ["Hub", "Foundry", "Generator Rig", "Midway", "Outpost", "Crystal Spire", "Ironbell HQ"]:
		_expect(region.platforms.has(p), "layout is missing platform %s" % p)
	_expect(region.tiles_of_platform("Hub").size() == 37, "Hub (radius 3) should have 37 tiles")
	_expect(region.tiles_of_platform("Generator Rig").size() == 7, "Generator Rig (radius 1) should have 7 tiles")
	_expect(region.walkway_count == region.layout.walkways.size(), "expected %d walkways" % region.layout.walkways.size())
	_expect(region.tiles_in_clouds.size() == 2, "expected 2 storm clouds")
	var types := {}
	for hex in region.tiles:
		types[region.tiles[hex].type] = true
	for t in ["core", "rival_core", "generator_socket", "harvester_anchor", "scrap_heap", "crystal_seam", "dock", "spawn", "walkway"]:
		_expect(types.has(t), "no %s tile in the layout" % t)
	_expect(region.has_node("Tiles") and region.get_node("Tiles").get_child_count() == region.tiles.size(),
		"every tile should have a placeholder mesh")


func _check_fog(main: Node) -> void:
	var region: SkyRegion = main.get_node("Region")
	var fog: FogSystem = main.fog
	_expect(fog != null, "the main scene should have a FogSystem")
	if fog == null:
		return
	fog.update_visibility()
	_expect(fog.is_platform_revealed("Hub"), "the Hub should start out of the fog")
	for hq in ["Ironbell HQ", "Vesper Aerodrome"]:
		_expect(not fog.is_platform_revealed(hq), "%s should start hidden in the fog" % hq)
		_expect(fog.beacons.has(hq), "%s should glow through the fog" % hq)
	# Islands one walkway or ferry hop from the Hub are shown from the start,
	# with what they hold on their label.
	for near in ["Foundry", "Generator Rig", "Crystal Spire"]:
		_expect(fog.is_platform_revealed(near), "%s (next to the Hub) should start out of the fog" % near)
	_expect(region.platform_label("Foundry").text.contains("2 scrap heaps"), "the Foundry's label should say it holds 2 scrap heaps")
	_expect(not region.platform_label("Hub").text.contains("scrap heap"), "your own Hub's label shouldn't list its contents")
	var hq_tile: Node3D = region._tile_nodes[region.platforms["Ironbell HQ"].center]
	_expect(not hq_tile.visible, "Ironbell HQ's deck should be hidden by the fog")
	_expect(not region.get_node("HQ_IronbellHQ").visible, "Ironbell's HQ building should be hidden by the fog")

	var scout: Unit = main.get_node("Units").get_child(0)
	var home := scout.position
	var enemy := Unit.new()
	enemy.faction = "rival"
	main.get_node("Units").add_child(enemy)
	enemy.position = region.get_platform_position("Vesper Aerodrome")
	fog.update_visibility()
	_expect(not enemy.visible, "a rival unit out of sight should be hidden")

	scout.position = region.get_platform_position("Ironbell HQ")
	enemy.position = scout.position + Vector3(3, 0, 0)
	fog.update_visibility()
	_expect(fog.is_platform_revealed("Ironbell HQ"), "a unit next to Ironbell HQ should reveal it")
	_expect(not fog.beacons.has("Ironbell HQ"), "a revealed island stops glowing through the fog")
	_expect(hq_tile.visible, "Ironbell HQ's deck should show once scouted")
	_expect(enemy.visible, "a rival unit next to your unit should be visible")

	scout.position = home
	fog.update_visibility()
	_expect(hq_tile.visible, "scouted sky should stay clear")
	_expect(not enemy.visible, "a rival unit should vanish once you lose sight of it")
	main.get_node("Units").remove_child(enemy)
	enemy.free()


func _check_hex_math() -> void:
	for hex in [Vector2i(0, 0), Vector2i(3, -2), Vector2i(-7, 5), Vector2i(10, -17)]:
		_expect(HexGrid.from_world(HexGrid.to_world(hex, 2.0), 2.0) == hex, "hex round trip failed for %s" % hex)
	_expect(HexGrid.disk(Vector2i.ZERO, 2).size() == 19, "disk of radius 2 should have 19 hexes")
	_expect(HexGrid.ring(Vector2i.ZERO, 3).size() == 18, "ring of radius 3 should have 18 hexes")
	_expect(HexGrid.distance(Vector2i(0, 0), Vector2i(6, -9)) == 9, "hex distance is wrong")
	var line := HexGrid.line(Vector2i(0, 0), Vector2i(4, -2))
	_expect(line.size() == 5 and line[0] == Vector2i(0, 0) and line[4] == Vector2i(4, -2), "hex line is wrong")
	for i in line.size() - 1:
		_expect(HexGrid.distance(line[i], line[i + 1]) == 1, "hex line has a gap")


func _check_camera(cam: RtsCamera) -> void:
	_expect(cam.camera != null and cam.camera.current, "camera should be current")
	cam.zoom = 0.0
	cam._apply_zoom()
	var near_height := cam.camera.position.y
	var near_pitch := cam.get_pitch_degrees()
	cam.zoom = 1.0
	cam._apply_zoom()
	_expect(cam.camera.position.y > near_height, "zooming out should raise the camera")
	_expect(cam.get_pitch_degrees() > near_pitch, "zooming out should steepen the pitch")
	cam.position = Vector3(1000, 0, -1000)
	cam._clamp_to_bounds()
	_expect(cam.position.x <= cam.bounds.end.x and cam.position.z >= cam.bounds.position.y,
		"camera pivot should stay inside bounds")
	# Put the camera back over the Hub for the selection checks.
	cam.position = Vector3.ZERO
	cam.zoom = 0.5
	cam._apply_zoom()


func _check_routing(region: SkyRegion) -> void:
	var hub := region.get_platform_position("Hub")
	var foundry := region.get_platform_position("Foundry") + Vector3(1, 0, 0)
	var ironbell := region.hex_center(region.platforms["Ironbell HQ"].center + Vector2i(0, 2))
	var route := region.find_route(hub + Vector3(0, 0, 3), ironbell)
	_expect(not route.is_empty(), "Hub to Ironbell HQ should be walkable")
	var along := region.platforms_along(hub + Vector3(0, 0, 3), route)
	_expect(along == PackedStringArray(region.layout.paths.Ironbell),
		"Hub to Ironbell HQ should follow the chain %s, got %s" % [region.layout.paths.Ironbell, along])
	_expect(route[route.size() - 1].is_equal_approx(ironbell), "route should end at the target")
	_expect(not region.find_route(hub, foundry).is_empty(), "Hub to Foundry should be walkable")
	_expect(region.find_route(hub, region.get_platform_position("Crystal Spire") + Vector3(1, 0, 0)).is_empty(),
		"Crystal Spire is ferry-only and shouldn't be walkable from the Hub")
	_expect(region.find_route(hub, Vector3(500, 0, 500)).is_empty(), "open sky should be unreachable")
	_expect(not region.is_walkable(hub), "the Hub core blocks walking")
	var near := hub + Vector3(3, 0, 0)
	_expect(region.find_route(near, hub + Vector3(-3, 0, 2)).size() <= 2, "a short move on one deck should be nearly direct")
	# Every leg of a route stays on walkable tiles.
	var prev := hub + Vector3(0, 0, 3)
	for point in route:
		_expect(region._clear_line(prev, point), "route leg %s -> %s crosses open sky" % [prev, point])
		prev = point


func _check_drifting_islands(main: Node) -> void:
	var region: SkyRegion = main.get_node("Region")
	var drift: DriftSystem = main.drift
	_expect(drift.balloons.size() >= 1, "seed 3 should have a balloon platform")
	if drift.balloons.is_empty():
		return
	var b: Dictionary = drift.balloons[0]
	_expect(b.state == DriftSystem.MOORED and drift.moored_to(b) == b.ends[0], "a balloon starts moored at its first end")
	_expect(region.tiles_of_platform(b.name).size() == 7, "a balloon platform has 7 tiles")
	_expect(not b.walkway.is_empty(), "a moored balloon has a walkway")
	_expect(not region.reserved_hexes.is_empty(), "a balloon's flight path should be reserved")
	var aboard := region.hex_center(drift.center_of(b))
	var home := region.snap_to_walkable(region.get_platform_position(b.ends[0]))
	_expect(not region.find_route(home, aboard).is_empty(), "a moored balloon should be walkable from %s" % b.ends[0])

	var units_root := main.get_node("Units")
	var stuck := Unit.new()
	stuck.name = "DriftTestStuck"
	stuck.position = region.hex_center(b.walkway[0])
	units_root.add_child(stuck)
	var rider := Unit.new()
	rider.name = "DriftTestRider"
	rider.position = aboard
	units_root.add_child(rider)
	var warned := []
	drift.warning_started.connect(func(_n, _p, _s, count): warned.append(count), CONNECT_ONE_SHOT)

	# Balloons ignore the old timer: they only cast off when the wind turns.
	_expect(drift.wind == main.wind, "balloons follow the wind")
	b.timer = 0.01
	drift.step(0.05)
	_expect(b.state == DriftSystem.MOORED and warned.is_empty(), "a balloon stays moored until the wind turns")
	main.wind.wind_changed.emit(main.wind.from_index, false)
	drift.step(0.05)
	_expect(b.state == DriftSystem.WARNING, "a balloon should warn before casting off")
	_expect(warned == [1], "the warning should count 1 of your units on the walkway, got %s" % [warned])
	_expect(stuck.has_node(DriftSystem.CAUTION_NAME), "a unit on a breaking walkway gets a caution sign")
	_expect(not rider.has_node(DriftSystem.CAUTION_NAME), "a unit on the balloon itself is safe")

	drift.step(drift.warning_seconds)
	_expect(b.state == DriftSystem.DRIFTING, "after the warning the balloon casts off")
	_expect(stuck.riding, "a unit left on the walkway falls")
	_expect(not stuck.has_node(DriftSystem.CAUTION_NAME), "caution signs go once the walkway is gone")
	_expect(b.walkway.is_empty() and region.find_route(home, aboard).is_empty(), "a drifting balloon is cut off")

	for i in b.track.size() * 30:
		if b.state != DriftSystem.DRIFTING:
			break
		drift.step(drift.hop_seconds / 10.0)
	_expect(b.state == DriftSystem.MOORED and drift.moored_to(b) == b.ends[1], "the balloon should moor at %s" % b.ends[1])
	_expect(drift.center_of(b) == b.track[b.track.size() - 1], "the balloon should end on its track's last hex")
	_expect(region.platforms[b.name].center == drift.center_of(b), "the balloon's platform centre follows it")
	_expect(region.tiles_of_platform(b.name).size() == 7, "the balloon keeps 7 tiles after drifting")
	_expect(region.platform_at(rider.position) == b.name, "a unit aboard rides along with the balloon")
	var far := region.snap_to_walkable(region.get_platform_position(b.ends[1]))
	_expect(not region.find_route(far, region.hex_center(drift.center_of(b))).is_empty(),
		"the walkway reconnects at %s" % b.ends[1])
	_expect(region.get_node("Tiles").get_child_count() == region.tiles.size(), "every tile still has one mesh after drifting")
	await create_timer(drift.fall_seconds + 0.3).timeout
	_expect(not is_instance_valid(stuck), "a fallen unit is lost")
	units_root.remove_child(rider)
	rider.free()


func _check_selection_and_orders(main: Node) -> void:
	var sel: SelectionController = main.selection
	var units := sel.all_units()
	_expect(units.size() == 5, "expected the Commander and 4 Riveteers, got %d" % units.size())
	var hero := sel.find_hero()
	_expect(hero != null, "a hero should exist")

	sel.select_units([hero])
	_expect(sel.selected.size() == 1 and hero.selected, "clicking the hero selects only the hero")
	var others := units.filter(func(u): return not u.is_hero)
	sel.select_units(others, true)
	_expect(sel.selected.size() == 5, "Shift-adding the squad should select all 5")
	sel.assign_control_group(1)
	sel.select_units([])
	_expect(sel.selected.is_empty() and not hero.selected, "empty click clears the selection")
	sel.recall_control_group(1)
	_expect(sel.selected.size() == 5, "control group 1 should bring back all 5")

	# Box select over the whole screen catches every unit on the Hub.
	var everything := sel.units_in_screen_rect(main.get_viewport().get_visible_rect())
	_expect(everything.size() == 5, "box over the screen should catch 5 units, got %d" % everything.size())

	# The deck plane under the screen centre should be a real point.
	var centre := main.get_viewport().get_visible_rect().size / 2.0
	_expect(sel.ground_point_at(centre) != null, "screen centre should hit the deck plane")

	var offsets := sel.formation_offsets(5)
	_expect(offsets[0] == Vector3.ZERO, "first formation slot is the centre")

	# Order everyone to NeutralD and simulate until they arrive.
	var region: SkyRegion = main.get_node("Region")
	var target: Vector3 = region.hex_center(region.platforms["Midway"].center)
	_expect(sel.order_move(target), "ordering a move to Midway should succeed")
	_expect(not sel.order_move(Vector3(500, 0, 500)), "ordering a move into open sky should fail")
	for i in 600:
		for u in units:
			u._process(0.05)
	for u in units:
		_expect(not u.is_moving(), "%s should have arrived" % u.name)
		_expect(region.platform_at(u.position) == "Midway", "%s should be on Midway, is at %s" % [u.name, u.position])
	_expect(hero.position.distance_to(target) < 0.01, "hero should take the centre spot")
	await process_frame


func _check_building(main: Node) -> void:
	var region: SkyRegion = main.get_node("Region")
	var build: BuildController = main.building
	var res: PlayerResources = main.resources
	var hub: Vector2i = region.platforms["Hub"].center
	var start_scrap := res.scrap
	_expect(start_scrap == 300, "player should start with 300 scrap")
	# The Hub starts with one Dynamo on a generator socket (15 power, 3 weight).
	var starting := region.buildings_on("Hub").filter(func(b): return b.type_id == "dynamo")
	_expect(starting.size() == 1 and starting[0].power == 15, "the Hub starts with one socketed Dynamo")
	var base_power := region.power_supply()
	var base_load := region.platform_load("Hub")

	var deck := hub + Vector2i(2, 0)
	_expect(region.get_tile(deck).type == "deck", "test tile should be plain deck")
	_expect(build.try_place("dynamo", deck) == "", "a Dynamo on Hub deck should be allowed")
	_expect(res.scrap == start_scrap - 40, "Dynamo should cost 40 scrap")
	_expect(region.platform_load("Hub") == base_load + 3, "Dynamo should add 3 weight")
	_expect(region.power_supply() == base_power + 10, "Dynamo on deck should supply 10")
	_expect(not region.is_hex_walkable(deck), "a building blocks its tile")
	_expect(build.try_place("rivet_turret", deck) != "", "can't build on an occupied tile")

	var socket := hub + Vector2i(2, -1)
	if region.buildings.has(socket):
		socket = hub + Vector2i(-2, 1)
	_expect(region.get_tile(socket).type == "generator_socket", "Hub should have a free generator socket")
	_expect(build.try_place("dynamo", socket) == "", "a Dynamo on a socket should be allowed")
	_expect(region.power_supply() == base_power + 25, "a socketed Dynamo should supply 15")

	_expect(build.try_place("harvester", hub + Vector2i(-2, 0)) != "", "harvesters need an anchor")
	var anchor := Vector2i(999, 999)
	for hex in region.tiles_of_platform("Hub"):
		if region.get_tile(hex).type == "harvester_anchor":
			anchor = hex
	_expect(build.try_place("harvester", anchor) == "", "a harvester on the Hub anchor should be allowed")
	_expect(region.power_supply() == base_power + 55, "harvester should add 30 power")

	res.add_scrap(100)
	var coil_err := build.try_place("arc_coil", hub + Vector2i(-2, 2))
	_expect(coil_err == "", "an Arc Coil should be allowed: " + coil_err)
	_expect(region.power_demand() == 8, "Arc Coil should draw 8")
	var coil: Building = region.buildings[hub + Vector2i(-2, 2)]
	coil.set_efficiency(0.0)
	_expect(coil.power_warning() == "NO POWER", "an unpowered tower shows NO POWER")
	coil.set_efficiency(0.5)
	_expect(coil.power_warning() == "LOW POWER", "a browned-out tower shows LOW POWER")
	coil.set_efficiency(1.0)
	_expect(coil.power_warning() == "", "a powered tower shows no warning")
	_expect(build.try_place("rivet_turret", hub) != "", "can't build on the Hub core")
	_expect(build.try_place("rivet_turret", region.platforms["Foundry"].center) != "", "can't build on an unowned platform")
	var hero: Unit = main.selection.find_hero()
	var hero_home := hero.position
	hero.position = region.hex_center(hub + Vector2i(0, 1))
	_expect(build.placement_problem("rivet_turret", hub + Vector2i(0, 1)) == "Units are standing there", "can't build under a unit")
	hero.position = hero_home

	var before := res.scrap
	res.scrap = 10
	_expect(build.try_place("flak_battery", hub + Vector2i(-1, -1)).begins_with("Not enough scrap"), "costs are enforced")
	res.scrap = before

	var refund := build.demolish(deck)
	_expect(refund == 30, "demolishing a Dynamo refunds 30, got %d" % refund)
	_expect(res.scrap == before + 30, "refund should be added to scrap")
	_expect(region.is_hex_walkable(deck), "demolished tile is walkable again")
	_expect(region.platform_load("Hub") == base_load + 2 + 3 + 4, "load after demolish should be 9 more than at the start, got %d" % (region.platform_load("Hub") - base_load))

	# Build mode hotkeys create and clear the ghost.
	build.start_placing("flak_battery")
	_expect(build.placing == "flak_battery" and build._ghost != null, "start_placing should show a ghost")
	build.cancel_placing()
	_expect(build.placing == "" and build._ghost == null, "cancel_placing should clear the ghost")


func _check_build_menu(main: Node) -> void:
	var menu: BuildMenu = main.build_menu
	_expect(menu != null, "the HUD should have a build menu")
	if menu == null:
		return
	_expect(menu.get_node("Box/Tabs").get_child_count() == 4, "the build menu should have 4 tabs")
	for tab_name in BuildMenu.TABS:
		menu.show_tab(tab_name)
		var filled: int = BuildMenu.TABS[tab_name].filter(func(e): return e != "").size()
		_expect(menu._entry_buttons.size() == filled, "%s tab should show its buttons" % tab_name)
	# Every building in the catalog is somewhere in the menu.
	# (Turbine Engines are parked off the menu until moving islands return.)
	for type_id in BuildingCatalog.BUILDINGS:
		if type_id != "turbine_engine":
			_expect(BuildMenu.tab_of(type_id) != "", "%s is missing from the build menu" % type_id)
	# Clicking a button starts placing, and a hotkey jumps to the right tab.
	menu.show_tab("Defense")
	menu._entry_buttons["flak_battery"].emit_signal("pressed")
	_expect(main.building.placing == "flak_battery", "the Flak Battery button should start placing")
	_expect(menu._entry_buttons["flak_battery"].button_pressed, "the active building's button should be lit")
	main.building.start_placing("dynamo")
	_expect(menu.current_tab == "Industry", "placing a Dynamo should switch to the Industry tab")
	_expect(main.region.show_loads, "platform loads show while placing a building")
	main.building.cancel_placing()
	_expect(not main.region.show_loads, "platform loads hide again when placing ends")
	_expect(BuildMenu.TABS.keys() == ["Army", "Defense", "Industry", "Hum"], "four build tabs: Army, Defense, Industry, Hum")
	menu.activate("walkway")
	_expect(main.walkways.active, "the Walkway button should start a walkway")
	menu.activate("walkway")
	_expect(not main.walkways.active, "pressing Walkway again should cancel it")
	menu.show_tab("Army")

	# The command grid: keys follow the slots, and their meaning follows the tab.
	_expect(menu._grid.get_child_count() == 16, "the command grid should have 16 slots")
	menu.show_tab("Defense")
	menu._unhandled_input(_key(KEY_A))
	_expect(main.building.placing == "flak_battery", "A on the Defense tab should pick the Flak Battery")
	main.building.cancel_placing()
	menu._unhandled_input(_key(KEY_Z))
	_expect(main.building.placing == "airship_hangar", "Z on the Defense tab should pick the Airship Hangar")
	main.building.cancel_placing()
	menu._unhandled_input(_key(KEY_S))
	_expect(main.building.placing == "skyhook_cannon", "S on the Defense tab should pick the Skyhook Gun")
	main.building.cancel_placing()
	menu.show_tab("Industry")
	menu._unhandled_input(_key(KEY_Q))
	_expect(main.building.placing == "dynamo", "Q on the Industry tab should pick the Dynamo")
	main.building.cancel_placing()
	menu._unhandled_input(_key(KEY_W, true))
	_expect(not main.walkways.active, "Shift + W is for the camera, not the grid")
	menu._unhandled_input(_key(KEY_TAB))
	_expect(menu.current_tab == "Hum", "Tab should move on to the next tab")
	menu.show_tab("Army")

	# Only one click tool is live at a time: starting one ends the others.
	menu.activate("patrol_route")
	_expect(main.patrols.editing, "the Patrol Route button should start drawing a route")
	menu.activate("walkway")
	_expect(main.walkways.active and not main.patrols.editing, "starting a walkway should end route drawing")
	menu.activate("steer")
	_expect(main.steering.active and not main.walkways.active, "steering should end the walkway tool")
	menu.activate("rivet_turret")
	_expect(main.building.placing == "rivet_turret" and not main.steering.active, "placing a building should end steering")
	menu.activate("patrol_route")
	_expect(main.patrols.editing and main.building.placing == "", "drawing a route should end placing")
	main.patrols.cancel_route()
	menu.show_tab("Army")
	# The how-to-play text names the right key for flak.
	var flak_key: String = BuildMenu.SLOT_KEYS[BuildMenu.TABS["Defense"].find("flak_battery")]
	_expect("\n".join(main.TIPS).contains("Flak Batteries (Defense, %s)" % flak_key), "how to play should give Flak's real key (%s)" % flak_key)

	# The legend folds away and comes back.
	main.set_legend_open(false)
	_expect(not main._legend_entries.visible, "the legend should fold away")
	main.set_legend_open(true)
	_expect(main._legend_entries.visible, "the legend should open again")


func _check_info_panel(main: Node) -> void:
	var info: InfoPanel = main.info_panel
	var region: SkyRegion = main.get_node("Region")
	var cam: Camera3D = main.camera.camera
	# Every kind of thing has a title and a summary.
	var things: Array = [main.selection.find_hero(), {"kind": "platform", "name": "Foundry"},
		{"kind": "tile", "type": "scrap_heap", "platform": "Foundry", "target": ""}]
	for cloud in region.clouds:
		things.append({"kind": "cloud", "name": cloud})
	for hq in main.get_tree().get_nodes_in_group(Headquarters.GROUP):
		things.append(hq)
	for pair in region.layout.air_lanes:
		things.append({"kind": "air_lane", "a": pair[0], "b": pair[1]})
	for pair in region.layout.ferry_routes:
		things.append({"kind": "ferry", "a": pair[0], "b": pair[1]})
	for thing in things:
		var d := info.describe(thing)
		_expect(d.title != "" and d.body != "", "info card is missing text for %s" % str(thing))
	for type_id in BuildingCatalog.BUILDINGS:
		_expect(InfoPanel.BUILDING_INFO.has(type_id), "no info card summary for %s" % type_id)

	# Clicking picks the thing under the mouse.
	main.camera.position = region.get_platform_position("Hub")
	main.camera._apply_zoom()
	var hero: Unit = main.selection.find_hero()
	var picked = info.pick(cam.unproject_position(hero.global_position + Vector3.UP))
	_expect(picked == hero, "clicking the Commander should describe the Commander, got %s" % str(picked))
	var hub: Vector2i = region.platforms["Hub"].center
	# A free deck tile away from the squad, so a unit doesn't win the click.
	var deck := Vector2i(999, 999)
	for hex in region.tiles_of_platform("Hub"):
		if region.get_tile(hex).type != "deck" or region.buildings.has(hex):
			continue
		var clear := true
		for u in main.get_tree().get_nodes_in_group(Unit.GROUP):
			if u.global_position.distance_to(region.hex_center(hex)) < 4.0:
				clear = false
		if clear:
			deck = hex
			break
	main.resources.add_scrap(40)
	_expect(main.building.try_place("dynamo", deck) == "", "info card test needs a Dynamo on the Hub")
	# The headless window is tiny, so far-off units can still be within the
	# click radius on screen: hide them for this click.
	var squad: Array = main.get_tree().get_nodes_in_group(Unit.GROUP)
	for u in squad:
		u.visible = false
	picked = info.pick(cam.unproject_position(region.hex_center(deck)))
	for u in squad:
		u.visible = true
	_expect(picked is Building and picked.type_id == "dynamo", "clicking a Dynamo should describe it, got %s" % str(picked))
	info.show_thing(picked)
	_expect(info.visible and info._title.text == "Dynamo Generator", "the info card should show the Dynamo")
	info.show_at(Vector2(-5000, -5000))
	_expect(not info.visible, "clicking empty sky should hide the info card")
	main.building.demolish(deck)
	# Put scrap back where it was for the checks that follow.
	main.resources.scrap -= BuildingCatalog.refund_for("dynamo")


func _check_top_bar(main: Node) -> void:
	var bar: TopBar = main.top_bar
	var waves: WaveManager = main.waves
	_expect(bar != null, "the HUD should have a top bar")
	if bar == null:
		return
	bar.refresh()
	_expect(bar._scrap.text == "Scrap %d" % main.resources.scrap, "the top bar should show scrap")
	_expect(not bar._overload.visible, "no overload warning while every platform is stable")
	var plan := waves.wave_plan()
	_expect(plan.size() >= 2, "the wave plan should list every rival")
	for entry in plan:
		_expect(bar._cards.has(entry.corp), "the top bar should have a card for %s" % entry.corp)
	# Wave 1: Ironbell sends walkers, Vesper sits it out until wave 2.
	var ironbell: Dictionary = plan[0]
	var total := 0
	for u in ironbell.units:
		total += u[1]
	_expect(total == waves.party_size_for(waves.wave), "Ironbell's plan should match its party size")
	_expect(bar.wave_tooltip(ironbell).contains("Ironbell Walker"), "hovering Ironbell should list its walkers")
	if waves.phase == WaveManager.BUILD:
		_expect(bar.status_text(ironbell).begins_with("Wave %d in" % waves.wave), "Ironbell's card should count down: " + bar.status_text(ironbell))
	var vesper: Array = waves.wave_plan(3).filter(func(e): return e.corp == "Vesper")
	_expect(not vesper.is_empty() and vesper[0].units[0][0] == "Vesper Bomber", "Vesper's wave 3 should send bombers")
	_expect(TopBar.clock(83.2) == "1:24", "clock should format as m:ss")


func _check_debug_panel(main: Node) -> void:
	var debug: DebugPanel = main.debug_panel
	_expect(debug != null and not debug.is_open(), "the Debug panel should start folded")
	if debug == null:
		return
	var fog: FogSystem = main.fog
	var far := Vector3(99999, 0, 99999)
	debug.set_fog(false)
	_expect(not fog.enabled and fog.is_explored(far) and fog.is_visible_now(far), "fog off should show everything")
	_expect(not fog.get_node("FogBank").visible, "fog off should hide the fog clouds")
	debug.set_fog(true)
	_expect(fog.enabled and not fog.is_explored(far), "fog on should hide unexplored sky again")
	_expect(fog.get_node("FogBank").visible, "fog on should show the fog clouds")
	debug.set_open(true)
	_expect(debug.is_open(), "the Debug panel should open")
	debug.set_open(false)


func _key(keycode: Key, shift := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = true
	event.shift_pressed = shift
	return event


func _check_claiming_walkways_and_raids(main: Node) -> void:
	var region: SkyRegion = main.get_node("Region")
	var capture: CaptureSystem = main.capture
	var raids: RivalRaids = main.raids
	var res: PlayerResources = main.resources
	var units: Array[Unit] = main.selection.all_units()
	capture.set_process(false)
	raids.set_process(false)

	_expect(not capture.is_claimable("Hub") and not capture.is_claimable("Ironbell HQ"), "HQs can't be claimed")
	_expect(capture.is_claimable("Foundry"), "neutral platforms can be claimed")

	# Two units on the Foundry claim it.
	var foundry := region.get_platform_position("Foundry")
	units[1].position = foundry + Vector3(1, 0, 0)
	units[2].position = foundry + Vector3(-1, 0, 0)
	for u in units.slice(3):
		u.position = region.hex_center(region.platforms["Hub"].center + Vector2i(1, 1))
	units[0].position = region.hex_center(region.platforms["Hub"].center + Vector2i(-1, 1))
	capture.step(1.0)
	_expect(capture.claims["Foundry"].side == "player" and capture.claims["Foundry"].progress > 0.0, "claiming should start")
	for i in 10:
		capture.step(1.0)
	_expect(region.platform_owner("Foundry") == "player", "two units should claim the Foundry within 11 s")

	# Building a walkway from the Foundry to the ferry-only Crystal Spire.
	var crystal: Dictionary = region.platforms["Crystal Spire"]
	var foundry_data: Dictionary = region.platforms["Foundry"]
	var from_hex: Vector2i = region.rim_toward(foundry_data, crystal.center, true)
	var to_hex: Vector2i = region.rim_toward(crystal, foundry_data.center, true)
	var plan := region.plan_walkway(from_hex, to_hex)
	_expect(plan.problem == "" and plan.tiles.size() > 0, "Foundry to Crystal Spire walkway should plan: %s" % plan.problem)
	_expect(region.plan_walkway(to_hex, from_hex).problem != "", "can't start a walkway on a platform you don't own")
	_expect(region.plan_walkway(from_hex, region.platforms["Foundry"].center).problem != "", "walkway must end on another platform")
	var walkways_before := region.walkway_count
	var scrap_before := res.scrap
	res.add_scrap(100)
	_expect(main.walkways.try_build(from_hex, to_hex) == "", "walkway build should succeed")
	_expect(res.scrap == scrap_before + 100 - plan.cost, "walkway should cost %d" % plan.cost)
	_expect(region.walkway_count == walkways_before + 1, "walkway count should go up")
	var spire := region.get_platform_position("Crystal Spire") + Vector3(1, 0, 0)
	_expect(not region.find_route(region.get_platform_position("Hub") + Vector3(0, 0, 3), spire).is_empty(),
		"Crystal Spire should be walkable after the new walkway")

	# Contested: a rival on the Foundry stops progress.
	var rival := raids.send_party(1)[0]
	rival.position = foundry
	region.set_platform_owner("Foundry", "")
	capture.claims.erase("Foundry")
	capture.step(1.0)
	_expect(capture.claims["Foundry"].progress == 0.0, "contested platforms don't progress")
	rival.queue_free()
	await process_frame
	region.set_platform_owner("Foundry", "player")
	units[1].position = region.hex_center(region.platforms["Hub"].center + Vector2i(2, 1))
	units[2].position = region.hex_center(region.platforms["Hub"].center + Vector2i(-2, 2))

	# A raiding party claims Midway on its way, then gathers at the Hub.
	var party := raids.send_party(3)
	_expect(party.size() == 3 and get_root().get_tree().get_nodes_in_group(Unit.ENEMY_GROUP).size() == 3, "raid should spawn 3 walkers")
	var chain: Array = region.layout.paths.Ironbell
	_expect(raids.next_objective(party[0].position) == chain[chain.size() - 2], "raiders should go for the platform next to their HQ first")
	for i in 8000:
		raids._process(0.05)
		for u in party:
			u._process(0.05)
		capture.step(0.05)
		if region.platform_owner("Midway") == "rival" and party.all(func(u): return region.platform_at(u.position) == "Hub" and not u.is_moving()):
			break
	for platform_name in chain.slice(1, chain.size() - 1):
		_expect(region.platform_owner(platform_name) == "rival", "raiders should claim %s on the way" % platform_name)
	for u in party:
		_expect(region.platform_at(u.position) == "Hub", "%s should end on the Hub, is at %s" % [u.name, u.position])
	capture.set_process(true)
	raids.set_process(true)


func _check_weight_power_income(main: Node) -> void:
	var region: SkyRegion = main.get_node("Region")
	var loads: LoadSystem = main.loads
	var economy: EconomySystem = main.economy
	var build: BuildController = main.building
	var res: PlayerResources = main.resources
	loads.set_process(false)
	economy.set_process(false)
	# Storm power is checked on its own in _check_storms.
	main.storms.set_process(false)
	region.storm_bonus = 0
	for e in get_root().get_tree().get_nodes_in_group(Unit.ENEMY_GROUP):
		e.free()

	_expect(LoadSystem.state_for(40, 40) == LoadSystem.STABLE, "100% is stable")
	_expect(LoadSystem.state_for(41, 40) == LoadSystem.SWAYING, "102% sways")
	_expect(LoadSystem.state_for(47, 40) == LoadSystem.SAGGING, "117% sags")
	_expect(LoadSystem.state_for(53, 40) == LoadSystem.FAILING, "132% fails")

	# Overload the small Generator Rig (capacity 10) with units and buildings.
	region.set_platform_owner("Generator Rig", "player")
	var rig: Vector2i = region.platforms["Generator Rig"].center
	res.add_scrap(500)
	_expect(build.try_place("dynamo", rig) == "", "Dynamo on the Rig socket")
	_expect(build.try_place("rivet_turret", rig + Vector2i(1, 0)) == "", "turret on the Rig")
	_expect(build.try_place("flak_battery", rig + Vector2i(-1, 0)) == "", "flak on the Rig")
	_expect(region.platform_load("Generator Rig") == 8, "Rig buildings weigh 8")
	var units: Array[Unit] = main.selection.all_units()
	var spots := [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(0, 1)]
	for i in units.size():
		units[i].position = region.hex_center(rig + spots[i])
	_expect(region.platform_load("Generator Rig") == 11, "units add half their weight (hero 2 + 4 x 1 = 6, counts 3), got %d" % region.platform_load("Generator Rig"))
	loads.step(0.1)
	_expect(loads.state_of("Generator Rig") == LoadSystem.SWAYING, "110% load should sway")
	_expect(is_equal_approx(units[0].speed_multiplier, 1.0), "swaying doesn't slow units")
	# Shrink the Rig to push it over the edge: 11 / 8 is 137%.
	var rig_cap: int = region.platforms["Generator Rig"].capacity
	region.platforms["Generator Rig"].capacity = 8
	loads.step(0.1)
	_expect(loads.state_of("Generator Rig") == LoadSystem.FAILING, "137% load should be failing")
	_expect(is_equal_approx(units[0].speed_multiplier, 0.4), "units on a failing platform move at 40%")
	# Emergency Lift (a company power) holds it steady while it runs.
	var powers: CompanyPowers = main.powers
	res.crystals = 0
	_expect(powers.use("emergency_lift") != "", "company powers cost crystals")
	res.add_crystals(50)
	_expect(powers.use("emergency_lift") == "" and res.crystals == 30, "Emergency Lift costs 20 crystals")
	loads.step(6.0)
	_expect(loads.state_of("Generator Rig") == LoadSystem.STABLE, "Emergency Lift keeps your platforms stable")
	_expect(region.buildings_on("Generator Rig").size() == 3, "nothing breaks off under Emergency Lift")
	powers.step(CompanyPowers.POWERS.emergency_lift.seconds + 0.1)
	_expect(not powers.is_running("emergency_lift") and powers.use("emergency_lift") != "", "Emergency Lift wears off and recharges")
	powers.step(CompanyPowers.POWERS.emergency_lift.cooldown + 0.1)
	loads.step(0.1)
	_expect(loads.state_of("Generator Rig") == LoadSystem.FAILING, "overload returns when Emergency Lift ends")
	loads.step(6.0)
	_expect(region.buildings_on("Generator Rig").size() == 2, "the newest building should break off")
	_expect(not region.buildings.has(rig + Vector2i(-1, 0)), "the Flak Battery (newest) is the one lost")
	loads.step(0.1)
	_expect(loads.state_of("Generator Rig") == LoadSystem.STABLE, "8 of 8 is stable")
	# A Lift Engine adds 10 capacity, and weighs nothing itself.
	region.platforms["Generator Rig"].capacity = rig_cap
	var lift_hex := rig + Vector2i(-1, 0)
	_expect(build.try_place("lift_engine", lift_hex) == "", "a Lift Engine on the Rig")
	_expect(region.platform_capacity("Generator Rig") == rig_cap + 10, "a Lift Engine adds 10 capacity")
	_expect(region.platform_load("Generator Rig") == 8, "a Lift Engine weighs nothing")
	build.demolish(lift_hex)
	_expect(region.platform_capacity("Generator Rig") == rig_cap, "capacity drops when the Lift Engine goes")
	# Overcharge makes your towers fire faster while it runs.
	_expect(powers.use("overcharge") == "" and is_equal_approx(main.combat.player_tower_rate, CompanyPowers.OVERCHARGE_RATE), "Overcharge speeds up your towers")
	powers.step(CompanyPowers.POWERS.overcharge.seconds + 0.1)
	_expect(is_equal_approx(main.combat.player_tower_rate, 1.0), "Overcharge wears off")
	powers.step(100.0)

	# Brownout: remove every power source, then restore one.
	for b in region.buildings.values().duplicate():
		if b.power > 0:
			build.demolish(b.hex)
	_expect(region.power_supply() == 0 and region.power_demand() > 0, "no supply left")
	economy.step(0.1)
	_expect(region.grid_efficiency() == 0.0 and economy.efficiency == 0.0, "no supply means 0% efficiency")
	var consumer: Building = null
	for b in region.buildings.values():
		if b.power < 0:
			consumer = b
	_expect(consumer != null and consumer.efficiency == 0.0, "consumers dim in a brownout")
	_expect(build.try_place("dynamo", rig) == "", "rebuild a Dynamo")
	economy.step(0.1)
	_expect(economy.efficiency == 1.0 and consumer.efficiency == 1.0, "power restored")

	# Income: the Foundry (claimed earlier) has 2 scrap heaps; a harvester forms crystals.
	_expect(region.platform_owner("Foundry") == "player", "Foundry should still be ours")
	var anchor := Vector2i(999, 999)
	for hex in region.tiles_of_platform("Hub"):
		if region.get_tile(hex).type == "harvester_anchor":
			anchor = hex
	_expect(build.try_place("harvester", anchor) == "", "rebuild the Hub harvester")
	var scrap_before := res.scrap
	var crystals_before := res.crystals
	economy.step(30.0)
	_expect(res.scrap == scrap_before and res.crystals == crystals_before, "income waits for the end of the round")
	var preview := economy.round_income()
	var islands := economy.islands_held()
	_expect(islands >= 2, "we hold the Foundry and the Rig, got %d islands" % islands)
	var expected := 2 * economy.scrap_per_heap_per_round + islands * economy.scrap_per_island_per_round
	_expect(preview.scrap == expected, "2 heaps and %d islands should pay %d scrap a round, got %d" % [islands, expected, preview.scrap])
	var paid := economy.pay_round(1)
	_expect(res.scrap == scrap_before + paid.scrap and paid.scrap == preview.scrap, "the round payout should add the heaps' scrap")
	_expect(res.crystals == crystals_before + economy.crystals_per_harvester_per_round, "1 harvester should pay %d crystals a round" % economy.crystals_per_harvester_per_round)
	_expect(paid.sources.size() == 3, "the payout should list islands, heaps and harvesters")
	_expect(main.payout_popup.visible and main.payout_popup._lines.text.contains("scrap heap"), "the payout popup should list the income")
	region.set_platform_owner("Foundry", "")
	scrap_before = res.scrap
	economy.pay_round(2)
	_expect(res.scrap == scrap_before + economy.islands_held() * economy.scrap_per_island_per_round, "unowned scrap heaps give nothing")
	# Crystal seams pay crystals while you hold their island.
	var spire_owner := region.platform_owner("Crystal Spire")
	region.set_platform_owner("Crystal Spire", "player")
	var seams := 0
	for hex in region.tiles_of_platform("Crystal Spire"):
		if region.get_tile(hex).type == "crystal_seam":
			seams += 1
	_expect(seams > 0, "the Crystal Spire has crystal seams")
	crystals_before = res.crystals
	economy.pay_round(3)
	_expect(res.crystals == crystals_before + economy.crystals_per_harvester_per_round + seams * economy.crystals_per_seam_per_round,
		"held crystal seams should pay %d crystals each" % economy.crystals_per_seam_per_round)
	region.set_platform_owner("Crystal Spire", spire_owner)
	# One Lift Engine per island.
	var deck := []
	for hex in region.tiles_of_platform("Hub"):
		if region.get_tile(hex).type == "deck" and not region.buildings.has(hex):
			deck.append(hex)
	res.add_scrap(500)
	_expect(build.try_place("lift_engine", deck[0]) == "", "place a Lift Engine")
	_expect(build.try_place("lift_engine", deck[1]) == "One Lift Engine per island", "a second Lift Engine on the same island is refused")
	build.demolish(deck[0])


func _check_ferry(main: Node) -> void:
	var region: SkyRegion = main.get_node("Region")
	var ferry: FerrySystem = main.ferry
	var sel: SelectionController = main.selection
	ferry.set_process(false)
	_expect(ferry.ferries.size() == 1, "expected one ferry route")
	var hero: Unit = sel.find_hero()
	hero.position = region.get_platform_position("Hub") + Vector3(0, 0, 3)
	hero.stop()
	sel.select_units([hero])
	var spire := region.get_platform_position("Crystal Spire") + Vector3(1, 0, 0)
	_expect(region.find_route(hero.position, spire).is_empty(), "Crystal Spire can't be walked to")
	_expect(sel.order_move(spire), "an order to the Crystal Spire should go by ferry")
	_expect(ferry.is_waiting(hero), "the hero should head for the ferry dock")
	var rode := false
	for i in 1200:
		hero._process(0.05)
		ferry.step(0.05)
		rode = rode or hero.riding
		if not hero.riding and not hero.is_moving() and region.platform_at(hero.position) == "Crystal Spire":
			break
	_expect(rode, "the hero should have boarded the ferry")
	_expect(region.platform_at(hero.position) == "Crystal Spire", "the ferry should land the hero on the Crystal Spire, got '%s'" % region.platform_at(hero.position))
	_expect(not ferry.is_waiting(hero) and not hero.riding, "the trip should be finished")
	# And back: an order to the Hub also goes by ferry.
	_expect(sel.order_move(region.get_platform_position("Hub") + Vector3(0, 0, 3)), "ferry back to the Hub")
	for i in 1200:
		hero._process(0.05)
		ferry.step(0.05)
		if not hero.riding and not hero.is_moving() and region.platform_at(hero.position) == "Hub":
			break
	_expect(region.platform_at(hero.position) == "Hub", "the ferry should bring the hero home")
	sel.select_units([])


func _check_storms(main: Node) -> void:
	var region: SkyRegion = main.get_node("Region")
	var storms: StormSystem = main.storms
	var build: BuildController = main.building
	storms.set_process(false)
	main.ferry.set_process(false)
	var anchors := {}
	for hex in region.tiles:
		var t: Dictionary = region.tiles[hex]
		if t.type == "harvester_anchor":
			anchors[hex] = t
			if region.buildings.has(hex):
				region.remove_building(hex).free()
	var anchor_count := 0
	for p in region.layout.platforms:
		for f in p.features:
			if f[0] == "harvester_anchor":
				anchor_count += 1
	_expect(anchors.size() == anchor_count, "expected %d harvester anchors, got %d" % [anchor_count, anchors.size()])
	var hub_anchor := Vector2i.ZERO
	for hex in anchors:
		_expect(region.clouds.has(anchors[hex].get("target", "")), "anchor %s should face a cloud" % [hex])
		if anchors[hex].platform == "Hub":
			hub_anchor = hex
	# The storm the Hub can tap sits by Ironbell's chain.
	var storm: String = anchors[hub_anchor].target
	storms.refresh()
	_expect(storms.control[storm] == "" and region.storm_bonus == 0, "storms start uncontrolled")

	main.resources.add_scrap(200)
	_expect(build.try_place("harvester", hub_anchor) == "", "place a harvester on the Hub anchor")
	storms.refresh()
	_expect(storms.control[storm] == "player", "one harvester should control the %s" % storm)
	var supply_with := region.power_supply()
	_expect(region.storm_bonus == storms.power_per_storm, "a controlled storm adds power")

	# Ironbell holds the chain platforms by that storm and builds on their anchors.
	var owners_before := {}
	var rival_anchors := 0
	for hex in anchors:
		var platform_name: String = anchors[hex].platform
		if platform_name != "Hub" and anchors[hex].target == storm:
			owners_before[platform_name] = region.platform_owner(platform_name)
			region.set_platform_owner(platform_name, "rival")
			rival_anchors += 1
	var built := 0
	while storms.rival_build() != "":
		built += 1
	_expect(built == rival_anchors, "Ironbell should build on its %d anchors, built %d" % [rival_anchors, built])
	storms.refresh()
	_expect(storms.control[storm] == "rival", "%d v 1 harvesters should give Ironbell the %s" % [rival_anchors, storm])
	_expect(region.power_supply() == supply_with - storms.power_per_storm, "losing the storm loses its power")
	_expect(is_equal_approx(main.waves.hp_bonus, storms.wave_hp_per_storm), "an Ironbell storm toughens waves")
	var rival_harvester: Building = null
	for b in region.buildings.values():
		if b.faction == "rival":
			rival_harvester = b
	_expect(build.demolish(rival_harvester.hex) == 0, "you can't demolish Ironbell's buildings")

	# Lightning from that storm hits a unit beneath it.
	var victim: Unit = main.selection.all_units()[1]
	victim.position = region.snap_to_walkable(region.hex_center(region.clouds[storm].center))
	victim.stop()
	var hp_before := victim.hp
	_expect(storms.strike(storm) == victim and victim.hp < hp_before, "the %s should strike the nearby unit" % storm)
	victim.hp = victim.max_hp

	for hex in anchors:
		if region.buildings.has(hex):
			region.remove_building(hex).free()
	for platform_name in owners_before:
		region.set_platform_owner(platform_name, owners_before[platform_name])
	storms.refresh()
	_expect(region.storm_bonus == 0 and main.waves.hp_bonus == 0.0, "storm effects clear when harvesters go")


func _check_hero_respawn(main: Node) -> void:
	var hero: Unit = main.selection.find_hero()
	hero.take_damage(100000.0)
	await process_frame
	_expect(main.selection.find_hero() == null, "a fallen Commander should leave the field")
	main._process(main.HERO_RESPAWN_SECONDS - 1.0)
	_expect(main.selection.find_hero() == null, "the Commander shouldn't be back early")
	main._process(1.5)
	var back: Unit = main.selection.find_hero()
	_expect(back != null and back.is_alive() and main.region.platform_at(back.position) == "Hub", "the Commander should respawn on the Hub")

	# Recruiting a Riveteer costs scrap and takes the training time.
	var rec: Recruiter = main.recruiter
	rec.set_process(false)
	var before: int = main.selection.all_units().size()
	main.resources.add_scrap(100)
	var scrap: int = main.resources.scrap
	_expect(rec.queue_one() == "", "queue a Riveteer")
	_expect(main.resources.scrap == scrap - Recruiter.cost_of("riveteer"), "recruiting costs scrap up front")
	rec.step(Recruiter.train_seconds_of("riveteer") - 0.5)
	await process_frame
	_expect(main.selection.all_units().size() == before, "no Riveteer before training ends")
	rec.step(1.0)
	await process_frame
	_expect(main.selection.all_units().size() == before + 1, "a trained Riveteer joins the squad")
	main.resources.scrap = 0
	_expect(rec.queue_one() != "", "recruiting needs scrap")


func _check_unit_roster(main: Node) -> void:
	var region: SkyRegion = main.get_node("Region")
	var combat: CombatSystem = main.combat
	var units_root: Node3D = main.get_node("Units")
	# These checks drive combat by hand.
	combat.set_process(false)
	main.raids.set_process(false)

	# Every trainable unit has an Army button and distinct stats.
	for type_id in UnitCatalog.TRAINABLE:
		_expect(BuildMenu.tab_of("unit:" + type_id) == "Army", "%s should be on the Army tab" % type_id)
		_expect(UnitCatalog.get_data(type_id).blurb != "", "%s needs a description" % type_id)
	var riot := UnitCatalog.make("shieldbearer")
	_expect(riot.shield > 0.5 and not riot.is_ranged() and riot.max_hp > 100.0, "Shieldbearers are shielded melee tanks")
	riot.free()
	var rifle_stats := UnitCatalog.get_data("rifleman")
	_expect(rifle_stats.range > UnitCatalog.get_data("walker").range, "Riflemen outrange walkers")
	var rival_rifle := UnitCatalog.make("rifleman", "rival")
	_expect(rival_rifle.faction == "rival" and rival_rifle.bounty > 0, "rivals can field the same units")
	var aa_rifle := UnitCatalog.make("rifleman")
	var aa_rivet := UnitCatalog.make("riveteer")
	_expect(aa_rifle.hits_air and not aa_rivet.hits_air, "Riflemen can shoot aircraft; Riveteers can't")
	aa_rifle.free()
	aa_rivet.free()
	rival_rifle.free()
	_expect(main.raids.unit_for_slot(0) == "walker" and main.raids.party_mix.has("shieldbearer"), "Ironbell mixes base troops into bigger parties")

	# The training queue takes mixed unit types in order.
	var rec: Recruiter = main.recruiter
	main.resources.add_scrap(500)
	var scrap: int = main.resources.scrap
	_expect(rec.queue_one("rifleman") == "" and rec.queue_one("shieldbearer") == "", "queue a Rifleman and a Shieldbearer")
	_expect(main.resources.scrap == scrap - Recruiter.cost_of("rifleman") - Recruiter.cost_of("shieldbearer"), "each unit costs its own price")
	var trained: Array[Unit] = []
	var grab := func(u: Unit): trained.append(u)
	rec.recruited.connect(grab)
	rec.step(Recruiter.train_seconds_of("rifleman") + 0.01)
	rec.step(Recruiter.train_seconds_of("shieldbearer") + 0.01)
	rec.recruited.disconnect(grab)
	_expect(trained.size() == 2 and trained[0].unit_type == "rifleman" and trained[1].unit_type == "shieldbearer", "units train in queue order")
	for u in trained:
		u.free()
	_expect(rec.queue_one("nonsense") != "", "unknown unit types are refused")

	# Test squad on an empty strip of sky, far from everything else.
	var base := region.get_platform_position("Hub") + Vector3(0, 0, -400)
	var spawn := func(type_id: String, faction: String, offset: Vector3) -> Unit:
		var u := UnitCatalog.make(type_id, faction)
		u.position = base + offset
		units_root.add_child(u)
		return u
	var shooter: Unit = spawn.call("rifleman", "rival", Vector3(0, 0, 0))
	var rifle: Unit = spawn.call("rifleman", "player", Vector3(0, 0, 6))
	var shield: Unit = spawn.call("shieldbearer", "player", Vector3(0, 0, 3))
	await process_frame

	# A shield catches a shot flying past it, and stops most of it.
	_expect(combat.shield_in_path(shooter.global_position, rifle) == shield, "the Shieldbearer stands in the line of fire")
	combat.deal_hit(shooter, rifle, 20.0, Color.WHITE)
	_expect(rifle.hp == rifle.max_hp, "the Rifleman behind the shield is untouched")
	_expect(is_equal_approx(shield.max_hp - shield.hp, 20.0 * (1.0 - shield.shield)), "the shield stops %d%% of a shot" % int(shield.shield * 100))
	# Off to the side, the shield doesn't help.
	shield.position.x += 4.0
	_expect(combat.shield_in_path(shooter.global_position, rifle) == null, "a shield off to the side doesn't block")
	combat.deal_hit(shooter, rifle, 20.0, Color.WHITE)
	_expect(is_equal_approx(rifle.max_hp - rifle.hp, 20.0), "an unshielded Rifleman takes the full shot")
	# Melee isn't a projectile, so a shield doesn't stop it.
	var brawler: Unit = spawn.call("shieldbearer", "rival", Vector3(4, 0, 2))
	shield.hp = shield.max_hp
	combat.deal_hit(brawler, shield, 14.0, Color.WHITE)
	_expect(is_equal_approx(shield.max_hp - shield.hp, 14.0), "melee hits go around shields")
	brawler.free()

	# Lancers wreck armor.
	var lancer: Unit = spawn.call("lancer", "player", Vector3(-3, 0, 0))
	var armored: Unit = spawn.call("walker", "rival", Vector3(-6, 0, 0))
	var walker_hp := armored.hp
	combat.deal_hit(lancer, armored, lancer.damage, Color.WHITE)
	_expect(is_equal_approx(walker_hp - armored.hp, lancer.damage * lancer.vs_armor), "a Lancer does bonus damage to armored walkers")
	_expect(not armored.is_ranged(), "walkers fight up close, so riot shields don't stop them")

	# Medics heal the most wounded ally in range.
	var medic: Unit = spawn.call("medic", "player", Vector3(1, 0, 6))
	rifle.hp = 10.0
	combat._tend(medic, "player", 1.0)
	_expect(is_equal_approx(rifle.hp, 10.0 + medic.heal_power), "a Medic heals a wounded ally")

	# Buffs: stat multipliers, refresh, expiry and auras.
	rifle.add_buff("test_drill", {"damage": 1.5, "range": 2.0, "attack_speed": 2.0}, 1.0)
	_expect(is_equal_approx(rifle.get_damage(), rifle.damage * 1.5), "a damage buff raises damage")
	_expect(is_equal_approx(rifle.get_attack_range(), rifle.attack_range * 2.0), "a range buff raises range")
	_expect(is_equal_approx(rifle.get_attack_cooldown(), rifle.attack_cooldown / 2.0), "an attack speed buff shortens the cooldown")
	rifle.tick_buffs(1.5)
	_expect(not rifle.has_buff("test_drill") and is_equal_approx(rifle.get_damage(), rifle.damage), "timed buffs run out")
	var reached := Unit.buff_allies_near(main, rifle.global_position, 3.0, "player", "test_aura", {"armor": 0.5, "regen": 4.0}, 0.5)
	_expect(reached >= 2 and rifle.has_buff("test_aura") and medic.has_buff("test_aura") and not lancer.has_buff("test_aura"), "an aura buffs allies in its radius only")
	var hp_before := rifle.hp
	rifle.take_damage(10.0)
	_expect(is_equal_approx(hp_before - rifle.hp, 5.0), "an armor buff cuts damage taken")
	hp_before = rifle.hp
	rifle.tick_buffs(0.25)
	_expect(is_equal_approx(rifle.hp - hp_before, 1.0), "a regen buff heals over time")
	rifle.remove_buff("test_aura")
	_expect(not rifle.has_buff("test_aura"), "buffs can be removed")

	for u in [shooter, armored, rifle, shield, lancer, medic]:
		u.free()

	# Sappers repair damaged buildings.
	var hub: Vector2i = region.platforms["Hub"].center
	main.resources.add_scrap(200)
	var hex := hub + Vector2i(2, -2)
	if region.buildings.has(hex):
		main.building.demolish(hex)
	_expect(main.building.try_place("rivet_turret", hex) == "", "place a turret to repair")
	var turret: Building = region.buildings[hex]
	turret.hp = turret.max_hp * 0.5
	var sapper := UnitCatalog.make("sapper")
	sapper.position = turret.global_position + Vector3(1.5, 0, 0)
	units_root.add_child(sapper)
	_expect(combat._repair(sapper, "player", 1.0) and is_equal_approx(turret.hp, turret.max_hp * 0.5 + sapper.repair_power), "a Sapper repairs a damaged building")
	_expect(is_equal_approx(UnitCatalog.get_data("sapper").vs_buildings, sapper.vs_buildings) and sapper.vs_buildings > 1.0, "Sappers hit buildings harder")
	# With nothing else to mend, a Sapper slowly repairs the Hub.
	turret.hp = turret.max_hp
	var hub_hq: Headquarters = combat.headquarters_on("Hub")
	hub_hq.hp = hub_hq.max_hp - 100.0
	sapper.position = hub_hq.global_position + Vector3(2.0, 0, 0)
	_expect(combat._repair(sapper, "player", 1.0) and hub_hq.hp > hub_hq.max_hp - 100.0 and hub_hq.hp < hub_hq.max_hp - 100.0 + sapper.repair_power,
		"a Sapper repairs the Hub, more slowly than a building")
	hub_hq.hp = hub_hq.max_hp
	sapper.free()
	main.building.demolish(hex)
	combat.set_process(true)
	main.raids.set_process(true)
	await process_frame


## Flak only shoots aircraft, ground defenses only shoot the ground and buff
## nearby allies, and hangars launch drones that fight and get rebuilt.
func _check_defense_roles(main: Node) -> void:
	var region: SkyRegion = main.get_node("Region")
	var combat: CombatSystem = main.combat
	var defenses: DefenseSystem = main.defenses
	var build: BuildController = main.building
	var res: PlayerResources = main.resources
	_expect(defenses != null, "main should have a DefenseSystem")
	if defenses == null:
		return
	for n in [combat, defenses, main.waves, main.raids, main.fleet, main.loads, main.economy, main.capture]:
		n.set_process(false)
	for e in get_root().get_tree().get_nodes_in_group(Unit.ENEMY_GROUP):
		e.free()
	for b in region.buildings.values().duplicate():
		build.demolish(b.hex)
	var units: Array[Unit] = main.selection.all_units()
	for u in units:
		u.position = region.get_platform_position("Outpost")
		u.stop()
	await process_frame
	for type_id in BuildingCatalog.BUILDINGS:
		var data: Dictionary = BuildingCatalog.BUILDINGS[type_id]
		if data.has("attack") or data.has("hangar"):
			_expect(BuildingCatalog.ROLES.has(BuildingCatalog.role_of(type_id)), "%s needs a defense role" % type_id)
		if BuildingCatalog.role_of(type_id) == "flak":
			_expect(data.attack.get("air_only", false), "%s is flak, so it should be air-only" % type_id)
		if BuildingCatalog.role_of(type_id) == "ground":
			_expect(not data.get("attack", {}).has("air"), "%s is a ground defense, so it can't hit aircraft" % type_id)

	var hub: Vector2i = region.platforms["Hub"].center
	var scrap_start := res.scrap
	res.add_scrap(1000)
	# Flak ignores a walker right in front of it.
	_expect(build.try_place("flak_battery", hub + Vector2i(2, -2)) == "", "place a Flak Battery")
	var walker: Unit = main.raids.send_party(1)[0]
	walker.position = region.hex_center(hub + Vector2i(3, -3))
	walker.stop()
	walker.damage = 0.0
	for i in 40:
		combat.step(0.05)
	_expect(walker.hp == walker.max_hp, "flak shouldn't shoot walkers")
	build.demolish(hub + Vector2i(2, -2))
	walker.free()

	# Ground support: a Rally Horn and a Rivet Turret buff a Riveteer.
	var riveteer: Unit = units[1]
	riveteer.position = region.hex_center(hub + Vector2i(0, 2))
	_expect(build.try_place("rally_horn", hub + Vector2i(-1, 2)) == "", "place a Rally Horn")
	_expect(build.try_place("rivet_turret", hub + Vector2i(1, 1)) == "", "place a Rivet Turret")
	defenses.step(1.0)
	_expect(riveteer.damage_mult > 1.0 and riveteer.cooldown_mult < 1.0, "a Rally Horn should boost nearby units")
	_expect(riveteer.armor > 0.0, "a Rivet Turret should give nearby units armor")
	_expect(not BuildingCatalog.BUILDINGS.has("mending_post"), "the Mending Post is cut (Medics heal)")
	var far: Unit = units[2]
	_expect(far.damage_mult == 1.0 and far.armor == 0.0, "units far away get no bonus")
	var before := riveteer.hp
	riveteer.take_damage(10.0)
	_expect(before - riveteer.hp < 10.0, "armor should block part of the damage")
	riveteer.hp = riveteer.max_hp
	build.demolish(hub + Vector2i(-1, 2))
	build.demolish(hub + Vector2i(1, 1))
	defenses.step(0.1)
	_expect(riveteer.damage_mult == 1.0 and riveteer.armor == 0.0, "bonuses end when the building is gone")
	riveteer.position = region.get_platform_position("Outpost")

	# Hangar: launches drones, they shoot down a bomber, and die with the hangar.
	var hangar_hex := hub + Vector2i(2, -2)
	var hangar_err := build.try_place("airship_hangar", hangar_hex)
	_expect(hangar_err == "", "place an Airship Hangar: " + hangar_err)
	var hangar: Building = region.buildings[hangar_hex]
	defenses.step(0.1)
	_expect(defenses.drones_of(hangar).size() == 1, "a new hangar launches a drone right away")
	for i in 400:
		defenses.step(0.05)
	var drones: Array = defenses.drones_of(hangar)
	_expect(drones.size() == 2, "the hangar should fill up to 2 drones, got %d" % drones.size())
	_expect(not main.selection.all_units().has(drones[0]), "drones aren't selectable squad units")
	_expect(not drones[0].is_in_group(Unit.GROUP), "drones don't count as squad units (capture, load, army size)")
	_expect(main.info_panel.describe(drones[0]).body != "", "the info card describes drones")
	_expect(main.info_panel.describe(hangar).stats.contains("Drones up: 2 / 2"), "the hangar's card shows its drones")
	var bomber: Unit = main.fleet.send_flight(1)[0]
	bomber.stop()
	bomber.position = hangar.global_position + Vector3(6, VesperFleet.ALTITUDE, 0)
	bomber.damage = 0.0
	for i in 600:
		defenses.step(0.05)
		combat.step(0.05)
		for d in defenses.drones_of(hangar):
			d._process(0.05)
		if not is_instance_valid(bomber) or bomber.hp <= 0.0:
			break
	_expect(not is_instance_valid(bomber) or bomber.hp <= 0.0, "drones should shoot down a bomber near their hangar")
	await process_frame
	drones = defenses.drones_of(hangar)
	build.demolish(hangar_hex)
	defenses.step(0.05)
	await process_frame
	var alive := drones.filter(func(d): return is_instance_valid(d))
	_expect(alive.is_empty(), "drones go down with their hangar")
	_expect(get_root().get_tree().get_nodes_in_group(Unit.DRONE_GROUP).is_empty(), "no drones left over")
	res.scrap = scrap_start


func _check_combat_and_waves(main: Node) -> void:
	var region: SkyRegion = main.get_node("Region")
	var combat: CombatSystem = main.combat
	var waves: WaveManager = main.waves
	var raids: RivalRaids = main.raids
	var build: BuildController = main.building
	var res: PlayerResources = main.resources
	for n in [combat, waves, raids, main.loads, main.economy, main.capture]:
		n.set_process(false)
	for e in get_root().get_tree().get_nodes_in_group(Unit.ENEMY_GROUP):
		e.free()
	# Clear the Hub of buildings and park player units far away.
	for b in region.buildings.values().duplicate():
		build.demolish(b.hex)
	var units: Array[Unit] = main.selection.all_units()
	for u in units:
		u.position = region.get_platform_position("Outpost")
		u.stop()
	await process_frame

	var hqs := get_root().get_tree().get_nodes_in_group(Headquarters.GROUP)
	_expect(hqs.size() == 3, "expected 3 headquarters (Hub, Ironbell, Vesper), got %d" % hqs.size())

	# A Rivet Turret kills a walker and pays its bounty.
	var hub: Vector2i = region.platforms["Hub"].center
	res.add_scrap(500)
	_expect(build.try_place("rivet_turret", hub + Vector2i(2, -2)) == "", "place a turret")
	var walker: Unit = raids.send_party(1)[0]
	walker.position = region.hex_center(hub + Vector2i(3, -3))
	walker.stop()
	_expect(combat.nearest_enemy(walker.global_position, "rival", 10.0) != null, "walker should see a target")
	var scrap_before := res.scrap
	for i in 400:
		combat.step(0.05)
		if not is_instance_valid(walker) or walker.hp <= 0.0:
			break
	_expect(not is_instance_valid(walker) or walker.hp <= 0.0, "the turret should destroy the walker")
	_expect(res.scrap == scrap_before + 8, "a walker kill should pay half its 15 bounty (8 scrap), got %d" % (res.scrap - scrap_before))
	await process_frame

	# Brownout halves a tower's damage over time.
	var turret: Building = region.buildings[hub + Vector2i(2, -2)]
	var dummy: Unit = raids.send_party(1)[0]
	dummy.max_hp = 100000.0
	dummy.hp = dummy.max_hp
	dummy.damage = 0.0
	dummy.position = region.hex_center(hub + Vector2i(3, -3))
	dummy.stop()
	turret.efficiency = 1.0
	turret.cooldown_left = 0.0
	for i in 200:
		combat.step(0.05)
	var full_damage := dummy.max_hp - dummy.hp
	dummy.hp = dummy.max_hp
	turret.efficiency = 0.5
	turret.cooldown_left = 0.0
	for i in 200:
		combat.step(0.05)
	var half_damage := dummy.max_hp - dummy.hp
	_expect(full_damage > 0.0 and half_damage > 0.0 and half_damage < full_damage * 0.7,
		"a 50%% grid should cut damage roughly in half (%d vs %d)" % [half_damage, full_damage])
	dummy.free()

	# Arc Coil lightning chains across a cluster.
	_expect(build.try_place("arc_coil", hub + Vector2i(-2, 2)) == "", "place an Arc Coil")
	build.demolish(hub + Vector2i(2, -2))
	var cluster := raids.send_party(3)
	for i in cluster.size():
		cluster[i].position = region.hex_center(hub + Vector2i(-3, 3)) + Vector3(i * 1.2, 0, 0)
		cluster[i].damage = 0.0
		cluster[i].max_hp = 1000.0
		cluster[i].hp = 1000.0
		cluster[i].stop()
	var coil: Building = region.buildings[hub + Vector2i(-2, 2)]
	coil.cooldown_left = 0.0
	combat.step(0.01)
	var hit_count := 0
	for u in cluster:
		if u.hp < 1000.0:
			hit_count += 1
	_expect(hit_count == 3, "one Arc Coil shot should hit all 3 walkers, hit %d" % hit_count)
	for u in cluster:
		u.free()
	build.demolish(hub + Vector2i(-2, 2))

	# Units fight each other.
	var riveteer: Unit = units[1]
	riveteer.position = region.hex_center(hub + Vector2i(0, 2))
	var foe: Unit = raids.send_party(1)[0]
	foe.position = riveteer.position + Vector3(2.0, 0, 0)
	foe.stop()
	for i in 40:
		combat.step(0.05)
	_expect(riveteer.hp < riveteer.max_hp and foe.hp < foe.max_hp, "adjacent units should trade blows")
	foe.free()
	riveteer.hp = riveteer.max_hp

	# Walling off the Midway walkway doesn't stop raiders: they route through
	# the wall and attack it, while player routes still respect buildings.
	var midway_hex: Vector2i = region.platforms["Midway"].center
	var entry := []
	var best := 1 << 30
	for hex in region.tiles:
		if region.tiles[hex].type != "walkway":
			continue
		var touches_hub := false
		for n in HexGrid.neighbors(hex):
			if region.get_tile(n).get("platform", "") == "Hub":
				touches_hub = true
		if not touches_hub:
			continue
		var d := HexGrid.distance(hex, midway_hex)
		if d < best - 1:
			entry = [hex]
			best = d
		elif d <= best + 1:
			entry.append(hex)
			best = mini(best, d)
	var wall := []
	for e in entry:
		if HexGrid.distance(e, midway_hex) > best + 1:
			continue
		for n in HexGrid.neighbors(e):
			if region.get_tile(n).get("platform", "") == "Hub" and region.is_hex_walkable(n) and not wall.has(n):
				wall.append(n)
	for hex in wall:
		region.place_building(Building.new().setup("rivet_turret"), hex)
	var from := region.get_platform_position("Midway")
	var to := raids._target_point()
	_expect(region.find_route(from, to).is_empty(), "the wall should block a normal route to the Hub")
	var smash := raids._route(from, to)
	_expect(not smash.is_empty(), "raiders should still find a route through the wall")
	for hex in wall:
		_expect(not region.is_hex_walkable(hex), "wall tile %s should stay blocked" % [hex])
		region.remove_building(hex).free()

	# Vesper bombers: only anti-air can hit them, and they bomb buildings.
	var fleet: VesperFleet = main.fleet
	fleet.set_process(false)
	var bomber: Unit = fleet.send_flight(1)[0]
	_expect(bomber.flying and bomber.position.y > 5.0, "bombers fly high")
	_expect(bomber.is_moving(), "a new bomber flies its air lane")
	var dynamo_hex := hub + Vector2i(-2, 1)
	_expect(build.try_place("dynamo", dynamo_hex) == "", "place a dynamo for the bomber")
	var dynamo: Building = region.buildings[dynamo_hex]
	bomber.position = dynamo.global_position + Vector3.UP * VesperFleet.ALTITUDE
	bomber.stop()
	_expect(combat.nearest_enemy(bomber.global_position, "player", 20.0, false) != bomber, "ground-only weapons can't target aircraft")
	_expect(combat.nearest_enemy(bomber.global_position, "player", 20.0, true) == bomber, "anti-air weapons can")
	_expect(not region.units_on_platform("Hub", Unit.ENEMY_GROUP).has(bomber), "aircraft don't stand on platforms")
	var riveteer_far: Unit = units[2]
	riveteer_far.position = region.get_platform_position("Outpost")
	bomber.cooldown_left = 0.0
	var dynamo_hp := dynamo.hp
	combat.step(0.05)
	_expect(dynamo.hp < dynamo_hp, "the bomber should bomb the dynamo below it")
	# A Flak Battery brings it down quickly.
	_expect(build.try_place("flak_battery", hub + Vector2i(-1, 2)) == "", "place a Flak Battery")
	for i in 200:
		combat.step(0.05)
		if not is_instance_valid(bomber) or bomber.hp <= 0.0:
			break
	_expect(not is_instance_valid(bomber) or bomber.hp <= 0.0, "flak should shoot the bomber down")
	await process_frame
	# An idle bomber picks the nearest player building.
	var lost: Unit = fleet.send_flight(1)[0]
	lost.stop()
	lost.position = region.get_platform_position("Outpost") + Vector3.UP * VesperFleet.ALTITUDE
	fleet.step()
	_expect(lost.is_moving(), "an idle bomber should head for a target")
	lost.free()
	for hex in [dynamo_hex, hub + Vector2i(-1, 2)]:
		if region.buildings.has(hex):
			build.demolish(hex)

	# Waves: the build timer starts wave 1 with 3 walkers; clearing it starts the next build phase.
	_expect(waves.phase == WaveManager.BUILD and waves.wave == 1, "game starts in the build phase")
	waves.step(waves.time_left + 0.1)
	_expect(waves.phase == WaveManager.WAVE and waves.remaining() == 3, "wave 1 should send 3 walkers")
	for e in get_root().get_tree().get_nodes_in_group(Unit.ENEMY_GROUP):
		e.take_damage(10000.0)
	await process_frame
	waves.step(0.1)
	_expect(waves.phase == WaveManager.BUILD and waves.wave == 2, "clearing wave 1 should start the build phase for wave 2")
	_expect(waves.party_size_for(2) == 4 and waves.party_size_for(50) == waves.max_party, "waves grow up to a cap")
	_expect(waves.flight_size_for(2) == 0 and waves.flight_size_for(3) == 1 and waves.flight_size_for(50) == waves.max_flight, "Vesper flights start in wave 3 and grow")
	waves.start_wave()
	_expect(waves.remaining() == 4, "starting early sends wave 2 now: 4 walkers, got %d" % waves.remaining())
	for e in get_root().get_tree().get_nodes_in_group(Unit.ENEMY_GROUP):
		e.take_damage(10000.0)
	await process_frame

	# The match lasts match_waves waves from first contact (walkways are
	# prebuilt here, so contact was wave 1).
	_expect(waves.final_wave() == waves.contact_wave.values().min() + waves.match_waves - 1, "the last wave is counted from first contact, got %d" % waves.final_wave())
	# One rival down isn't a win, and that rival stops attacking.
	var won := [false]
	waves.game_over.connect(func(w): won[0] = w)
	combat.headquarters_on("Ironbell HQ").take_damage(100000.0)
	_expect(waves.phase != WaveManager.OVER, "the game goes on while Vesper stands")
	waves.step(0.1)
	_expect(waves.phase == WaveManager.BUILD, "clearing wave 2 starts the next build phase")
	waves.start_wave()
	var walkers := 0
	for e in get_root().get_tree().get_nodes_in_group(Unit.ENEMY_GROUP):
		if not e.flying:
			walkers += 1
	_expect(walkers == 0 and waves.remaining() > 0, "with Ironbell HQ gone, only Vesper attacks")
	for e in get_root().get_tree().get_nodes_in_group(Unit.ENEMY_GROUP):
		e.take_damage(10000.0)
	await process_frame
	waves.step(0.1)
	# Victory when both rival headquarters have fallen.
	combat.headquarters_on("Vesper Aerodrome").take_damage(100000.0)
	_expect(waves.phase == WaveManager.OVER and won[0], "destroying both rival headquarters should win")
	# Surviving the last wave wins too.
	waves.phase = WaveManager.WAVE
	waves.wave = waves.final_wave()
	won[0] = false
	waves.step(0.1)
	_expect(waves.phase == WaveManager.OVER and won[0], "clearing the final wave wins the match")


## The map rules hold for many seeds: rival headquarters in two different
## compass directions at least 90 degrees apart, 4 to 9 platforms between
## the Hub and each, and every platform reachable on foot or by ferry.
## Airships steer around islands, and the wind turns their attack routes.
func _check_air_routes(main: Node) -> void:
	var region: SkyRegion = main.region
	var fleet: VesperFleet = main.fleet
	var wind: WindSystem = main.wind
	var nav := fleet.nav
	_expect(nav != null and wind != null and fleet.wind == wind, "the fleet plans with the wind")
	var from := region.get_platform_position(fleet.home)
	var hub := region.get_platform_position("Hub")
	# Does the straight line from the Aerodrome to the Hub cross an island?
	var straight_blocked := false
	for i in 200:
		var p := region.platform_at(from.lerp(hub, i / 200.0))
		if p != "" and p != fleet.home and p != "Hub":
			straight_blocked = true
	var route := nav.plan(from, hub)
	_expect(not route.is_empty() and route[route.size() - 1].distance_to(Vector3(hub.x, 0, hub.z)) < 0.01, "an airship route ends at its target")
	_expect(_route_over_islands(region, from, route, [fleet.home, "Hub"]) == "", "airship route crosses %s" % _route_over_islands(region, from, route, [fleet.home, "Hub"]))
	if straight_blocked:
		_expect(route.size() > 1, "with islands in the way, the airship should bend around them")
	# Lanes are drawn along planned routes, and avoid islands too.
	var drawn := region.air_lane_routes()
	_expect(drawn.size() == fleet.lanes().size() and drawn.size() > 0, "every Vesper lane is drawn")
	for lane in drawn:
		var pts: PackedVector3Array = lane[2]
		_expect(_route_over_islands(region, pts[0], pts.slice(1), [lane[0], lane[1]]) == "", "drawn lane %s to %s avoids islands" % [lane[0], lane[1]])
		var node := region.get_node_or_null(("AirLane_%s_%s" % [lane[0], lane[1]]).replace(" ", ""))
		_expect(node != null and node.get_child_count() > 0, "lane %s to %s has markers" % [lane[0], lane[1]])
	# Attacks come in from upwind: the last leg runs with the wind.
	var old_wind := wind.from_index
	var old_routes := {}
	for lane in fleet.lanes():
		old_routes[lane[1]] = fleet.route_for(lane)
	var stage = nav.staging_point(from, hub)
	_expect(stage != null, "with wind, the flight gathers upwind of its target")
	if stage != null:
		var run: Vector3 = (Vector3(hub.x, 0, hub.z) - stage).normalized()
		_expect(run.dot(wind.blowing()) > 0.6, "the bombing run goes downwind")
	# Every 3 waves the wind turns at least 90 degrees and the lanes move.
	_expect(wind.waves_until_shift(1) == 3 and wind.waves_until_shift(3) == 1, "wind turns every 3 waves")
	wind._on_phase_changed(WaveManager.BUILD, 3)
	_expect(wind.from_index == old_wind, "wind holds before wave 4")
	wind._on_phase_changed(WaveManager.BUILD, 4)
	_expect(LevelLayout.compass_gap(wind.from_index, old_wind) >= 2, "wind turns at least 90 degrees before wave 4")
	_expect(wind.since_wave == 4 and wind.waves_until_shift(4) == 3, "next turn is 3 waves later")
	var nb := wind.blowing()
	_expect(nav.wind.distance_to(Vector2(nb.x, nb.z)) < 0.01, "the fleet hears the new wind")
	var moved := 0
	for lane in fleet.lanes():
		if fleet.route_for(lane) != old_routes[lane[1]]:
			moved += 1
	_expect(moved > 0, "turning the wind changes the attack routes")
	# Put things back for the wave tests.
	wind.since_wave = 1
	wind.from_index = old_wind
	wind.wind_changed.emit(old_wind, true)


## Vesper's bombers go for your outer island with the most built on it,
## the lane is redrawn to it, and airship buttons wait for a Hangar.
func _check_bomb_target(main: Node) -> void:
	var region: SkyRegion = main.region
	var fleet: VesperFleet = main.fleet
	var owner_before := region.platform_owner("Generator Rig")
	region.set_platform_owner("Generator Rig", "")
	_expect(fleet.bomb_target("Vesper") == "Hub", "with no outer islands built on, bombers go for the Hub")
	region.set_platform_owner("Generator Rig", "player")
	var hex := Vector2i(999, 999)
	for h in region.tiles_of_platform("Generator Rig"):
		if not region.buildings.has(h) and region.get_tile(h).type in ["deck", "generator_socket"]:
			hex = h
			break
	var placed := false
	if hex != Vector2i(999, 999):
		region.place_building(Building.new().setup("dynamo"), hex)
		placed = true
	_expect(fleet.bomb_target("Vesper") == "Generator Rig", "bombers go for the outer island you built on, got %s" % fleet.bomb_target("Vesper"))
	fleet.refresh_lanes()
	var to := region.air_lane_routes().map(func(l): return l[1])
	_expect(to == ["Generator Rig"], "Vesper's one drawn lane leads to its target, got %s" % [to])
	if placed:
		region.remove_building(hex)
	region.set_platform_owner("Generator Rig", owner_before)
	fleet.refresh_lanes()
	# Airship buttons say they need a Hangar while you have none.
	var menu: BuildMenu = main.build_menu
	if main.patrols.hangars.is_empty():
		menu.show_tab("Army")
		var b: Button = menu._entry_buttons.get("ship:interceptor")
		_expect(b != null, "the Army tab has an Interceptor button")
		if b:
			menu.refresh()
			_expect(b.text.contains("needs a Hangar") and b.modulate.a < 0.5, "the Interceptor button is greyed without a Hangar")


## Rivals launch airships in waves: Ironbell carriers drop troops on your
## platforms, Vesper gunships hunt your units, and the wind sets their speed.
func _check_rival_airships(main: Node) -> void:
	var region: SkyRegion = main.region
	var fleet: VesperFleet = main.fleet
	var waves: WaveManager = main.waves
	var combat: CombatSystem = main.combat
	fleet.set_process(false)
	# Wave data the top bar reads.
	_expect(waves.carriers_for(4) == 0 and waves.carriers_for(5) == 1 and waves.carriers_for(99) == waves.max_carriers, "carriers start in wave 5 and grow")
	_expect(waves.gunships_for(6) == 0 and waves.gunships_for(7) == 1, "gunships start in wave 7")
	var kinds := waves.composition_for(7).map(func(e): return e.unit)
	_expect(kinds.has("carrier") and kinds.has("gunship") and kinds.has("bomber") and kinds.has("walker"), "wave 7 sends walkers, carriers, bombers and gunships: %s" % [kinds])
	var plan_text := str(waves.wave_plan(7))
	_expect(plan_text.contains("Troop Carrier") and plan_text.contains("Gunship"), "the wave preview lists the airships")
	# A carrier flies around islands to your platform and drops its squad.
	var carrier: Unit = fleet.launch("carrier", 1)[0]
	var target: String = carrier.get_meta("carrier_target")
	_expect(region.platform_owner(target) == "player", "carriers aim for one of your platforms")
	_expect(carrier.flying and carrier.is_moving() and not carrier.attack_move, "a carrier flies without stopping to fight")
	var dropped := []
	fleet.troops_dropped.connect(func(_c, p, units): dropped.append([p, units]), CONNECT_ONE_SHOT)
	carrier.stop()
	carrier.position = region.get_platform_position(target) + Vector3.UP * VesperFleet.ALTITUDE
	fleet.step(0.1)
	_expect(carrier.get_meta("carrier_state") == "unloading", "over its target, the carrier hovers to unload")
	fleet.step(VesperFleet.UNLOAD_SECONDS)
	_expect(dropped.size() == 1 and dropped[0][1].size() == VesperFleet.AIRSHIPS.carrier.troops.size(), "the carrier drops its squad")
	if dropped.size() == 1:
		for u in dropped[0][1]:
			_expect(region.platform_at(u.position) == target and not u.flying, "dropped troops land on %s" % target)
			u.free()
	_expect(carrier.get_meta("carrier_state") == "outbound" and carrier.is_moving(), "an empty carrier flies home")
	carrier.free()
	# A gunship hunts a unit of yours and can hit aircraft.
	var gun: Unit = fleet.launch("gunship", 1)[0]
	_expect(gun.targets_units and gun.hits_air, "gunships fight units and aircraft")
	var prey: Unit = main.selection.all_units()[0]
	gun.stop()
	gun.position = prey.global_position + Vector3(12, VesperFleet.ALTITUDE, 0)
	fleet.step(0.1)
	_expect(gun.is_moving() and gun.next_waypoint().distance_to(Vector3(prey.global_position.x, 0, prey.global_position.z)) < 1.0, "an idle gunship goes after your nearest unit")
	# Airships ride the wind.
	var blow: Vector3 = main.wind.blowing()
	gun.set_route(PackedVector3Array([gun.position + blow * 10.0]))
	_expect(fleet.wind_speed_for(gun) > 1.2, "a tailwind speeds an airship up")
	gun.set_route(PackedVector3Array([gun.position - blow * 10.0]))
	_expect(fleet.wind_speed_for(gun) < 0.8, "a headwind slows it down")
	gun.free()
	fleet.set_process(true)
	await process_frame


## Turbine Engines go only on turbine islands; with 4 the island can be
## steered, breaking its walkways after a warning and carrying its buildings.
func _check_island_steering(main: Node) -> void:
	var region: SkyRegion = main.region
	var steer: IslandSteering = main.steering
	var build: BuildController = main.building
	var turbine := ""
	for p in region.platforms:
		if region.platforms[p].get("style", "") == "turbine" and not region.platforms[p].get("balloon", false):
			turbine = p
			break
	_expect(turbine != "", "seed 3 has a turbine island")
	if turbine == "":
		return
	main.resources.add_scrap(2000)
	region.set_platform_owner("Hub", "player")
	_expect(build.try_place(IslandSteering.ENGINE, region.platforms["Hub"].center + Vector2i(1, 1)).contains("turbine"), "engines only fit on turbine islands")
	region.set_platform_owner(turbine, "player")
	var spots: Array[Vector2i] = []
	for hex in region.tiles_of_platform(turbine):
		if region.build_problem(IslandSteering.ENGINE, hex) == "":
			spots.append(hex)
	_expect(spots.size() >= 4, "room for 4 engines on %s" % turbine)
	if spots.size() < 4:
		return
	for i in 3:
		_expect(build.try_place(IslandSteering.ENGINE, spots[i]) == "", "build an engine on %s" % turbine)
	_expect(steer.steer_problem(turbine).contains("needs 4"), "3 engines aren't enough: %s" % steer.steer_problem(turbine))
	_expect(build.try_place(IslandSteering.ENGINE, spots[3]) == "", "build a 4th engine")
	region.storm_bonus += 200
	_expect(steer.steer_problem(turbine) == "", "4 engines and spare power let you steer: %s" % steer.steer_problem(turbine))
	var old_center: Vector2i = region.platforms[turbine].center
	var engine_hex := spots[0]
	var engine: Building = region.buildings[engine_hex]
	var dir := -1
	for d in 6:
		if steer._clear_at(turbine, HexGrid.DIRECTIONS[d]):
			dir = d
			break
	_expect(dir >= 0, "%s has open sky on some side" % turbine)
	if dir < 0:
		return
	var tile_count := region.tiles_of_platform(turbine).size()
	# A stub of walkway on the far side, which will break off.
	var stub = null
	for hex in region.tiles_of_platform(turbine):
		var out: Vector2i = hex - HexGrid.DIRECTIONS[dir]
		if not region.tiles.has(out):
			stub = out
			break
	if stub != null:
		region.add_tiles({stub: {"type": "walkway", "platform": ""}})
	_expect(steer.steer(turbine, dir, 2) == "", "order the island to move")
	_expect(region.power_demand() >= IslandSteering.STEER_POWER, "moving engines draw power")
	_expect(steer.moving[turbine].state == IslandSteering.WARNING, "it warns before moving")
	steer.step(steer.warning_seconds + 0.1)
	_expect(steer.moving.has(turbine) and steer.moving[turbine].state == IslandSteering.MOVING, "after the warning it moves")
	_expect(stub == null or not region.tiles.has(stub), "its walkways break off")
	for i in 400:
		if not steer.moving.has(turbine):
			break
		steer.step(0.1)
	var new_center: Vector2i = region.platforms[turbine].center
	_expect(not steer.moving.has(turbine), "the island stops")
	_expect(HexGrid.distance(new_center, old_center) >= 1, "the island moved (from %s to %s)" % [old_center, new_center])
	_expect(region.tiles_of_platform(turbine).size() == tile_count, "the island keeps its shape")
	_expect(is_instance_valid(engine) and region.buildings.get(engine.hex) == engine and engine.hex == engine_hex + new_center - old_center, "its buildings ride along")
	_expect(region.engine_draw == 0, "engines stop drawing power once it stops")
	_expect(steer.engines_on(turbine) == 4, "still 4 engines aboard")
	region.storm_bonus -= 200


## Player airships: built at an Airship Hangar, patrolling Mooring Masts,
## hunting only within reach of a hangar or mast, with three roles.
func _check_air_patrols(main: Node) -> void:
	var region: SkyRegion = main.region
	var patrols: AirPatrols = main.patrols
	var build: BuildController = main.building
	var combat: CombatSystem = main.combat
	patrols.set_process(false)
	main.resources.add_scrap(3000)
	region.storm_bonus += 200
	_expect(patrols.queue_ship("interceptor").contains("Hangar"), "ships need a hangar first")
	var spots: Array[Vector2i] = []
	for hex in region.tiles_of_platform("Hub"):
		if region.build_problem(AirPatrols.HANGAR, hex) == "" and HexGrid.distance(hex, region.platforms["Hub"].center) >= 2:
			spots.append(hex)
	_expect(spots.size() >= 3, "room on the Hub for a hangar and two masts")
	if spots.size() < 3:
		return
	_expect(build.try_place(AirPatrols.HANGAR, spots[0]) == "", "build an Airship Hangar")
	_expect(build.try_place(AirPatrols.MAST, spots[spots.size() - 1]) == "", "build a Mooring Mast")
	_expect(build.try_place(AirPatrols.MAST, spots[spots.size() / 2]) == "", "build a second Mooring Mast")
	var hangar: Building = region.buildings[spots[0]]
	var far_mast: Building = region.buildings[spots[spots.size() - 1]]
	var near_mast: Building = region.buildings[spots[spots.size() / 2]]
	_expect(patrols.queue_ship("interceptor") == "", "order an interceptor")
	patrols.step(AirPatrols.SHIPS.interceptor.build_seconds + 0.1)
	_expect(patrols.hangars.has(hangar) and patrols.hangars[hangar].ships.size() == 1, "the hangar launches the ship")
	var ship: Unit = patrols.hangars[hangar].ships[0]
	_expect(ship.flying and ship.is_drone and ship.air_only and ship.faction == "player", "an interceptor is a player airship that hits only aircraft")
	_expect(not main.selection.all_units().has(ship), "patrol ships fly themselves")
	_expect(patrols.route_of(hangar).size() == 2, "without a set route, ships visit every patrol point")
	patrols.set_route(hangar, [near_mast])
	_expect(patrols.route_of(hangar) == [near_mast], "a set route is followed")
	patrols.step(0.1)
	_expect(ship.is_moving(), "the ship sets out on patrol")
	# Air-to-air ignores ground troops.
	var walker := UnitCatalog.make("walker", "rival")
	walker.position = Vector3(ship.position.x + 2, 0, ship.position.z)
	main.get_node("Units").add_child(walker)
	_expect(combat.nearest_enemy(ship.global_position, "player", 10.0, ship.hits_air, ship.targets_units, ship.air_only) == null, "interceptors ignore ground troops")
	# No fuel: a ship far from home doesn't run dry or crash.
	_expect(not ship.has_meta("fuel"), "ships have no fuel to manage")
	ship.stop()
	ship.position = near_mast.global_position + Vector3(30, AirPatrols.ALTITUDE, 0)
	for i in 100:
		patrols.step(0.5)
	_expect(is_instance_valid(ship) and ship.is_alive(), "a ship far out for a long time doesn't crash")
	# Range: ships only hunt inside the sky your hangars and masts cover.
	_expect(patrols.in_range(near_mast.global_position), "the sky over a mast is covered")
	_expect(not patrols.in_range(near_mast.global_position + Vector3(AirPatrols.PATROL_RANGE * 4, 0, 0)), "far-off sky isn't covered")
	_expect(patrols.hunt_radius(ship) == AirPatrols.HUNT_RADIUS or far_mast.global_position.distance_to(ship.global_position) <= AirPatrols.MAST_RADIUS + 7, "hunt radius away from a mast")
	ship.position = far_mast.global_position + Vector3.UP * AirPatrols.ALTITUDE
	_expect(patrols.hunt_radius(ship) == AirPatrols.HUNT_RADIUS * 2.0, "near a Mooring Mast, ships spot twice as far")
	# Gunboat: air-to-ground.
	_expect(patrols.queue_ship("gunboat") == "", "order a gunboat")
	patrols.step(AirPatrols.SHIPS.gunboat.build_seconds + 0.1)
	var gunboat: Unit = patrols.hangars[hangar].ships[1]
	_expect(not gunboat.hits_air and gunboat.targets_units, "a gunboat hits the ground, not the air")
	gunboat.position = walker.position + Vector3(1, AirPatrols.ALTITUDE, 0)
	_expect(combat.nearest_enemy(gunboat.global_position, "player", gunboat.attack_range, gunboat.hits_air, gunboat.targets_units, gunboat.air_only) == walker, "a gunboat targets ground troops")
	walker.free()
	# Utility: pick the job first.
	_expect(patrols.next_utility_job() == "scout", "the utility job cycles to scout")
	_expect(patrols.queue_ship("utility") == "", "order a scout tender")
	patrols.utility_job = "troops"
	_expect(patrols.queue_ship("utility") == "", "order a troop tender")
	patrols.step(AirPatrols.SHIPS.utility.build_seconds + 0.1)
	patrols.step(AirPatrols.SHIPS.utility.build_seconds + 0.1)
	var ships: Array = patrols.hangars[hangar].ships
	_expect(ships.size() == 4, "the hangar holds 4 ships")
	_expect(patrols.queue_ship("interceptor").contains("full"), "a full hangar takes no more")
	var scout: Unit = ships[2]
	var troop: Unit = ships[3]
	_expect(scout.display_name == "Scout Tender" and scout.get_meta("sight") > main.fog.unit_sight, "a scout tender sees further")
	_expect(troop.display_name == "Troop Tender" and troop.get_meta("troops") == 3, "a troop tender carries 3 troops")
	troop.position = region.get_platform_position("Hub") + Vector3.UP * AirPatrols.ALTITUDE
	var dropped := patrols.drop_troops(troop)
	_expect(dropped.size() == 3 and dropped.all(func(u): return region.platform_at(u.position) == "Hub"), "troops land on the deck below")
	_expect(troop.get_meta("state") == "reload", "an empty troop tender flies home to reload")
	for u in dropped:
		u.free()
	# Damaged buildings get mended by a repair tender.
	var repairer: Unit = patrols._launch(hangar, "utility:repair")
	repairer.position = hangar.global_position + Vector3.UP * AirPatrols.ALTITUDE
	hangar.take_damage(50.0)
	var hp := hangar.hp
	patrols._repair_near(repairer, 1.0)
	_expect(hangar.hp > hp, "a repair tender mends buildings below")
	# Losing the only hangar downs its ships.
	build.demolish(spots[0])
	patrols.step(0.1)
	await process_frame
	_expect(not is_instance_valid(ship) or not ship.is_alive(), "ships go down with their only hangar")
	region.storm_bonus -= 200
	patrols.set_process(true)


## First platform (other than `allowed`) that a flight along `route` from
## `from` passes over, or "".
## A four-rival map: every rival from RivalCatalog takes part in the waves,
## each walking rival bridges and sends its own raiders.
func _check_four_rivals() -> void:
	SkyRegion.rivals_override = RivalCatalog.layout_rivals(4)
	SkyRegion.seed_override = 4
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.drift.set_process(false)
	main.waves.set_process(false)
	var waves: WaveManager = main.waves
	_expect(waves.rival_corps() == ["Ironbell", "Vesper", "Nimbus", "Aurum"], "four rivals take part, got %s" % [waves.rival_corps()])
	_expect(main.all_raids.has("Nimbus") and main.all_raids.has("Aurum") and not main.all_raids.has("Vesper"), "each walking rival gets raids")
	_expect(main.bridges.crews.size() == 3, "Ironbell, Nimbus and Aurum bridge, got %d" % main.bridges.crews.size())
	var corps_sending := {}
	for entry in waves.composition_for(7):
		corps_sending[entry.corp] = true
	_expect(corps_sending.size() == 4, "every rival sends something by wave 7, got %s" % [corps_sending.keys()])
	_expect(waves.wave_plan(7).size() == 4, "the top bar gets a card per rival")
	waves.wave = 4
	waves.start_wave()
	var by_corp := {}
	for e in get_root().get_tree().get_nodes_in_group(Unit.ENEMY_GROUP):
		by_corp[e.get_meta("corp", "")] = by_corp.get(e.get_meta("corp", ""), 0) + 1
	_expect(by_corp.get("Nimbus", 0) == RivalCatalog.count_for("Nimbus", "ground", 4), "Nimbus sends its wave 4 party, got %s" % [by_corp])
	_expect(by_corp.get("Aurum", 0) == RivalCatalog.count_for("Aurum", "ground", 4), "Aurum sends its wave 4 party")
	_expect(waves.remaining_for("Aurum") > 0, "Aurum's raiders count toward the wave")
	main.queue_free()
	await process_frame
	SkyRegion.rivals_override = []
	SkyRegion.seed_override = 3


func _route_over_islands(region: SkyRegion, from: Vector3, route: PackedVector3Array, allowed: Array) -> String:
	var prev := from
	for point in route:
		var steps := int(ceil(prev.distance_to(point) / 0.4))
		for s in range(steps + 1):
			var p := region.platform_at(prev.lerp(point, float(s) / maxi(steps, 1)))
			if p != "" and not allowed.has(p):
				return p
		prev = point
	return ""


func _check_layout_rules() -> void:
	for map_seed in 40:
		var l := LevelLayout.generate(map_seed)
		_expect(not l.is_empty(), "seed %d should make a map" % map_seed)
		if l.is_empty():
			continue
		var iron: int = LevelLayout.COMPASS.find(l.directions.Ironbell)
		var vesper: int = LevelLayout.COMPASS.find(l.directions.Vesper)
		_expect(iron >= 0 and vesper >= 0 and LevelLayout.compass_gap(iron, vesper) >= 2,
			"seed %d: rival directions %s should differ by 90 degrees or more" % [map_seed, l.directions])
		for corp in ["Ironbell", "Vesper"]:
			var between: int = l.paths[corp].size() - 2
			_expect(between >= LevelLayout.MIN_BETWEEN and between <= LevelLayout.MAX_BETWEEN,
				"seed %d: %d platforms between Hub and %s" % [map_seed, between, corp])
		# Every platform is joined to the Hub by walkways or the ferry.
		var linked := {"Hub": true}
		var links: Array = l.walkways + l.ferry_routes
		var grew := true
		while grew:
			grew = false
			for w in links:
				if linked.has(w[0]) != linked.has(w[1]):
					linked[w[0]] = true
					linked[w[1]] = true
					grew = true
		_expect(linked.size() == l.platforms.size(), "seed %d: every platform should be reachable" % map_seed)
		# Island outlines: inside their radius, holding their fixed features,
		# and an island type for each.
		for p in l.platforms:
			_expect(p.style in ["city", "turbine", "crystal", "rock"], "seed %d: %s has no island type" % [map_seed, p.name])
			_expect(p.shape.has(Vector2i.ZERO), "seed %d: %s's outline should include its centre" % [map_seed, p.name])
			for off in p.shape:
				_expect(HexGrid.distance(Vector2i.ZERO, off) <= p.radius, "seed %d: %s's outline leaves its radius" % [map_seed, p.name])
			for f in p.features:
				if f[1] is Vector2i:
					_expect(p.shape.has(f[1]), "seed %d: %s's %s is off the island" % [map_seed, p.name, f[0]])
			if p.style == "crystal":
				_expect(p.get("variant", "") in ["grassy", "overcharged"], "seed %d: crystal island %s needs a variant" % [map_seed, p.name])
		# HQ really is in its compass direction.
		for p in l.platforms:
			if p.has("corp"):
				var w := HexGrid.to_world(p.center, LevelLayout.TILE_SIZE)
				var idx := posmod(roundi(atan2(-w.z, w.x) / (PI / 4.0)), 8)
				_expect(LevelLayout.COMPASS[idx] == l.directions[p.corp], "seed %d: %s should lie %s" % [map_seed, p.name, l.directions[p.corp]])
	# Up to four rivals: four headquarters, each in its own direction.
	var four := [
		{"corp": "Ironbell", "hq": "Ironbell HQ", "first": "Midway"},
		{"corp": "Vesper", "hq": "Vesper Aerodrome", "first": "Outpost"},
		{"corp": "Third", "hq": "Third HQ", "first": "Third Reach"},
		{"corp": "Fourth", "hq": "Fourth HQ", "first": "Fourth Reach"},
	]
	for map_seed in 20:
		var l4 := LevelLayout.generate(map_seed, four)
		_expect(not l4.is_empty() and l4.paths.size() == 4, "seed %d should fit four rivals" % map_seed)
		if l4.is_empty():
			continue
		var dirs := {}
		for corp in l4.directions:
			dirs[l4.directions[corp]] = true
			var between: int = l4.paths[corp].size() - 2
			_expect(between >= LevelLayout.MIN_BETWEEN and between <= LevelLayout.MAX_BETWEEN, "seed %d: %d platforms to %s" % [map_seed, between, corp])
		_expect(dirs.size() == 4, "seed %d: four rivals need four directions, got %s" % [map_seed, l4.directions])
	var three := LevelLayout.generate(5, four.slice(0, 3))
	_expect(not three.is_empty() and three.paths.size() == 3, "three rivals should fit too")
	var again := LevelLayout.generate(7)
	_expect(again.platforms.size() == LevelLayout.generate(7).platforms.size(), "the same seed makes the same map")
