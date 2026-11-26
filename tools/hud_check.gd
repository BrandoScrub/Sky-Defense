## Renders the game the way a player sees it (whole screen: 3D view plus every
## HUD panel) at common window sizes, and saves one PNG per moment.
## Run after any HUD change and look at every shot. Needs a display:
##   xvfb-run -s "-screen 0 1920x1080x24" godot --path . --rendering-method gl_compatibility \
##     --script res://tools/hud_check.gd -- out_dir [1920x1080,1280x720]
## Shots per size: start (first frame a player sees), build (Defense tab, a
## turret ghost), info (an info card open), wave (wave running, card open).
extends SceneTree


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "user://hud_check"
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
	await _save("%s/%s-start.png" % [out_dir, tag])

	main.build_menu.show_tab("Defense")
	main.building.start_placing("rivet_turret")
	await _settle(10)
	await _save("%s/%s-build.png" % [out_dir, tag])
	main.building.cancel_placing()

	main.info_panel.show_thing(main.selection.all_units()[0])
	await _settle(10)
	await _save("%s/%s-info.png" % [out_dir, tag])

	main.waves.start_wave()
	await _settle(240)
	await _save("%s/%s-wave.png" % [out_dir, tag])

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
