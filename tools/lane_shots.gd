## Full-screen shots of the rivals' wind lanes as the player sees them (3D
## view plus every HUD panel): the opening view, a wave of airships
## weaving down their lanes, and the same after the wind turns.
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-method gl_compatibility \
##     --script res://tools/lane_shots.gd -- out_dir [1920x1080,1280x720]
## Saves <size>-1-start.png, -2-wave.png, -3-wind-turned.png.
extends SceneTree


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "user://lane_shots"
	var sizes: PackedStringArray = (args[1] if args.size() > 1 else "1920x1080,1280x720").split(",")
	DirAccess.make_dir_recursive_absolute(out_dir)
	for s in sizes:
		var wh := s.split("x")
		await _shoot(out_dir, s, Vector2i(int(wh[0]), int(wh[1])))
	quit()


func _shoot(out_dir: String, tag: String, size: Vector2i) -> void:
	DisplayServer.window_set_size(size)
	root.size = size
	SkyRegion.seed_override = 3
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _settle(30)
	await _save("%s/%s-1-start.png" % [out_dir, tag])

	# Zoomed out over the whole map with the fog lifted, wave 3 in the air.
	var region: SkyRegion = main.region
	var cam: RtsCamera = main.get_node("RtsCamera")
	main.fog.set_enabled(false)
	main.waves.set_process(false)
	main.waves.wave = 3
	# Keep the Hub standing so the shots show the airships, not a game over.
	for hq in get_nodes_in_group(Headquarters.GROUP):
		if hq.faction == "player":
			hq.max_hp = 1e6
			hq.hp = 1e6
	var hub := region.get_platform_position("Hub")
	cam.position = Vector3(hub.x, cam.position.y, hub.z - 12)
	cam.zoom = 0.75
	cam._target_zoom = 0.75
	cam._apply_zoom()
	for kind in [["bomber", "Vesper", 4], ["carrier", "Ironbell", 3]]:
		main.fleet.launch(kind[0], kind[2], kind[1])
	await _settle(200)
	await _settle(2)
	await _save("%s/%s-2-wave.png" % [out_dir, tag])

	for u in get_nodes_in_group(Unit.ENEMY_GROUP):
		if u.flying:
			u.queue_free()
	main.wind.shift(4)
	await _settle(5)
	for kind in [["bomber", "Vesper", 4], ["carrier", "Ironbell", 3]]:
		main.fleet.launch(kind[0], kind[2], kind[1])
	await _settle(200)
	await _settle(2)
	await _save("%s/%s-3-wind-turned.png" % [out_dir, tag])

	root.remove_child(main)
	main.free()
	await _settle(2)


func _settle(frames: int) -> void:
	for i in frames:
		await process_frame


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("saved ", path)
