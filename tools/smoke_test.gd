## Headless smoke test: loads the main scene, checks the input map and the
## camera's zoom behaviour, then exits non-zero on any failure.
## Run: godot --headless --path . --script res://tools/smoke_test.gd
extends SceneTree

const Bindings = preload("res://tools/input_bindings.gd")

var _failures := 0


func _initialize() -> void:
	_check_input_map()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	_check_scene(main)
	_check_camera(main.get_node("RtsCamera"))
	_check_routing(main.get_node("Region"))
	await _check_selection_and_orders(main)
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
	var region: Node = main.get_node("Region")
	for name in ["Hub", "NeutralA", "NeutralB", "NeutralC", "NeutralD", "RivalHQ", "StormCloud"]:
		_expect(region.has_node(name), "region is missing %s" % name)
	_expect(region.get_children().filter(func(n): return n.name.begins_with("Walkway_")).size() == 5,
		"expected 5 walkways")


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


func _check_routing(region: Node) -> void:
	_expect(region.platform_path("Hub", "RivalHQ") == PackedStringArray(["Hub", "NeutralB", "NeutralD", "RivalHQ"]),
		"Hub to RivalHQ should go via NeutralB and NeutralD, got %s" % [region.platform_path("Hub", "RivalHQ")])
	var hub: Vector3 = region.get_platform_position("Hub")
	var d: Vector3 = region.get_platform_position("NeutralD")
	var route: PackedVector3Array = region.find_route(hub, d)
	_expect(route.size() == 5, "Hub to NeutralD should be 2 walkways (4 rim points) + goal, got %d points" % route.size())
	_expect(route.size() > 0 and route[route.size() - 1].is_equal_approx(d), "route should end at the target")
	_expect(region.find_route(hub, Vector3(500, 0, 500)).is_empty(), "a point in open sky should be unreachable")
	_expect(region.find_route(hub, hub + Vector3(2, 0, 0)).size() == 1, "same-platform move should be direct")
	var clamped: Vector3 = region.clamp_to_platform("Hub", hub + Vector3(50, 0, 0))
	_expect(region.platform_at(clamped) == "Hub", "clamped point should stay on the Hub")


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
	var region: Node = main.get_node("Region")
	var target: Vector3 = region.get_platform_position("NeutralD")
	_expect(sel.order_move(target), "ordering a move to NeutralD should succeed")
	_expect(not sel.order_move(Vector3(500, 0, 500)), "ordering a move into open sky should fail")
	for i in 600:
		for u in units:
			u._process(0.05)
	for u in units:
		_expect(not u.is_moving(), "%s should have arrived" % u.name)
		_expect(region.platform_at(u.position) == "NeutralD", "%s should be on NeutralD, is at %s" % [u.name, u.position])
	_expect(hero.position.distance_to(target) < 0.01, "hero should take the centre spot")
	await process_frame
