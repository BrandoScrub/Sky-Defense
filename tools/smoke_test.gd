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
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	_check_scene(main)
	_check_camera(main.get_node("RtsCamera"))
	_check_routing(main.get_node("Region"))
	await _check_selection_and_orders(main)
	_check_building(main)
	await _check_claiming_walkways_and_raids(main)
	_check_weight_power_income(main)
	await _check_combat_and_waves(main)
	if _failures == 0:
		print("Smoke test passed")
	else:
		printerr("Smoke test failed: %d problem(s)" % _failures)
	quit(1 if _failures > 0 else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)


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
	_expect(region.walkway_count == 5, "expected 5 walkways")
	_expect(region.tiles_in_clouds.size() == 2, "expected 2 storm clouds")
	var types := {}
	for hex in region.tiles:
		types[region.tiles[hex].type] = true
	for t in ["core", "rival_core", "generator_socket", "harvester_anchor", "scrap_heap", "crystal_seam", "dock", "spawn", "walkway"]:
		_expect(types.has(t), "no %s tile in the layout" % t)
	_expect(region.has_node("Tiles") and region.get_node("Tiles").get_child_count() == region.tiles.size(),
		"every tile should have a placeholder mesh")


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
	_expect(region.platforms_along(hub + Vector3(0, 0, 3), route) == PackedStringArray(["Hub", "Midway", "Ironbell HQ"]),
		"Hub to Ironbell HQ should go via Midway, got %s" % [region.platforms_along(hub + Vector3(0, 0, 3), route)])
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
	_expect(start_scrap == 200, "player should start with 200 scrap")

	var deck := hub + Vector2i(2, 0)
	_expect(region.get_tile(deck).type == "deck", "test tile should be plain deck")
	_expect(build.try_place("dynamo", deck) == "", "a Dynamo on Hub deck should be allowed")
	_expect(res.scrap == start_scrap - 40, "Dynamo should cost 40 scrap")
	_expect(region.platform_load("Hub") == 3, "Dynamo should add 3 weight")
	_expect(region.power_supply() == 10, "Dynamo on deck should supply 10")
	_expect(not region.is_hex_walkable(deck), "a building blocks its tile")
	_expect(build.try_place("rivet_turret", deck) != "", "can't build on an occupied tile")

	var socket := hub + Vector2i(2, -1)
	_expect(region.get_tile(socket).type == "generator_socket", "Hub should have a generator socket at (2,-1)")
	_expect(build.try_place("dynamo", socket) == "", "a Dynamo on a socket should be allowed")
	_expect(region.power_supply() == 25, "a socketed Dynamo should supply 15")

	_expect(build.try_place("harvester", hub + Vector2i(-2, 0)) != "", "harvesters need an anchor")
	var anchor := Vector2i(999, 999)
	for hex in region.tiles_of_platform("Hub"):
		if region.get_tile(hex).type == "harvester_anchor":
			anchor = hex
	_expect(build.try_place("harvester", anchor) == "", "a harvester on the Hub anchor should be allowed")
	_expect(region.power_supply() == 55, "harvester should add 30 power")

	res.add_scrap(100)
	var coil_err := build.try_place("arc_coil", hub + Vector2i(-2, 2))
	_expect(coil_err == "", "an Arc Coil should be allowed: " + coil_err)
	_expect(region.power_demand() == 8, "Arc Coil should draw 8")
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
	_expect(region.platform_load("Hub") == 2 + 3 + 4, "load after demolish should be 9, got %d" % region.platform_load("Hub"))

	# Build mode hotkeys create and clear the ghost.
	build.start_placing("flak_battery")
	_expect(build.placing == "flak_battery" and build._ghost != null, "start_placing should show a ghost")
	build.cancel_placing()
	_expect(build.placing == "" and build._ghost == null, "cancel_placing should clear the ghost")


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
	var from_hex: Vector2i = region._rim_toward(foundry_data, crystal.center, true)
	var to_hex: Vector2i = region._rim_toward(crystal, foundry_data.center, true)
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
	_expect(raids.next_objective(party[0].position) == "Midway", "raiders should go for Midway first")
	for i in 1600:
		raids._process(0.05)
		for u in party:
			u._process(0.05)
		capture.step(0.05)
	_expect(region.platform_owner("Midway") == "rival", "raiders should claim Midway")
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
	_expect(region.platform_load("Generator Rig") == 14, "units add their weight (hero 2 + 4 x 1)")
	loads.step(0.1)
	_expect(loads.state_of("Generator Rig") == LoadSystem.FAILING, "140% load should be failing")
	_expect(is_equal_approx(units[0].speed_multiplier, 0.4), "units on a failing platform move at 40%")
	loads.step(6.0)
	_expect(region.buildings_on("Generator Rig").size() == 2, "the newest building should break off")
	_expect(not region.buildings.has(rig + Vector2i(-1, 0)), "the Flak Battery (newest) is the one lost")
	loads.step(0.1)
	_expect(loads.state_of("Generator Rig") == LoadSystem.SWAYING, "110% load should sway")
	_expect(is_equal_approx(units[0].speed_multiplier, 1.0), "swaying doesn't slow units")

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
	economy.step(10.0)
	_expect(res.scrap == scrap_before + 10, "2 heaps should give 10 scrap in 10 s, got %d" % (res.scrap - scrap_before))
	_expect(res.crystals == crystals_before + 1, "1 harvester should form 1 crystal in 10 s")
	region.set_platform_owner("Foundry", "")
	scrap_before = res.scrap
	economy.step(10.0)
	_expect(res.scrap == scrap_before, "unowned scrap heaps give nothing")


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
	_expect(hqs.size() == 2, "expected 2 headquarters, got %d" % hqs.size())

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
	_expect(res.scrap == scrap_before + 15, "a walker kill should pay 15 scrap, got %d" % (res.scrap - scrap_before))
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
	var wall := [hub + Vector2i(1, -3), hub + Vector2i(2, -3), hub + Vector2i(3, -3)]
	for hex in wall:
		_expect(build.try_place("rivet_turret", hex) == "", "place wall turret at %s" % [hex])
	var from := region.get_platform_position("Midway")
	var to := raids._target_point()
	_expect(region.find_route(from, to).is_empty(), "the wall should block a normal route to the Hub")
	var smash := raids._route(from, to)
	_expect(not smash.is_empty(), "raiders should still find a route through the wall")
	for hex in wall:
		_expect(not region.is_hex_walkable(hex), "wall tile %s should stay blocked" % [hex])
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
	waves.start_wave()
	_expect(waves.remaining() == 4, "starting early sends wave 2 now")
	for e in get_root().get_tree().get_nodes_in_group(Unit.ENEMY_GROUP):
		e.take_damage(10000.0)
	await process_frame

	# Victory when Ironbell HQ falls.
	var won := [false]
	waves.game_over.connect(func(w): won[0] = w)
	for hq in hqs:
		if hq.faction == "rival":
			hq.take_damage(100000.0)
	_expect(waves.phase == WaveManager.OVER and won[0], "destroying Ironbell HQ should win")
