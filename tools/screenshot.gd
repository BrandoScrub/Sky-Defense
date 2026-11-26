## Renders the main scene from a few camera positions and saves PNGs.
## Needs a display (use xvfb-run on a server):
##   godot --path . --rendering-method gl_compatibility --script res://tools/screenshot.gd -- out_dir
extends SceneTree


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "user://screenshots"
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1600, 900)

	SkyRegion.seed_override = 3
	# These shots show every system, so lay every planned walkway up front.
	SkyRegion.prebuilt_walkways = true
	SkyRegion.instant_walkways = true
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
	_save(out_dir + "/fog-of-war.png")
	main.set_tips_open(false)
	cam.position = region.get_platform_position("Hub") + Vector3(8, 0, 2)
	cam.zoom = 0.7
	cam._target_zoom = 0.7
	cam._apply_zoom()
	await _settle()
	_save(out_dir + "/fog-around-hub.png")
	cam.position = Vector3(mid.x, 0, mid.y + 8)
	cam.zoom = 1.0
	cam._target_zoom = 1.0
	cam._apply_zoom()
	# The rest of the shots show the whole map.
	main.fog.reveal_all()
	await _settle()
	_save(out_dir + "/overview.png")

	# Close view of the Hub with the squad.
	cam.position = region.get_platform_position("Hub")
	cam.zoom = 0.25
	cam._target_zoom = 0.25
	cam._apply_zoom()
	main.selection.select_units(main.selection.all_units())
	# A few sample buildings so the shot shows build mode's results.
	var hub: Vector2i = region.platforms["Hub"].center
	main.resources.add_scrap(300)
	main.building.try_place("dynamo", hub + Vector2i(2, -1))
	main.building.try_place("rivet_turret", hub + Vector2i(2, 0), 1)
	main.building.try_place("flak_battery", hub + Vector2i(-2, 0))
	main.building.try_place("arc_coil", hub + Vector2i(1, -2))
	for hex in region.tiles_of_platform("Hub"):
		if region.get_tile(hex).type == "harvester_anchor":
			main.building.try_place("harvester", hex)
	main.building.start_placing("rivet_turret")
	await _settle()
	_save(out_dir + "/hub.png")
	main.building.cancel_placing()

	# Sky network: a claimed Foundry, a new walkway, and a raid on Midway.
	region.set_platform_owner("Foundry", "player")
	var foundry: Dictionary = region.platforms["Foundry"]
	var crystal: Dictionary = region.platforms["Crystal Spire"]
	main.walkways.try_build(region.rim_toward(foundry, crystal.center, true), region.rim_toward(crystal, foundry.center, true))
	main.capture.set_process(false)
	main.raids.set_process(false)
	var party: Array[Unit] = main.raids.send_party(3)
	for i in 400:
		main.raids._process(0.05)
		for u in party:
			u._process(0.05)
		main.capture.step(0.05)
		if main.capture.claims.get("Midway", {}).get("progress", 0.0) > 0.6:
			break
	cam.position = (region.get_platform_position("Hub") + region.get_platform_position("Midway")) / 2.0 + Vector3(-8, 0, 4)
	cam.zoom = 0.6
	cam._target_zoom = 0.6
	cam._apply_zoom()
	await _settle()
	_save(out_dir + "/network.png")

	# Weight and power: an overloaded Generator Rig and a browned-out grid.
	region.set_platform_owner("Generator Rig", "player")
	var rig: Vector2i = region.platforms["Generator Rig"].center
	main.resources.add_scrap(400)
	main.building.try_place("arc_coil", rig)
	main.building.try_place("flak_battery", rig + Vector2i(1, 0))
	main.building.try_place("arc_coil", rig + Vector2i(-1, 0))
	main.building.try_place("arc_coil", rig + Vector2i(0, -1))
	main.building.try_place("arc_coil", rig + Vector2i(1, -1))
	main.building.try_place("arc_coil", region.platforms["Hub"].center + Vector2i(-1, -1))
	var units: Array[Unit] = main.selection.all_units()
	for i in units.size():
		units[i].position = region.hex_center(rig + [Vector2i(-1, 1), Vector2i(0, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 1)][i]) + Vector3(i * 0.4 - 0.8, 0, 0)
	main.loads.step(0.5)
	main.economy.step(0.1)
	main._refresh_resources()
	cam.position = region.get_platform_position("Generator Rig") + Vector3(-4, 0, -2)
	cam.zoom = 0.2
	cam._target_zoom = 0.2
	cam._apply_zoom()
	await _settle()
	_save(out_dir + "/systems.png")

	# Combat: a wave of Ironbell walkers hits the Hub's turret line.
	var hubc: Vector2i = region.platforms["Hub"].center
	main.resources.add_scrap(300)
	for hex in [hubc + Vector2i(1, -3), hubc + Vector2i(3, -3)]:
		main.building.try_place("rivet_turret", hex)
	for i in units.size():
		units[i].position = region.hex_center(hubc + Vector2i(i - 2, -1))
		units[i].stop()
	main.waves.start_wave()
	# Skip the long walk: drop the walkers just past the Midway walkway.
	var k := 0
	for e in main.get_tree().get_nodes_in_group(Unit.ENEMY_GROUP):
		e.position = region.hex_center(hubc + Vector2i(2, -5)) + Vector3((k % 3) * 1.2 - 1.2, 0, -(k / 3) * 1.2)
		k += 1
	for i in 8:
		main.raids._process(0.05)
		for u in get_root_units(main):
			u._process(0.05)
		main.combat.step(0.05)
	cam.position = region.get_platform_position("Hub") + Vector3(2, 0, -6)
	cam.zoom = 0.12
	cam._target_zoom = 0.12
	cam._apply_zoom()
	await _settle()
	for i in 4:
		main.combat.step(0.1)
		await process_frame
	_save(out_dir + "/combat.png")

	# Ferry and storms: the Commander rides to the Crystal Spire while the
	# North Storm feeds your grid.
	main.storms.set_process(false)
	main.ferry.set_process(false)
	for e in main.get_tree().get_nodes_in_group(Unit.ENEMY_GROUP):
		e.free()
	var anchor_hex := Vector2i.ZERO
	for hex in region.tiles_of_platform("Hub"):
		if region.get_tile(hex).type == "harvester_anchor":
			anchor_hex = hex
	if not region.buildings.has(anchor_hex):
		main.resources.add_scrap(100)
		main.building.try_place("harvester", anchor_hex)
	region.set_platform_owner("Midway", "rival")
	while main.storms.rival_build() != "":
		pass
	main.storms.refresh()
	var hero: Unit = main.selection.find_hero()
	main.selection.select_units([hero])
	var f: Dictionary = main.ferry.ferries[0]
	# (The network shot built a walkway to the Spire, so board directly.)
	hero.position = main.ferry.dock_point(f, 0)
	main.ferry.send(hero, region.get_platform_position("Crystal Spire") + Vector3(1, 0, 0))
	for i in 2000:
		hero._process(0.05)
		main.ferry.step(0.05)
		if hero.riding and f.flying and f.timer < main.ferry.trip_seconds * 0.45:
			break
	cam.position = (region.get_platform_position("Hub") + region.get_platform_position("Crystal Spire")) / 2.0 + Vector3(0, 0, -2)
	cam.zoom = 0.45
	cam._target_zoom = 0.45
	cam._apply_zoom()
	await _settle()
	_save(out_dir + "/ferry-and-storms.png")

	# Vesper Aeronautics: a bomber flight comes in over the Generator Rig.
	main.fleet.set_process(false)
	main.waves.set_process(false)
	main.resources.add_scrap(200)
	var rig_c: Vector2i = region.platforms["Generator Rig"].center
	main.building.try_place("flak_battery", hubc + Vector2i(3, 0))
	main.building.try_place("flak_battery", hubc + Vector2i(2, 1))
	var flight: Array[Unit] = []
	main.fleet._next_lane = 1
	flight.append_array(main.fleet.send_flight(3))
	for i in 400:
		for u in flight:
			if is_instance_valid(u):
				u._process(0.05)
		main.fleet.step()
		main.combat.step(0.05)
		var near := false
		for u in flight:
			if is_instance_valid(u) and Vector2(u.position.x, u.position.z).distance_to(Vector2(region.hex_center(rig_c).x, region.hex_center(rig_c).z)) < 9.0:
				near = true
		if near:
			break
	cam.position = region.hex_center(rig_c) + Vector3(0, 0, -4)
	cam.zoom = 0.2
	cam._target_zoom = 0.2
	cam._apply_zoom()
	await _settle()
	for i in 4:
		main.combat.step(0.1)
		await process_frame
	_save(out_dir + "/vesper-bombers.png")
	quit(0)


func get_root_units(main: Node) -> Array:
	var out := []
	for group in [Unit.GROUP, Unit.ENEMY_GROUP]:
		out.append_array(main.get_tree().get_nodes_in_group(group))
	return out


func _settle() -> void:
	for i in 10:
		await process_frame


func _save(path: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("Saved ", path)
