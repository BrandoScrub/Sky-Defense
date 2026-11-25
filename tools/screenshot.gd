## Renders the main scene from a few camera positions and saves PNGs.
## Needs a display (use xvfb-run on a server):
##   godot --path . --rendering-method gl_compatibility --script res://tools/screenshot.gd -- out_dir
extends SceneTree


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "user://screenshots"
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1600, 900)

	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var cam: RtsCamera = main.get_node("RtsCamera")
	var region: SkyRegion = main.get_node("Region")

	# Wide view of the whole region.
	var bounds := region.get_bounds()
	var mid := bounds.get_center()
	cam.position = Vector3(mid.x, 0, mid.y + 8)
	cam.distance_max = 130.0
	cam.zoom = 1.0
	cam._target_zoom = 1.0
	cam._apply_zoom()
	await _settle()
	_save(out_dir + "/overview.png")

	# Close view of the Hub with the squad.
	cam.position = region.get_platform_position("Hub")
	cam.zoom = 0.25
	cam._target_zoom = 0.25
	cam._apply_zoom()
	main.selection.select_units(main.selection.all_units())
	await _settle()
	_save(out_dir + "/hub.png")
	quit(0)


func _settle() -> void:
	for i in 10:
		await process_frame


func _save(path: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("Saved ", path)
