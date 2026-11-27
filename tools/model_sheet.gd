## Renders a labelled line-up of every model in the game through the game's
## own camera: all buildings on the Hub, every ground unit (yours and a
## rival's), every airship and drone, and each headquarters. Use it to review
## the models after changing ModelKit, BuildingModels or UnitModels.
## Needs a display (use xvfb-run on a server):
##   godot --path . --script res://tools/model_sheet.gd -- out_dir
extends SceneTree

var main: Node
var cam: RtsCamera
var region: SkyRegion


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "user://model_sheet"
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1920, 1080)
	SkyRegion.seed_override = 3
	SkyRegion.rivals_override = RivalCatalog.layout_rivals(4)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	cam = main.get_node("RtsCamera")
	region = main.get_node("Region")
	await _settle()
	main.fog.reveal_all()
	for platform_name in region.platforms:
		var plate := region.platform_label(platform_name)
		if plate:
			plate.visible = false
	# Freeze the game: this is a photo shoot, not a battle.
	for system in [main.waves, main.combat, main.economy, main.defenses, main.patrols, main.selection]:
		system.set_process(false)
		system.set_process_unhandled_input(false)
	for child in main.get_children():
		if child is CanvasLayer:
			child.visible = false
	for u in main.get_node("Units").get_children():
		if not (u as Unit).is_hero:
			u.queue_free()

	# Buildings: one of each on the Hub's free deck tiles, in catalog order.
	var hub: Vector2i = region.platforms["Hub"].center
	var free: Array[Vector2i] = []
	for hex in region.tiles_of_platform("Hub"):
		if region.tiles[hex].type == "deck" and not region.buildings.has(hex) and HexGrid.distance(hex, hub) >= 2:
			free.append(hex)
	free.sort_custom(func(a, b):
		var pa := region.hex_center(a)
		var pb := region.hex_center(b)
		return pa.z < pb.z if absf(pa.z - pb.z) > 0.1 else pa.x < pb.x)
	var ids := BuildingCatalog.BUILDINGS.keys()
	for i in ids.size():
		var hex: Vector2i = free[int(i * float(free.size() - 1) / maxi(1, ids.size() - 1))]
		if region.buildings.has(hex):
			continue
		region.place_building(Building.new().setup(ids[i]), hex)
		_label(region.hex_center(hex) + Vector3(0, 3.6, 0), BuildingCatalog.get_data(ids[i]).name)
	var hub_at := region.get_platform_position("Hub")
	await _shot(hub_at + Vector3(0, 0, 1.0), 0.09, out_dir + "/buildings.png")
	await _shot(hub_at + Vector3(-4, 0, -3.0), 0.03, out_dir + "/buildings-northwest.png")
	await _shot(hub_at + Vector3(4, 0, -3.0), 0.03, out_dir + "/buildings-northeast.png")
	await _shot(hub_at + Vector3(-4, 0, 4.0), 0.03, out_dir + "/buildings-southwest.png")
	await _shot(hub_at + Vector3(4, 0, 4.0), 0.03, out_dir + "/buildings-southeast.png")

	# Ground units: a row of yours and a row of a rival's, on the first
	# neutral island big enough.
	var stage := ""
	for p in region.layout.platforms:
		if p.name != "Hub" and region.platform_owner(p.name) == "" and region.tiles_of_platform(p.name).size() >= 19:
			stage = p.name
			break
	var at := region.get_platform_position(stage)
	var types := UnitCatalog.UNITS.keys()
	var spacing := 2.1
	for i in types.size():
		var x := (i - (types.size() - 1) / 2.0) * spacing
		if types[i] != "walker":
			_unit(UnitCatalog.make(types[i], "player"), at + Vector3(x, 0, 1.6), types[i].capitalize())
		_unit(UnitCatalog.make(types[i], "rival"), at + Vector3(x, 0, -1.8), "Rival " + types[i].capitalize())
	for u in main.get_node("Units").get_children():
		if (u as Unit).is_hero:
			u.position = at + Vector3((types.size() - 1) / 2.0 * spacing, 0, 1.6)
			u.rotation.y = 0.0
			u.set_process(false)
			_label(u.position + Vector3(0, 3.6, 0), "Commander")
	await _shot(at + Vector3(0, 0, 0.5), 0.0, out_dir + "/ground-units.png")
	await _shot(at + Vector3(0, 0, 0.5), 0.3, out_dir + "/ground-units-far.png")

	# Airships and drones, flying over open sky next to the stage island.
	var sky := at
	for u in main.get_node("Units").get_children():
		u.position.y -= 200.0
	for l in _labels:
		l.visible = false
	var back := [["drone", "player"], ["airship", "bomber"], ["airship", "gunship"], ["airship", "carrier"], ["drone", "rival"]]
	var xs := [-9.0, -5.0, -1.0, 3.8, 8.5]
	for i in back.size():
		var here := sky + Vector3(xs[i], VesperFleet.ALTITUDE, -4.0)
		if back[i][0] == "drone":
			_unit(_drone(back[i][1]), here, ("Your" if back[i][1] == "player" else "Rival") + " drone", 0.5)
		else:
			var u: Unit = main.fleet._make(back[i][1])
			u.set_meta("corp", VesperFleet.AIRSHIPS[back[i][1]].corp)
			_unit(u, here, VesperFleet.AIRSHIPS[back[i][1]].name, 0.5)
	var k := 0
	for kind in AirPatrols.SHIPS:
		for job in (AirPatrols.UTILITY_JOBS if kind == "utility" else [""]):
			var u: Unit = _player_ship(kind, job)
			_unit(u, sky + Vector3(k * 3.5 - 7.0, AirPatrols.ALTITUDE, 3.0), u.display_name, 0.5)
			k += 1
	await _shot(sky + Vector3(0, VesperFleet.ALTITUDE * 0.6, 1.0), 0.03, out_dir + "/airships.png")
	await _shot(sky + Vector3(0, 0, 1.0), 0.25, out_dir + "/airships-far.png")

	# The ferry, the balloon island tug and each headquarters.
	for l in _labels:
		l.visible = false
	if not main.ferry.ferries.is_empty():
		var ship: Node3D = main.ferry.ferries[0].ship
		await _shot(ship.position, 0.02, out_dir + "/ferry.png")
	await _shot(hub_at + Vector3(0, 2.5, 1.5), 0.0, out_dir + "/hq-player.png")
	for corp in RivalCatalog.ORDER:
		await _shot(region.get_platform_position(RivalCatalog.hq_of(corp)) + Vector3(0, 2.5, 1.5), 0.0, out_dir + "/hq-%s.png" % corp.to_lower())
	quit(0)


var _labels: Array[Label3D] = []


func _unit(u: Unit, at: Vector3, text: String, yaw := 0.0) -> void:
	u.position = at
	main.get_node("Units").add_child(u)
	u.rotation.y = yaw
	u.set_process(false)
	_label(at + Vector3(0, 2.9 if not u.flying else 2.4, 0), text)


## Look-alikes of the ships AirPatrols launches (visuals only).
func _player_ship(kind: String, job: String) -> Unit:
	var spec: Dictionary = AirPatrols.SHIPS[kind]
	var u := Unit.new()
	u.display_name = main.patrols.ship_name(kind, job)
	u.is_drone = true
	u.flying = true
	u.footprint = spec.footprint
	u.body_color = spec.color
	u.set_meta("ship", kind)
	u.set_meta("job", job)
	return u


## A look-alike of a hangar's defense drone (visuals only).
func _drone(side: String) -> Unit:
	var d := Unit.new()
	d.display_name = "Defense Drone"
	d.faction = side
	d.is_drone = true
	d.flying = true
	d.footprint = 0.45
	d.body_color = Color(0.8, 0.65, 0.3) if side == "player" else Color(0.6, 0.3, 0.3)
	return d


func _label(at: Vector3, text: String) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = 30
	l.outline_size = 10
	l.pixel_size = 0.008
	l.position = at
	main.add_child(l)
	_labels.append(l)
	return l


func _shot(at: Vector3, zoom: float, path: String) -> void:
	cam.position = at
	cam.zoom = zoom
	cam._target_zoom = zoom
	cam._apply_zoom()
	await _settle()
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("Saved ", path)


func _settle() -> void:
	for i in 12:
		await process_frame
