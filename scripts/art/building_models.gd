## The model for every building shape in BuildingCatalog, assembled from the
## shared ModelKit parts. Each building stands on the same riveted bedplate
## and shows what it does: generators have a flywheel and insulators, guns
## have barrels and ammunition, engines have intakes, exhausts and fuel lines.
## The building's catalog colour is its paint ("accent"), so buildings keep
## the colours the build menu and legend use. Front is +Z.
class_name BuildingModels
extends RefCounted


static func build(root: Node3D, shape: String, k: ModelKit) -> void:
	match shape:
		"generator":
			_generator(root, k, k.bedplate(root))
		"harvester":
			_harvester(root, k, k.bedplate(root, 0.85))
		"lift":
			_lift(root, k, k.bedplate(root))
		"turret":
			_turret(root, k, k.bedplate(root))
		"coil":
			_coil(root, k, k.bedplate(root))
		"horn":
			_horn(root, k, k.bedplate(root))
		"mender":
			_mender(root, k, k.bedplate(root))
		"flak":
			_flak(root, k, k.bedplate(root))
		"skyhook":
			_skyhook(root, k, k.bedplate(root))
		"engine":
			_engine(root, k, k.bedplate(root))
		"airship_hangar":
			_hangar(root, k, k.bedplate(root, 1.38))
		"mast":
			_mast(root, k, k.bedplate(root))
		_:
			k.drum(root, 0.7, 0.8, 1.0, Vector3(0, k.bedplate(root) + 0.5, 0), "accent")


## Dynamo Generator: a banded casing with copper windings, a flywheel turning
## on one side, an exhaust stack, and two insulators where the power leaves.
static func _generator(root: Node3D, k: ModelKit, y: float) -> void:
	var c := Vector3(-0.15, y, 0)
	k.drum(root, 0.62, 0.7, 1.1, c + Vector3(0, 0.55, 0), "accent", 14)
	for h in [0.3, 0.55, 0.8]:
		k.ring(root, 0.69 - h * 0.07, 0.05, c + Vector3(0, h, 0), "copper")
	k.rivets(root, 0.64, y + 1.0, 8)
	k.dome(root, 0.62, c + Vector3(0, 1.1, 0), "brass", 0.45)
	# Insulators with a live glow on top.
	for z in [-0.22, 0.22]:
		k.drum(root, 0.06, 0.1, 0.3, c + Vector3(0, 1.5, z), "ceramic", 8)
		k.ring(root, 0.1, 0.03, c + Vector3(0, 1.48, z), "ceramic")
		k.ball(root, 0.08, c + Vector3(0, 1.7, z), "hum")
	# The flywheel and its bearing block.
	k.rod(root, Vector3(0.3, y + 0.6, 0), Vector3(0.95, y + 0.6, 0), 0.06, "steel")
	k.box(root, Vector3(0.16, 0.6, 0.3), Vector3(0.95, y + 0.3, 0), "iron")
	var wheel := k.group(root, Vector3(0.72, y + 0.6, 0))
	ModelKit.aim(wheel, Vector3.RIGHT)
	var rotor := k.group(wheel)
	k.ring(rotor, 0.44, 0.06, Vector3.ZERO, "brass")
	for i in 3:
		var spoke := k.box(rotor, Vector3(0.84, 0.05, 0.08), Vector3.ZERO, "iron")
		spoke.rotation.y = i * PI / 3.0
	ModelKit.spin(rotor, 1.6)
	k.stack(root, Vector3(-0.7, y, -0.65), 1.7, 0.13)
	k.pipe(root, [Vector3(-0.15, y + 0.35, 0.66), Vector3(-0.15, y + 0.35, 0.98), Vector3(-0.15, y, 0.98)], 0.06)
	k.vent(root, Vector3(-0.15, y + 0.55, -0.67), Vector3.FORWARD, 0.5, 0.3)


## Cloud Harvester: a winch and mast holding a collector balloon up in the
## storm, a copper funnel under it, and glowing storage jars at the foot.
static func _harvester(root: Node3D, k: ModelKit, y: float) -> void:
	k.box(root, Vector3(0.7, 0.4, 0.6), Vector3(0, y + 0.2, -0.25), "iron")
	var winch := k.rod(root, Vector3(-0.3, y + 0.55, -0.25), Vector3(0.3, y + 0.55, -0.25), 0.2, "copper", 10)
	winch.name = "Winch"
	for x in [-0.32, 0.32]:
		k.rod(root, Vector3(x - 0.02, y + 0.55, -0.25), Vector3(x + 0.02, y + 0.55, -0.25), 0.27, "brass", 10)
	# Storage jars.
	for x in [-0.4, 0.4]:
		k.drum(root, 0.16, 0.16, 0.45, Vector3(x, y + 0.23, 0.4), "accent", 10)
		k.ball(root, 0.13, Vector3(x, y + 0.5, 0.4), "hum")
	# Three-legged mast.
	var top := Vector3(0, y + 2.7, 0)
	for i in 3:
		var a := TAU * i / 3.0 + PI / 6.0
		k.rod(root, Vector3(cos(a) * 0.6, y, sin(a) * 0.6), top, 0.045, "iron", 6)
	k.ring(root, 0.31, 0.03, Vector3(0, y + 1.35, 0), "brass")
	k.rod(root, Vector3(0, y + 0.6, -0.25), top, 0.025, "rubber", 6)
	k.rod(root, top, top + Vector3(0, 0.75, 0), 0.03, "rubber", 6)
	# The collector: funnel, balloon, lightning rod.
	k.cone(root, top + Vector3(0, 1.0, 0), top + Vector3(0, 0.55, 0), 0.5, 0.08, "copper", 12)
	k.balloon(root, top + Vector3(0, 1.75, 0), 0.8, 2.0, "canvas", 3)
	k.dome(root, 0.5, top + Vector3(0, 2.35, 0), "accent", 0.45)
	k.rod(root, top + Vector3(0, 2.5, 0), top + Vector3(0, 3.1, 0), 0.03, "copper", 6)
	k.ball(root, 0.09, top + Vector3(0, 3.15, 0), "hum")


## Lift Engine: a squat housing with intake grilles and a big ducted fan
## pushing the deck up.
static func _lift(root: Node3D, k: ModelKit, y: float) -> void:
	k.drum(root, 0.8, 0.95, 0.75, Vector3(0, y + 0.375, 0), "accent_dark", 8)
	for i in 4:
		var n := Vector3(sin(i * PI / 2.0), 0, cos(i * PI / 2.0))
		k.vent(root, n * 0.84 + Vector3(0, y + 0.38, 0), n, 0.5, 0.36)
	k.drum(root, 0.98, 0.84, 0.3, Vector3(0, y + 0.9, 0), "iron", 16)
	k.ring(root, 0.98, 0.06, Vector3(0, y + 1.05, 0), "brass")
	k.drum(root, 0.84, 0.84, 0.04, Vector3(0, y + 0.8, 0), "rubber", 16)
	k.propeller(root, Vector3(0, y + 0.98, 0), Vector3.UP, 0.85, 4, 0.5, "brass")
	for i in 2:
		k.box(root, Vector3(1.9, 0.05, 0.07), Vector3(0, y + 1.08, 0), "iron").rotation.y = i * PI / 2.0 + PI / 4.0
	k.pipe(root, [Vector3(0.9, y + 0.5, 0.5), Vector3(1.05, y + 0.5, 0.6), Vector3(1.05, y, 0.6)], 0.06)


## Rivet Turret: an armoured casemate with a traversing gun head, an
## ammunition drum, and cover plates that shelter troops beside it.
static func _turret(root: Node3D, k: ModelKit, y: float) -> void:
	var base := k.drum(root, 0.82, 0.98, 0.45, Vector3(0, y + 0.225, 0), "accent", 8)
	base.rotation.y = PI / 8.0
	k.rivets(root, 0.92, y + 0.3, 8)
	k.ring(root, 0.62, 0.05, Vector3(0, y + 0.47, 0), "brass")
	for side in [-1.0, 1.0]:
		var plate := k.box(root, Vector3(0.1, 0.75, 1.0), Vector3(side * 1.12, y + 0.37, 0.25), "steel")
		plate.rotation.y = side * 0.3
		k.box(root, Vector3(0.14, 0.07, 1.0), Vector3(side * 1.12, y + 0.76, 0.25), "brass").rotation.y = side * 0.3
	var head := k.group(root, Vector3(0, y + 0.45, 0), "Head")
	k.drum(head, 0.48, 0.58, 0.42, Vector3(0, 0.21, 0), "steel", 10)
	k.box(head, Vector3(0.62, 0.36, 0.34), Vector3(0, 0.24, 0.42), "accent_dark")
	k.barrel(head, Vector3(0, 0.26, 0.5), Vector3(0, 0.08, 1.0), 1.1, 0.085)
	k.rod(head, Vector3(-0.6, 0.22, 0.05), Vector3(-0.42, 0.22, 0.05), 0.22, "brass", 10)
	k.hatch(head, Vector3(0.05, 0.42, -0.12), 0.2)
	k.lamp(head, Vector3(-0.25, 0.42, -0.3), 0.12, 0.07)
	k.pennant(root, Vector3(0.75, y, -0.75), 1.1)


## Arc Coil: copper windings round a ceramic insulator stack, with a charged
## ring on top that throws chain lightning.
static func _coil(root: Node3D, k: ModelKit, y: float) -> void:
	var glow := k.paint(k.accent.lightened(0.25), 2.4)
	k.drum(root, 0.62, 0.8, 0.35, Vector3(0, y + 0.175, 0), "iron", 10)
	for i in 3:
		k.ring(root, 0.62 - i * 0.09, 0.055, Vector3(0, y + 0.42 + i * 0.13, 0), "copper")
	k.drum(root, 0.16, 0.26, 1.5, Vector3(0, y + 1.1, 0), "ceramic", 10)
	for i in 4:
		k.ring(root, 0.29 - i * 0.025, 0.045, Vector3(0, y + 0.9 + i * 0.28, 0), "ceramic")
	k.ring(root, 0.52, 0.16, Vector3(0, y + 2.0, 0), "brass")
	k.ball(root, 0.3, Vector3(0, y + 2.05, 0), glow)
	k.rod(root, Vector3(0, y + 2.3, 0), Vector3(0, y + 2.75, 0), 0.03, "copper", 6)
	k.ball(root, 0.07, Vector3(0, y + 2.78, 0), glow)
	# Spark gap and earth cable.
	for x in [-0.12, 0.12]:
		k.rod(root, Vector3(x * 3.0, y, 0.82), Vector3(x, y + 0.4, 0.82), 0.03, "copper", 6)
		k.ball(root, 0.06, Vector3(x, y + 0.42, 0.82), "brass")
	k.pipe(root, [Vector3(-0.6, y + 0.2, -0.5), Vector3(-0.9, y + 0.2, -0.7), Vector3(-0.9, y, -0.7)], 0.05, "rubber")


## Rally Horn: a great brass horn on a mast, blown by a bellows and air tank,
## flying the company pennant.
static func _horn(root: Node3D, k: ModelKit, y: float) -> void:
	k.box(root, Vector3(0.75, 0.5, 0.9), Vector3(-0.4, y + 0.25, -0.1), "leather")
	for z in [-0.4, -0.1, 0.2]:
		k.box(root, Vector3(0.8, 0.54, 0.06), Vector3(-0.4, y + 0.26, z), "accent")
	k.tank(root, Vector3(0.5, y + 0.28, -0.55), 0.22, 0.5, Vector3.RIGHT, "copper")
	var mast_top := Vector3(0.3, y + 2.0, 0)
	k.drum(root, 0.2, 0.3, 0.3, Vector3(0.3, y + 0.15, 0), "iron", 8)
	k.rod(root, Vector3(0.3, y, 0), mast_top, 0.07, "iron")
	k.pipe(root, [Vector3(-0.4, y + 0.5, -0.1), Vector3(-0.4, y + 0.9, -0.1), Vector3(0.22, y + 1.5, -0.05), mast_top + Vector3(0, -0.1, -0.2)], 0.06)
	# The big horn and two smaller ones.
	k.cone(root, mast_top + Vector3(0, 0.25, 1.05), mast_top + Vector3(0, -0.1, -0.25), 0.58, 0.07, "brass", 14)
	ModelKit.aim(k.drum(root, 0.5, 0.5, 0.02, mast_top + Vector3(0, 0.255, 1.07), "rubber", 14), Vector3(0, 0.35, 1.3))
	var rim := k.ring(root, 0.58, 0.04, mast_top + Vector3(0, 0.25, 1.05), "brass")
	ModelKit.aim(rim, Vector3(0, 0.35, 1.3))
	for side in [-1.0, 1.0]:
		k.cone(root, mast_top + Vector3(side * 0.55, -0.3, 0.55), mast_top + Vector3(side * 0.1, -0.45, -0.1), 0.26, 0.04, "brass", 10)
	k.pennant(root, mast_top, 0.9)
	k.lamp(root, Vector3(-0.4, y + 0.5, 0.2), 0.1, 0.08)


## Mending Post: a white tonic tank under a big green cross, a medicine
## cabinet, and a sprayer arm on a hose.
static func _mender(root: Node3D, k: ModelKit, y: float) -> void:
	var tonic := k.paint(k.accent.lightened(0.2), 1.6)
	k.tank(root, Vector3(-0.25, y + 0.7, -0.2), 0.5, 0.8, Vector3.UP, "ceramic")
	k.drum(root, 0.6, 0.6, 0.06, Vector3(-0.25, y + 1.42, -0.2), "ceramic", 14)
	k.box(root, Vector3(1.0, 0.09, 0.3), Vector3(-0.25, y + 1.48, -0.2), "accent")
	k.box(root, Vector3(0.3, 0.09, 1.0), Vector3(-0.25, y + 1.48, -0.2), "accent")
	# Cabinet with tonic bottles.
	k.box(root, Vector3(0.6, 0.6, 0.7), Vector3(0.62, y + 0.3, -0.1), "ceramic")
	k.box(root, Vector3(0.64, 0.06, 0.74), Vector3(0.62, y + 0.62, -0.1), "brass")
	for z in [-0.28, 0.0, 0.28]:
		k.drum(root, 0.07, 0.09, 0.26, Vector3(0.62, y + 0.78, -0.1 + z), tonic, 8)
	# Hose reel and sprayer arm.
	var reel := k.ring(root, 0.24, 0.07, Vector3(-0.25, y + 0.5, 0.36), "rubber")
	reel.rotation.x = PI / 2.0
	k.pipe(root, [Vector3(-0.25, y + 1.2, 0.3), Vector3(-0.1, y + 1.3, 0.75), Vector3(0.1, y + 1.05, 1.0)], 0.045, "rubber")
	k.cone(root, Vector3(0.17, y + 0.95, 1.1), Vector3(0.1, y + 1.05, 1.0), 0.1, 0.04, "brass", 8)
	k.pennant(root, Vector3(0.85, y, 0.6), 1.0)


## Flak Battery: four barrels on a traversing ring mount, splinter shields
## either side, a ring sight and ready ammunition behind.
static func _flak(root: Node3D, k: ModelKit, y: float) -> void:
	k.drum(root, 0.8, 0.95, 0.3, Vector3(0, y + 0.15, 0), "accent", 12)
	k.rivets(root, 0.9, y + 0.2, 8)
	k.ring(root, 0.66, 0.05, Vector3(0, y + 0.32, 0), "brass")
	var head := k.group(root, Vector3(0, y + 0.3, 0), "Head")
	k.box(head, Vector3(1.0, 0.34, 0.6), Vector3(0, 0.25, -0.05), "steel")
	var up := Vector3(0, sin(deg_to_rad(52.0)), cos(deg_to_rad(52.0)))
	for x in [-0.36, -0.13, 0.13, 0.36]:
		k.barrel(head, Vector3(x, 0.38, -0.05), up, 1.35, 0.055)
	for side in [-1.0, 1.0]:
		var shield := k.box(head, Vector3(0.07, 0.7, 0.85), Vector3(side * 0.62, 0.55, 0.2), "accent")
		shield.rotation.x = -0.35
	# Ring sight, seat and ammunition.
	k.rod(head, Vector3(0, 0.4, -0.3), Vector3(0, 0.95, -0.2), 0.02, "iron", 6)
	ModelKit.aim(k.ring(head, 0.13, 0.02, Vector3(0, 1.0, -0.19), "brass"), up)
	k.box(head, Vector3(0.3, 0.1, 0.25), Vector3(0, 0.42, -0.5), "leather")
	k.box(root, Vector3(0.5, 0.3, 0.35), Vector3(-0.55, y + 0.15, -0.9), "accent_dark")
	for i in 3:
		k.drum(root, 0.05, 0.05, 0.28, Vector3(-0.7 + i * 0.15, y + 0.44, -0.9), "brass", 6)
	k.pennant(root, Vector3(0.8, y, -0.8), 1.1)


## Skyhook Gun: a heavy harpoon launcher on a yoke, with the cable drum and
## winch that reel big airships in.
static func _skyhook(root: Node3D, k: ModelKit, y: float) -> void:
	k.drum(root, 0.75, 0.92, 0.32, Vector3(0, y + 0.16, 0), "accent", 10)
	k.rivets(root, 0.86, y + 0.2, 8)
	var head := k.group(root, Vector3(0, y + 0.32, 0), "Head")
	for side in [-1.0, 1.0]:
		k.box(head, Vector3(0.12, 0.85, 0.4), Vector3(side * 0.34, 0.42, 0.05), "iron")
		k.rod(head, Vector3(side * 0.42, 0.7, 0.05), Vector3(side * 0.28, 0.7, 0.05), 0.1, "brass", 8)
	var dir := Vector3(0, sin(deg_to_rad(42.0)), cos(deg_to_rad(42.0)))
	var breech := Vector3(0, 0.7, 0.05) - dir * 0.55
	var muzzle := breech + dir * 1.9
	k.rod(head, breech, muzzle, 0.18, "steel", 10)
	for t in [0.1, 0.45, 0.95]:
		k.rod(head, breech + dir * (1.9 * t - 0.05), breech + dir * (1.9 * t + 0.05), 0.21, "brass", 10)
	# The harpoon: shaft, barbed head.
	k.rod(head, muzzle, muzzle + dir * 0.45, 0.05, "iron", 6)
	k.cone(head, muzzle + dir * 0.4, muzzle + dir * 0.85, 0.17, 0.0, "brass", 4)
	# Cable drum at the back, cable up to the breech.
	var spool := Vector3(0, 0.3, -0.72)
	k.rod(head, spool + Vector3(-0.3, 0, 0), spool + Vector3(0.3, 0, 0), 0.26, "rubber", 10)
	for side in [-1.0, 1.0]:
		k.rod(head, spool + Vector3(side * 0.3, 0, 0), spool + Vector3(side * 0.34, 0, 0), 0.34, "brass", 10)
	k.rod(head, spool + Vector3(0, 0.2, 0), breech, 0.03, "rubber", 6)
	var crank := k.ring(head, 0.16, 0.025, spool + Vector3(0.42, 0, 0), "brass")
	crank.rotation.z = PI / 2.0
	k.lamp(root, Vector3(-0.7, y, 0.55), 0.3, 0.08)
	k.pennant(root, Vector3(0.75, y, -0.75), 1.1)


## Turbine Engine: a cowled engine on a pylon, propeller facing out, with
## exhaust stubs, an intake ring and its fuel tank.
static func _engine(root: Node3D, k: ModelKit, y: float) -> void:
	k.drum(root, 0.4, 0.7, 0.55, Vector3(0, y + 0.275, 0), "iron", 8)
	k.box(root, Vector3(0.3, 0.5, 0.9), Vector3(0, y + 0.6, -0.05), "iron")
	var axis := Vector3(0, y + 1.25, 0)
	k.cone(root, axis + Vector3(0, 0, 0.7), axis + Vector3(0, 0, -0.75), 0.62, 0.5, "accent", 14)
	k.cone(root, axis + Vector3(0, 0, -0.75), axis + Vector3(0, 0, -1.15), 0.5, 0.12, "accent_dark", 14)
	for z in [0.68, 0.1, -0.5]:
		ModelKit.aim(k.ring(root, 0.63 - (0.68 - z) * 0.08, 0.04, axis + Vector3(0, 0, z), "brass"), Vector3(0, 0, 1))
	k.rod(root, axis + Vector3(0, 0, 0.7), axis + Vector3(0, 0, 0.74), 0.55, "rubber", 14)
	k.propeller(root, axis + Vector3(0, 0, 0.78), Vector3(0, 0, 1), 1.0, 3, 0.4)
	for side in [-1.0, 1.0]:
		k.pipe(root, [axis + Vector3(side * 0.4, 0.35, -0.1), axis + Vector3(side * 0.55, 0.6, -0.4), axis + Vector3(side * 0.55, 0.65, -0.8)], 0.07)
		k.vent(root, axis + Vector3(side * 0.6, 0, -0.2), Vector3(side, 0, 0), 0.45, 0.25)
	k.tank(root, Vector3(-0.72, y + 0.3, -0.5), 0.24, 0.5, Vector3(0, 0, 1), paint_fuel(k))
	k.pipe(root, [Vector3(-0.72, y + 0.55, -0.5), Vector3(-0.72, y + 0.85, -0.5), Vector3(-0.3, y + 0.95, -0.4)], 0.04, "rubber")


## Airship Hangar: a ribbed barrel-vault shed with lit doors, drone cradles on
## the roof, a fuel tank and a mooring mast with a lamp.
static func _hangar(root: Node3D, k: ModelKit, y: float) -> void:
	k.box(root, Vector3(1.9, 0.8, 1.9), Vector3(0, y + 0.4, 0), "accent")
	k.rod(root, Vector3(0, y + 0.8, -0.95), Vector3(0, y + 0.8, 0.95), 0.95, "accent_dark", 16)
	for z in [-0.9, -0.3, 0.3, 0.9]:
		ModelKit.aim(k.ring(root, 0.95, 0.05, Vector3(0, y + 0.8, z), "brass"), Vector3(0, 0, 1))
	# Doors: a dark opening with lit shop lights and brass rails.
	k.box(root, Vector3(1.3, 1.1, 0.06), Vector3(0, y + 0.55, 0.96), "rubber")
	k.box(root, Vector3(1.1, 0.1, 0.08), Vector3(0, y + 0.95, 0.97), "glass")
	for x in [-0.68, 0.68]:
		k.box(root, Vector3(0.08, 1.15, 0.1), Vector3(x, y + 0.57, 0.98), "brass")
		k.lamp(root, Vector3(x * 1.3, y, 1.08), 0.5, 0.08)
	# Landing apron stripes in front of the doors.
	for x in [-0.5, 0.0, 0.5]:
		k.box(root, Vector3(0.14, 0.02, 0.4), Vector3(x, y + 0.01, 1.15), "brass")
	# Drone cradles on the roof ridge.
	for z in [-0.45, 0.45]:
		k.drum(root, 0.3, 0.34, 0.1, Vector3(0, y + 1.78, z), "iron", 10)
		k.ring(root, 0.26, 0.035, Vector3(0, y + 1.85, z), "brass")
	k.hatch(root, Vector3(0, y + 1.75, 0), 0.14)
	# Fuel tank and the mooring mast.
	k.tank(root, Vector3(-1.12, y + 0.3, 0.2), 0.24, 0.8, Vector3(0, 0, 1), paint_fuel(k))
	var foot := Vector3(1.05, y, -0.85)
	k.drum(root, 0.12, 0.2, 0.3, foot + Vector3(0, 0.15, 0), "iron", 8)
	k.rod(root, foot, foot + Vector3(0, 3.1, 0), 0.055, "iron")
	k.rod(root, foot + Vector3(0, 1.2, 0), Vector3(0.75, y + 1.5, -0.7), 0.03, "iron", 6)
	k.ring(root, 0.16, 0.03, foot + Vector3(0, 3.0, 0.2), "brass")
	k.lamp(root, foot + Vector3(0, 3.1, 0), 0.0, 0.13)
	k.pennant(root, foot + Vector3(0, 2.0, 0), 0.7)


## Mooring Mast: a lattice tower with a mooring ring and beacon on top, a
## signal dish, and a fuel tank with a hose at its foot.
static func _mast(root: Node3D, k: ModelKit, y: float) -> void:
	var c := Vector3(0.2, y, -0.15)
	var top := c + Vector3(0, 3.0, 0)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			k.rod(root, c + Vector3(sx * 0.45, 0, sz * 0.45), top + Vector3(sx * 0.08, 0, sz * 0.08), 0.04, "iron", 6)
	for h in [0.8, 1.6, 2.4]:
		var w := lerpf(0.45, 0.08, h / 3.0) * 1.42
		var brace := k.drum(root, w, w, 0.05, c + Vector3(0, h, 0), "brass", 4)
		brace.rotation.y = PI / 4.0
	k.drum(root, 0.3, 0.2, 0.1, top, "iron", 10)
	k.ring(root, 0.34, 0.035, top + Vector3(0, 0.08, 0), "brass")
	k.rod(root, top, top + Vector3(0, 0.35, 0), 0.04, "iron", 6)
	k.ball(root, 0.16, top + Vector3(0, 0.48, 0), "hum")
	# Signal dish facing out and up.
	var dish_at := c + Vector3(0, 2.2, 0.25)
	k.cone(root, dish_at + Vector3(0, 0.12, 0.2), dish_at, 0.45, 0.06, "accent", 12)
	k.ball(root, 0.06, dish_at + Vector3(0, 0.2, 0.33), "lamp")
	# Fuel tank on cradles, hose up the mast.
	var fuel := Vector3(-0.6, y + 0.42, 0.25)
	k.tank(root, fuel, 0.32, 0.8, Vector3(0, 0, 1), paint_fuel(k))
	for z in [-0.25, 0.25]:
		k.box(root, Vector3(0.6, 0.16, 0.1), fuel + Vector3(0, -0.34, z), "iron")
	k.ring(root, 0.1, 0.02, fuel + Vector3(0, 0.36, 0), "brass")
	k.pipe(root, [fuel + Vector3(0.1, 0.3, 0), fuel + Vector3(0.45, 0.6, -0.2), c + Vector3(-0.2, 1.6, 0.1), c + Vector3(-0.35, 1.3, 0.45)], 0.04, "rubber")
	k.pennant(root, top + Vector3(0, 0.6, 0), 0.6)


## Fuel tanks are the same red everywhere so you can spot them.
static func paint_fuel(k: ModelKit) -> StandardMaterial3D:
	return k.paint(Color(0.72, 0.3, 0.18) if k.side == "player" else Color(0.4, 0.14, 0.1))
