## Renders a wide view of the generated map for each seed given, to compare
## layouts. Needs a display (use xvfb-run on a server):
##   godot --path . --rendering-method gl_compatibility --script res://tools/map_preview.gd -- out_dir 3 11 42
## Add "r4" (or r3) before the seeds to lay out 4 (or 3) rivals with placeholder
## names for the factions that aren't in the game yet.
extends SceneTree


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "user://maps"
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1600, 900)
	var seeds: Array = Array(args.slice(1)) if args.size() > 1 else ["3"]
	var tag := ""
	if not seeds.is_empty() and str(seeds[0]).begins_with("r"):
		var count := int(str(seeds.pop_front()).substr(1))
		tag = "-%drivals" % count
		var extra := [
			{"corp": "Weather", "hq": "Storm Faction HQ", "first": "Squall Reach"},
			{"corp": "Aurum", "hq": "Defense Faction HQ", "first": "Gilt Reach"},
		]
		SkyRegion.rivals_override = LevelLayout.DEFAULT_RIVALS + extra.slice(0, count - 2)
	for s in seeds:
		SkyRegion.seed_override = int(s)
		var main: Node = load("res://scenes/main.tscn").instantiate()
		root.add_child(main)
		await process_frame
		for child in main.get_children():
			if child is CanvasLayer:
				child.visible = false
		var region: SkyRegion = main.get_node("Region")
		main.fog.reveal_all()
		var cam: RtsCamera = main.get_node("RtsCamera")
		var bounds := region.get_bounds()
		cam.bounds = bounds.grow(200.0)
		cam.position = Vector3(bounds.get_center().x, 0, bounds.get_center().y + bounds.size.y * 0.12)
		cam.distance_max = maxf(bounds.size.x, bounds.size.y) * 1.05
		cam.zoom = 1.0
		cam._target_zoom = 1.0
		cam._apply_zoom()
		for i in 10:
			await process_frame
		var path := "%s/map-seed-%s%s.png" % [out_dir, s, tag]
		root.get_texture().get_image().save_png(path)
		var counts := {}
		for corp in region.layout.paths:
			counts[corp] = region.layout.paths[corp].size() - 2
		print("Saved ", path, "  directions ", region.layout.directions, "  platforms between ", counts)
		main.queue_free()
		await process_frame
	quit(0)
