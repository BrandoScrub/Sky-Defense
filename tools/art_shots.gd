## Renders close-ups for reviewing the art: the Hub, one island of each type,
## the rival airships and a wide view, all with the fog lifted. Needs a
## display (use xvfb-run on a server):
##   godot --path . --script res://tools/art_shots.gd -- out_dir
extends SceneTree

var main: Node
var cam: RtsCamera
var region: SkyRegion


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "user://art_shots"
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1600, 900)
	SkyRegion.seed_override = 3
	SkyRegion.prebuilt_walkways = true
	SkyRegion.instant_walkways = true
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	cam = main.get_node("RtsCamera")
	region = main.get_node("Region")
	await _settle()
	main._help.visible = false
	main.fog.reveal_all()
	main.waves.set_process(false)

	# The Hub with a few buildings and the squad.
	var hub: Vector2i = region.platforms["Hub"].center
	main.resources.add_scrap(400)
	main.building.try_place("dynamo", hub + Vector2i(2, -1))
	main.building.try_place("rivet_turret", hub + Vector2i(2, 0), 1)
	main.building.try_place("flak_battery", hub + Vector2i(-2, 0))
	main.building.try_place("arc_coil", hub + Vector2i(1, -2))
	await _shot(region.get_platform_position("Hub"), 0.28, out_dir + "/art-hub.png")

	# One island of each type.
	var seen := {}
	for p in region.layout.platforms:
		var key: String = p.get("variant", "") if p.get("style", "") == "crystal" else p.get("style", "city")
		if key == "city" or seen.has(key):
			continue
		seen[key] = true
		await _shot(region.get_platform_position(p.name), 0.22, out_dir + "/art-island-%s.png" % key)

	# Rival airships over the Hub.
	var ships: Array[Unit] = []
	var at := region.get_platform_position("Hub") + Vector3(3, VesperFleet.ALTITUDE, -6)
	var k := 0
	for kind in ["bomber", "gunship", "carrier"]:
		var u: Unit = main.fleet._make(kind)
		main.fleet._units_root().add_child(u)
		u.position = at + Vector3(k * 4.0 - 4.0, 0, k * 1.5)
		u.rotation.y = 0.6
		u.set_process(false)
		ships.append(u)
		k += 1
	await _shot(at + Vector3(0, -VesperFleet.ALTITUDE, 2), 0.14, out_dir + "/art-airships.png")
	for u in ships:
		u.queue_free()

	# Wide view.
	var mid := region.get_bounds().get_center()
	await _shot(Vector3(mid.x, 0, mid.y + 8), 0.75, out_dir + "/art-overview.png")
	quit(0)


func _shot(at: Vector3, zoom: float, path: String) -> void:
	cam.position = at
	cam.zoom = zoom
	cam._target_zoom = zoom
	cam._apply_zoom()
	await _settle()
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("Saved ", path)


func _settle() -> void:
	for i in 12:
		await process_frame
