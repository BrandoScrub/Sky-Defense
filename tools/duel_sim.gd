## Balance probe for single fights: a rival force attacks your Hub, defended by
## the units and towers you list. Waves and bridges are paused, so only this
## fight happens. Not part of the game or CI.
##
##   godot --headless --fixed-fps 60 --path . --script res://tools/duel_sim.gd -- \
##     atk=walker:4,shieldbearer:1 def=riveteer:4 towers=rivet_turret:3 wave=5 air=bomber:2
##
## atk: rival ground units, spawned beside the Hub, marching on its HQ.
## air: rival airships (VesperFleet kinds), launched along their usual lanes.
## def: your units, standing at the HQ. towers: your buildings on the Hub.
## wave: rival units get that wave's extra health.
## Prints one "DUEL" line: who's left, HQ damage, scrap spent and earned.
extends SceneTree


func _parse(spec: String) -> Array:
	var out := []
	for part in spec.split(",", false):
		var bits := part.split(":")
		out.append([bits[0], int(bits[1]) if bits.size() > 1 else 1])
	return out


func _initialize() -> void:
	var args := {"atk": "", "def": "", "towers": "", "wave": "1", "air": "", "seconds": "120", "seed": "3"}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	SkyRegion.seed_override = int(args.seed)
	SkyRegion.rivals_override = RivalCatalog.layout_rivals(2)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var region: SkyRegion = main.region
	var res: PlayerResources = main.resources
	main.waves.time_left = 1e9
	main.waves.wave = int(args.wave)
	main.bridges.span_seconds = 1e9
	for u in get_nodes_in_group(Unit.GROUP):
		u.queue_free()
	await process_frame
	res.scrap = 100000
	var spent := 0
	var units_root: Node3D = main.get_node("Units")
	var hub_pos := region.get_platform_position("Hub")
	var hub_hq = main.combat.headquarters_on("Hub")
	# Towers on the Hub's free deck tiles, closest to the HQ first.
	var hexes := region.tiles_of_platform("Hub")
	hexes.sort_custom(func(a, b): return region.hex_center(a).distance_to(hub_pos) < region.hex_center(b).distance_to(hub_pos))
	for pair in _parse(args.towers):
		for i in pair[1]:
			for hex in hexes:
				if region.buildings.has(hex) or region.tiles[hex].type != "deck":
					continue
				if main.building.try_place(pair[0], hex) == "":
					spent += BuildingCatalog.get_data(pair[0]).cost
					break
	# Enough power for whatever was built.
	while region.power_supply() < region.power_demand():
		var placed := false
		for hex in hexes:
			if not region.buildings.has(hex) and region.tiles[hex].type in ["deck", "generator_socket"]:
				if main.building.try_place("dynamo", hex) == "":
					placed = true
					break
		if not placed:
			break
	main.loads.set_process(false)
	var i := 0
	for pair in _parse(args.def):
		for k in pair[1]:
			var u := UnitCatalog.make(pair[0], "player")
			u.position = region.snap_to_walkable(hub_pos + Vector3(-2.0 + (i % 4) * 1.2, 0, 1.5 + (i / 4) * 1.2))
			units_root.add_child(u)
			spent += int(UnitCatalog.get_data(pair[0]).cost)
			i += 1
	# Attackers start on the nearest platform with a walk route to the Hub.
	var start := Vector3.ZERO
	var best := INF
	for p in region.platforms:
		if p == "Hub":
			continue
		var spot := region.snap_to_walkable(region.get_platform_position(p))
		var d := spot.distance_to(hub_pos)
		if d < best and not region.find_route(spot, region.snap_to_walkable(hub_pos)).is_empty():
			best = d
			start = spot
	if best == INF:
		# No walkway yet: drop them on the Hub's rim instead.
		start = region.snap_to_walkable(hub_pos + Vector3(9, 0, 0))
	var attackers := []
	i = 0
	for pair in _parse(args.atk):
		for k in pair[1]:
			var u := UnitCatalog.make(pair[0], "rival")
			u.position = region.snap_to_walkable(start + Vector3((i % 3) * 1.0 - 1.0, 0, (i / 3) * 1.0))
			units_root.add_child(u)
			main.waves._toughen(u)
			attackers.append(u)
			i += 1
	for pair in _parse(args.air):
		for u in main.fleet.launch(pair[0], pair[1], "Vesper" if pair[0] != "carrier" else "Ironbell"):
			main.waves._toughen(u)
			attackers.append(u)
	var scrap_before := res.scrap
	var t := 0.0
	var hq_target := region.snap_to_walkable(hub_pos)
	while t < float(args.seconds):
		await process_frame
		t += 1.0 / 60.0
		if int(t * 60) % 60 == 0:
			for u in attackers:
				if is_instance_valid(u) and u.is_alive() and not u.flying and not u.is_moving():
					var r := region.find_route(u.position, hq_target)
					if not r.is_empty():
						u.set_route(r, true)
		var left := 0
		for u in attackers:
			if is_instance_valid(u) and u.is_alive():
				left += 1
		if left == 0 or hub_hq == null or not hub_hq.is_alive():
			break
	var alive_atk := {}
	for u in attackers:
		if is_instance_valid(u) and u.is_alive():
			alive_atk[u.unit_type] = alive_atk.get(u.unit_type, 0) + 1
	var alive_def := {}
	for u in get_nodes_in_group(Unit.GROUP):
		alive_def[u.unit_type] = alive_def.get(u.unit_type, 0) + 1
	var towers_left := 0
	for b in region.buildings_on("Hub"):
		if b.type_id != "dynamo":
			towers_left += 1
	print("DUEL atk=%s air=%s def=%s towers=%s wave=%s | t=%.0f hq_lost=%.0f | attackers left %s | defenders left %s | towers left %d | spent %d earned %d" % [
		args.atk, args.air, args.def, args.towers, args.wave, t,
		1500.0 - (hub_hq.hp if hub_hq and hub_hq.is_alive() else 0.0), alive_atk, alive_def, towers_left, spent, res.scrap - scrap_before])
	quit()
