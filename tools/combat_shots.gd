## Full-screen shots of fights as the player sees them (3D view plus every
## HUD panel), for checking that combat reads well: shells in flight,
## impacts, shields, staggers, falling units. Waves are paused and a fight
## is staged on the Hub. Needs a display:
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-method gl_compatibility \
##     --script res://tools/combat_shots.gd -- out_dir [1920x1080,1280x720] [ground,air,towers,lineup]
## Saves <size>-<scene>-1.png (fight just joined) and -2.png (a moment later).
extends SceneTree

var main: Node


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "user://combat_shots"
	var sizes: PackedStringArray = (args[1] if args.size() > 1 else "1920x1080,1280x720").split(",")
	var scenes: PackedStringArray = (args[2] if args.size() > 2 else "ground").split(",")
	DirAccess.make_dir_recursive_absolute(out_dir)
	for s in sizes:
		var wh := s.split("x")
		for scene in scenes:
			await _shoot(out_dir, s, Vector2i(int(wh[0]), int(wh[1])), scene)
	quit()


func _shoot(out_dir: String, tag: String, size: Vector2i, scene: String) -> void:
	DisplayServer.window_set_size(size)
	root.size = size
	SkyRegion.seed_override = 3
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _settle(20)
	main.waves.time_left = 600.0
	main.waves.set_process(false)
	main.waves.wave = 5
	main.bridges.span_seconds = 1e9
	var region: SkyRegion = main.region
	var cam: RtsCamera = main.get_node("RtsCamera")
	var hub := region.get_platform_position("Hub")
	var units_root: Node3D = main.get_node("Units")
	for u in get_nodes_in_group(Unit.GROUP):
		if not u.is_hero:
			u.queue_free()
	await _settle(2)
	var focus := hub
	if scene == "ground":
		# Your line in front of the HQ, a rival column coming at it from the east.
		var line := [["shieldbearer", Vector3(3.0, 0, -1.2)], ["shieldbearer", Vector3(3.0, 0, 1.2)],
			["rifleman", Vector3(1.0, 0, -2.0)], ["rifleman", Vector3(1.0, 0, 0.0)], ["rifleman", Vector3(1.0, 0, 2.0)],
			["lancer", Vector3(0.0, 0, 3.4)], ["riveteer", Vector3(2.0, 0, -4.0)], ["engineer", Vector3(-0.5, 0, -1.0)]]
		for spec in line:
			var u := UnitCatalog.make(spec[0], "player")
			u.position = region.snap_to_walkable(hub + spec[1])
			units_root.add_child(u)
			u.face(hub + Vector3(20, 0, 0))
		var foes := ["walker", "walker", "shieldbearer", "walker", "rifleman", "walker", "rifleman", "shieldbearer"]
		for i in foes.size():
			var u := UnitCatalog.make(foes[i], "rival")
			u.position = region.snap_to_walkable(hub + Vector3(13.0 + (i / 3) * 1.6, 0, -1.6 + (i % 3) * 1.6))
			units_root.add_child(u)
			main.waves._toughen(u)
			u.set_route(region.find_route(u.position, region.snap_to_walkable(hub)), true)
		focus = hub + Vector3(5, 0, 0)
	elif scene == "air":
		main.resources.scrap = 5000
		main.resources.crystals = 200
		var c: Vector2i = region.platforms["Hub"].center
		for p in [["flak_battery", Vector2i(-2, 2)], ["skyhook_cannon", Vector2i(2, 1)], ["rivet_turret", Vector2i(1, -2)],
				["dynamo", Vector2i(0, 3)], ["dynamo", Vector2i(-3, 1)]]:
			main.building.try_place(p[0], c + p[1])
		for kind in ["bomber", "gunship", "carrier"]:
			for u in main.fleet.launch(kind, 3 if kind == "bomber" else 1, "Vesper" if kind != "carrier" else "Ironbell"):
				main.waves._toughen(u)
				# Start them close so the fight is on screen.
				var side := Vector3(u.position.x - hub.x, 0, u.position.z - hub.z).normalized()
				u.position = hub + side * 14.0 + Vector3.UP * VesperFleet.ALTITUDE
				# Fresh orders from here (VesperFleet plans the run).
				u.stop()
	elif scene == "towers" or scene == "lineup":
		# Every defense tower on the Hub, powered. "towers" also sends walkers
		# from the east and airships from their lanes; "lineup" is a close,
		# quiet look at the models.
		main.resources.scrap = 5000
		main.resources.crystals = 200
		var c: Vector2i = region.platforms["Hub"].center
		for d in [Vector2i(-3, 1), Vector2i(-2, -1), Vector2i(-1, -2)]:
			main.building.try_place("dynamo", c + d)
		# The towers stand in a row along the Hub's front (camera) edge,
		# left to right in build-menu order; dynamos go at the back.
		var front: Array[Vector2i] = []
		for hex in region.tiles_of_platform("Hub"):
			if region.tiles[hex].type == "deck" and not region.buildings.has(hex) and HexGrid.distance(hex, c) == 2 and region.hex_center(hex).z > hub.z - 0.5:
				front.append(hex)
		front.sort_custom(func(a, b): return region.hex_center(a).z > region.hex_center(b).z)
		front = front.slice(0, 7)
		front.sort_custom(func(a, b): return region.hex_center(a).x < region.hex_center(b).x)
		var towers := ["rivet_turret", "arc_coil", "rally_horn", "flak_battery", "skyhook_cannon"]
		var picks: Array[Vector2i] = []
		for i in towers.size():
			picks.append(front[int(round(i * (front.size() - 1) / 4.0))])
		for i in towers.size():
			var err: String = main.building.try_place(towers[i], picks[i])
			print("place ", towers[i], " at ", picks[i], ": ", err if err != "" else "ok")
		focus = hub + Vector3(0, 0, 2.5)
		if scene == "towers":
			for spec in [["riveteer", Vector3(3.5, 0, -0.5)], ["riveteer", Vector3(3.5, 0, 1.0)], ["rifleman", Vector3(2.5, 0, 2.5)]]:
				var u := UnitCatalog.make(spec[0], "player")
				u.position = region.snap_to_walkable(hub + spec[1])
				units_root.add_child(u)
			# Close enough that every tower is already firing in the shot.
			var foes := ["walker", "rifleman", "walker", "walker", "rifleman", "walker"]
			for i in foes.size():
				var u := UnitCatalog.make(foes[i], "rival")
				u.position = region.snap_to_walkable(hub + Vector3(-3.0 + (i % 3) * 1.4, 0, 5.5 + (i / 3) * 1.4))
				units_root.add_child(u)
				main.waves._toughen(u)
				u.set_route(region.find_route(u.position, region.snap_to_walkable(hub)), true)
			var k := 0
			for kind in ["carrier", "gunship"]:
				for u in main.fleet.launch(kind, 1, "Vesper"):
					main.waves._toughen(u)
					u.position = hub + Vector3(3.5 + k * 2.5, VesperFleet.ALTITUDE, 3.0 - k * 2.0)
					u.stop()
					k += 1
	var zoom := 0.1
	if scene == "lineup":
		zoom = 0.03
		focus = hub + Vector3(0, 0, 3.0)
		main.waves.set_process(false)
	cam.position = Vector3(focus.x, cam.position.y, focus.z + 6)
	cam.zoom = zoom
	cam._target_zoom = zoom
	cam._apply_zoom()
	await _settle(100 if scene == "ground" else (30 if scene == "towers" else 60))
	await _save("%s/%s-%s-1.png" % [out_dir, tag, scene])
	await _settle(40 if scene != "towers" else 12)
	await _save("%s/%s-%s-2.png" % [out_dir, tag, scene])
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
