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
