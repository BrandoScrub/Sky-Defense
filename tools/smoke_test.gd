## Headless smoke test: loads the main scene, checks the input map and the
## camera's zoom behaviour, then exits non-zero on any failure.
## Run: godot --headless --path . --script res://tools/smoke_test.gd
extends SceneTree

const Bindings = preload("res://tools/input_bindings.gd")

var _failures := 0


func _initialize() -> void:
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
