## Balance probe: plays the real map with a scripted player and logs each wave.
## Not part of the game or CI; run it by hand when tuning numbers.
##
##   godot --headless --fixed-fps 60 --path . --script res://tools/balance_sim.gd -- strategy=expand seed=3 rivals=2
##
## Strategies:
##   idle   - does nothing (how long the Hub lasts on its own)
##   turtle - only builds towers on the Hub
##   expand - claims islands one walkway at a time, keeps a mixed army and a
##            few towers, then attacks the nearest rival HQ once it is strong
##   rush   - spends almost everything on troops and attacks early
## One summary line starting with "RESULT" ends every run.
extends SceneTree

var strategy := "expand"
var max_seconds := 2400.0
var main: Node
var region: SkyRegion
var res: PlayerResources
## Where the attack force is heading, or "".
var assault := ""
var stats := {"walkways": 0, "units": 0, "towers": 0, "flak": 0, "kills_scrap": 0, "spent": 0}
var hq_down := []
## trace=1 prints what is attacking every 10 seconds of a wave.
var trace := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("strategy="): strategy = a.split("=")[1]
		if a.begins_with("seed="): SkyRegion.seed_override = int(a.split("=")[1])
		if a.begins_with("rivals="): SkyRegion.rivals_override = RivalCatalog.layout_rivals(int(a.split("=")[1]))
		if a.begins_with("minutes="): max_seconds = float(a.split("=")[1]) * 60.0
		if a == "trace=1": trace = true
		if a.begins_with("difficulty="): Difficulty.level = a.split("=")[1]
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	region = main.region
	res = main.resources
	main.combat.headquarters_destroyed.connect(func(f, p): if f == "rival": hq_down.append(p))
	var t := 0.0
	var last_wave := 0
	var think := 0.0
	var peak_army := 0
	while t < max_seconds:
		await process_frame
		t += 1.0 / 60.0
		think -= 1.0 / 60.0
		if main.waves.phase == WaveManager.OVER:
			break
		if think <= 0.0:
			think = 2.0
			_play()
			peak_army = maxi(peak_army, get_nodes_in_group(Unit.GROUP).size())
		if trace and main.waves.phase == WaveManager.WAVE and int(t * 60) % 600 == 0:
			_trace(t)
		if main.waves.wave != last_wave and main.waves.phase == WaveManager.BUILD:
			last_wave = main.waves.wave
			var hq = main.combat.headquarters_on("Hub")
			print("t=%4.0f wave %2d | scrap %4d cr %3d | hub %s | power %d/%d | islands %d | army %d | ironbell %s | rival HQs down %d" % [
				t, last_wave, res.scrap, res.crystals, ("%.0f" % hq.hp) if hq else "dead",
				region.power_supply(), region.power_demand(), main.economy.islands_held(),
				get_nodes_in_group(Unit.GROUP).size(),
				("%d/%d" % [main.bridges.spans_built("Ironbell"), main.bridges.crews["Ironbell"].path.size() - 1]) if main.bridges.crews.has("Ironbell") else "-",
				hq_down.size()])
	var hub_hq = main.combat.headquarters_on("Hub")
	print("RESULT difficulty=%s strategy=%s won=%s wave=%d t=%.0f hub=%s rival_hqs_down=%d islands=%d peak_army=%d %s" % [
		Difficulty.level, strategy, main.waves.won, main.waves.wave, t, ("%.0f" % hub_hq.hp) if hub_hq else "dead",
		hq_down.size(), main.economy.islands_held(), peak_army, stats])
	quit()


func _play() -> void:
	match strategy:
		"turtle": _towers_on("Hub", 99)
		"expand": _expand(14, 7)
		"rush": _expand(16, 4)


## A balanced player. Attacks once `army_goal` units are out and the wave is
## at least `attack_wave`.
func _expand(army_goal: int, attack_wave: int) -> void:
	var wave: int = main.waves.wave
	var army := get_nodes_in_group(Unit.GROUP)
	var rush := strategy == "rush"
	# 1. Power and a couple of towers first, so the Hub isn't bare.
	if not rush or wave >= 3:
		_towers_on("Hub", 2 + wave / 2 + res.scrap / 120)
	# 2. Flak once airships are coming.
	if wave >= 3:
		_flak_on("Hub", 1 + (wave - 3) / 3)
	# 3. Expand one island at a time (before troops: islands pay every wave).
	if not rush or wave >= 4:
		_build_walkway(20 if army.size() >= 6 else 0)
	# 4. Grow the army.
	var mix := ["riveteer", "shieldbearer", "rifleman", "riveteer", "lancer", "rifleman", "medic", "shieldbearer"]
	var keep := 40
	if rush:
		keep = 20
	while army.size() + main.recruiter.queued < army_goal and res.scrap >= keep + 45:
		var kind: String = mix[(stats.units) % mix.size()]
		if main.recruiter.queue_one(kind) != "":
			break
		stats.units += 1
	# 5. Orders.
	_order_units(army, army_goal, attack_wave)


func _towers_on(platform_name: String, goal: int) -> void:
	var have := 0
	for b in region.buildings_on(platform_name):
		if BuildingCatalog.role_of(b.type_id) == "ground":
			have += 1
	for hex in _tiles_near_hq(platform_name):
		if have >= goal or res.scrap < 40:
			return
		if region.buildings.has(hex) or region.tiles[hex].type != "deck":
			continue
		if region.platform_load(platform_name) + 4 > region.platform_capacity(platform_name):
			return
		var type := "rivet_turret"
		if region.power_supply() < region.power_demand() + 4:
			type = "dynamo"
		elif have % 4 == 3:
			type = "arc_coil"
		if main.building.try_place(type, hex) == "":
			stats.spent += BuildingCatalog.get_data(type).cost
			if type != "dynamo":
				have += 1
				stats.towers += 1


func _flak_on(platform_name: String, goal: int) -> void:
	var have := 0
	for b in region.buildings_on(platform_name):
		if BuildingCatalog.role_of(b.type_id) == "flak":
			have += 1
	for hex in _tiles_near_hq(platform_name):
		if have >= goal or res.scrap < 60:
			return
		if region.buildings.has(hex) or region.tiles[hex].type != "deck":
			continue
		if region.platform_load(platform_name) + 3 > region.platform_capacity(platform_name):
			return
		var type := "flak_battery"
		if region.power_supply() < region.power_demand() + 3:
			type = "dynamo"
		if main.building.try_place(type, hex) == "":
			stats.spent += BuildingCatalog.get_data(type).cost
			if type != "dynamo":
				have += 1
				stats.flak += 1


## Lays one walkway from a platform you hold to the closest unlinked
## neighbour on the planned map, if there's scrap to spare beyond `reserve`.
func _build_walkway(reserve: int) -> void:
	if not region.pending_hexes.is_empty():
		return
	var best := []
	var best_score := INF
	for w in region.layout.walkways:
		for k in 2:
			var a: String = w[k]
			var b: String = w[1 - k]
			if region.platform_owner(a) != "player" or region.platforms_linked(a, b):
				continue
			var kind: String = region.platforms[b].kind
			# Only bridge to a rival HQ when ready to attack it.
			if kind == "rival" and get_nodes_in_group(Unit.GROUP).size() < 10:
				continue
			var plan := region.plan_walkway(region.rim_toward(region.platforms[a], region.platforms[b].center), region.rim_toward(region.platforms[b], region.platforms[a].center))
			if plan.problem != "":
				continue
			var score: float = plan.cost + region.get_platform_position(b).distance_to(region.get_platform_position("Hub"))
			# Scrap heaps and generator sockets are worth going out of the way for.
			for hex in region.tiles_of_platform(b):
				if region.tiles[hex].type in ["scrap_heap", "generator_socket"]:
					score -= 40.0
			if score < best_score:
				best_score = score
				best = [a, b, plan]
	if best.is_empty() or res.scrap < best[2].cost + reserve:
		return
	var a: Dictionary = region.platforms[best[0]]
	var b: Dictionary = region.platforms[best[1]]
	if main.walkways.try_build(region.rim_toward(a, b.center), region.rim_toward(b, a.center)) == "":
		stats.walkways += 1
		stats.spent += best[2].cost


func _order_units(army: Array, army_goal: int, attack_wave: int) -> void:
	var idle := []
	for u in army:
		if u.is_alive() and not u.is_moving() and not u.riding and u != main.get("hero"):
			idle.append(u)
	# One unit claims each linked platform nobody holds (or a rival took),
	# then walks home; the rest wait on the Hub.
	var hub := region.snap_to_walkable(region.get_platform_position("Hub"))
	for p in region.platforms:
		if idle.size() < 3:
			break
		if region.platforms[p].kind in ["hub", "rival"] or region.platform_owner(p) == "player":
			continue
		if region.units_on_platform(p, Unit.GROUP).size() > 0 or region.units_on_platform(p, Unit.ENEMY_GROUP).size() > 0:
			continue
		var spot := region.snap_to_walkable(region.get_platform_position(p))
		if region.find_route(hub, spot).is_empty():
			continue
		var u: Unit = idle.pop_back()
		var r := region.find_route(u.position, spot)
		if trace:
			print("   claim %s with %s route=%d" % [p, u.display_name, r.size()])
		if not r.is_empty():
			u.set_route(r, true)
	for u in idle:
		var here := region.platform_at(u.position)
		if here != "Hub" and here != assault and region.platform_owner(here) == "player" and assault == "":
			var r := region.find_route(u.position, hub)
			if not r.is_empty():
				u.set_route(r, true)
	# Attack the nearest reachable rival HQ with all but a home guard.
	var wave: int = main.waves.wave
	if army.size() >= army_goal - 2 and wave >= attack_wave:
		if assault == "" or main.combat.headquarters_on(assault) == null:
			assault = ""
			var best_d := INF
			for corp in main.waves.rival_corps():
				var hq_name := RivalCatalog.hq_of(corp)
				if main.combat.headquarters_on(hq_name) == null:
					continue
				var spot := region.snap_to_walkable(region.get_platform_position(hq_name))
				var r := region.find_route(hub, spot)
				if r.is_empty():
					continue
				if r.size() < best_d:
					best_d = r.size()
					assault = hq_name
	if assault != "":
		var spot := region.snap_to_walkable(region.get_platform_position(assault))
		for i in range(maxi(0, idle.size() - 3)):
			var u: Unit = idle[i]
			if region.platform_at(u.position) == assault:
				continue
			var r := region.find_route(u.position, spot)
			if not r.is_empty():
				u.set_route(r, true)


func _trace(t: float) -> void:
	var hq = main.combat.headquarters_on("Hub")
	var c := {}
	for e in get_nodes_in_group(Unit.ENEMY_GROUP):
		var where := region.platform_at(e.position)
		var k: String = e.display_name.get_slice(" ", e.display_name.get_slice_count(" ") - 1) + "@" + (where if where != "" else ("air" if e.flying else "walk"))
		c[k] = c.get(k, 0) + 1
	var mine := {}
	for u in get_nodes_in_group(Unit.GROUP):
		mine[u.display_name] = mine.get(u.display_name, 0) + 1
	var towers := []
	for b in region.buildings_on("Hub"):
		towers.append("%s%.0f" % [b.type_id.left(4), b.hp])
	for e in get_nodes_in_group(Unit.ENEMY_GROUP):
		if region.platform_at(e.position) == "Hub":
			var ds := []
			for b in region.buildings_on("Hub"):
				ds.append("%.1f" % Vector2(b.global_position.x - e.global_position.x, b.global_position.z - e.global_position.z).length())
			print("     %s hp %.0f/%.0f armor %.2f riding %s dists %s" % [e.display_name, e.hp, e.max_hp, e.armor, e.riding, ds])
	print("   load %s %d/%d eff %.2f towers %s" % [main.loads.state_of("Hub"), region.platform_load("Hub"), region.platform_capacity("Hub"), region.grid_efficiency(), towers])
	print("   t=%.0f hub=%s bld=%d | enemies %s | mine %s" % [t, ("%.0f" % hq.hp) if hq else "-", region.buildings_on("Hub").size(), c, mine])


## A platform's tiles, closest to its middle (where the HQ is) first.
func _tiles_near_hq(platform_name: String) -> Array:
	var mid := region.get_platform_position(platform_name)
	var hexes: Array = region.tiles_of_platform(platform_name)
	hexes.sort_custom(func(a, b): return region.hex_center(a).distance_to(mid) < region.hex_center(b).distance_to(mid))
	return hexes
