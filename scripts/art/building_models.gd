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


## Rivet Turret, the line gun: a low, wide riveted pillbox with a domed head
## and twin belt-fed barrels. The squattest of the towers. Its head turns to
## face what it shoots.
static func _turret(root: Node3D, k: ModelKit, y: float) -> void:
	var casemate := k.drum(root, 0.9, 1.05, 0.55, Vector3(0, y + 0.275, 0), "accent", 8)
	casemate.rotation.y = PI / 8.0
	for h in [0.12, 0.45]:
		var band := k.drum(root, 0.93 - h * 0.25, 0.95 - h * 0.25, 0.06, Vector3(0, y + h, 0), "iron", 8)
		band.rotation.y = PI / 8.0
		k.rivets(root, 1.0 - h * 0.25, y + h + 0.02, 12)
	# Firing slits all round.
	for i in 4:
		var a := TAU * i / 4.0 + PI / 4.0
		var slit := k.box(root, Vector3(0.36, 0.07, 0.05), Vector3(sin(a) * 0.98, y + 0.32, cos(a) * 0.98), "rubber")
		slit.rotation.y = a
	k.ring(root, 0.66, 0.05, Vector3(0, y + 0.57, 0), "brass")
	var head := k.group(root, Vector3(0, y + 0.55, 0), "Head")
	k.dome(head, 0.62, Vector3(0, 0.0, -0.05), "steel", 0.55)
	k.box(head, Vector3(0.78, 0.3, 0.3), Vector3(0, 0.15, 0.5), "accent_dark")
	k.rivets(head, 0.5, 0.05, 10)
	for x in [-0.17, 0.17]:
		k.barrel(head, Vector3(x, 0.17, 0.55), Vector3(0, 0.02, 1.0), 1.05, 0.07)
	# Ammunition belt drum on the side, feeding both guns.
	var belt := k.drum(head, 0.2, 0.2, 0.2, Vector3(0.52, 0.18, 0.18), "brass", 12)
	belt.rotation.z = PI / 2.0
	k.pipe(head, [Vector3(0.45, 0.2, 0.3), Vector3(0.3, 0.2, 0.48)], 0.04, "brass")
	# Periscope and commander's hatch.
	k.rod(head, Vector3(-0.2, 0.25, -0.15), Vector3(-0.2, 0.55, -0.15), 0.04, "iron", 6)
	k.box(head, Vector3(0.1, 0.08, 0.14), Vector3(-0.2, 0.57, -0.11), "brass")
	k.hatch(head, Vector3(0.12, 0.3, -0.2), 0.16)
	k.pennant(root, Vector3(0.8, y + 0.55, -0.55), 0.8)


## Arc Coil, the crowd breaker: the tallest tower, a lattice tripod lifting a
## copper-wound insulator to a glowing discharge ball. Lightning leaps from
## the ball.
static func _coil(root: Node3D, k: ModelKit, y: float) -> void:
	var glow := k.paint(k.accent.lightened(0.25), 2.6)
	# Junction box and earth cables at the foot.
	k.drum(root, 0.42, 0.55, 0.3, Vector3(0, y + 0.15, 0), "iron", 10)
	k.ring(root, 0.45, 0.04, Vector3(0, y + 0.3, 0), "brass")
	# Tripod legs with cross braces.
	var feet: Array[Vector3] = []
	var tops: Array[Vector3] = []
	for i in 3:
		var a := TAU * i / 3.0 + PI / 6.0
		feet.append(Vector3(cos(a) * 0.85, y, sin(a) * 0.85))
		tops.append(Vector3(cos(a) * 0.2, y + 1.7, sin(a) * 0.2))
		k.rod(root, feet[i], tops[i], 0.05, "iron", 6)
		k.drum(root, 0.1, 0.12, 0.08, feet[i] + Vector3(0, 0.04, 0), "brass", 6)
	for i in 3:
		var j := (i + 1) % 3
		k.rod(root, feet[i].lerp(tops[i], 0.45), feet[j].lerp(tops[j], 0.45), 0.025, "iron", 6)
		k.rod(root, feet[i].lerp(tops[i], 0.15), feet[j].lerp(tops[j], 0.6), 0.02, "iron", 6)
	# Insulator column, wound in copper.
	k.drum(root, 0.12, 0.18, 2.6, Vector3(0, y + 1.5, 0), "ceramic", 10)
	for i in 4:
		k.ring(root, 0.22, 0.04, Vector3(0, y + 0.5 + i * 0.25, 0), "ceramic")
	for i in 6:
		k.ring(root, 0.36 - i * 0.025, 0.05, Vector3(0, y + 1.9 + i * 0.12, 0), "copper")
	# Discharge ring and ball.
	k.ring(root, 0.5, 0.11, Vector3(0, y + 2.85, 0), "brass")
	k.ball(root, 0.3, Vector3(0, y + 3.0, 0), glow)
	k.rod(root, Vector3(0, y + 3.25, 0), Vector3(0, y + 3.65, 0), 0.03, "copper", 6)
	k.ball(root, 0.07, Vector3(0, y + 3.68, 0), glow)
	for i in 3:
		var a := TAU * i / 3.0
		k.ball(root, 0.06, Vector3(cos(a) * 0.5, y + 2.85, sin(a) * 0.5), glow)
	k.pipe(root, [Vector3(0.4, y + 0.2, 0.1), Vector3(0.9, y + 0.1, 0.4), Vector3(1.0, y, 0.5)], 0.045, "rubber")


## Rally Horn, the morale tower: a great flared brass horn on a tall mast,
## blown by a bellows and air tank, flying the company pennant. No gun.
static func _horn(root: Node3D, k: ModelKit, y: float) -> void:
	var first := root.get_child_count()
	k.box(root, Vector3(0.75, 0.5, 0.9), Vector3(-0.45, y + 0.25, -0.15), "leather")
	for z in [-0.45, -0.15, 0.15]:
		k.box(root, Vector3(0.8, 0.54, 0.06), Vector3(-0.45, y + 0.26, z), "accent")
	k.tank(root, Vector3(0.5, y + 0.28, -0.6), 0.22, 0.5, Vector3.RIGHT, "copper")
	var mast_top := Vector3(0.2, y + 2.3, -0.1)
	k.drum(root, 0.22, 0.32, 0.3, Vector3(0.2, y + 0.15, -0.1), "iron", 8)
	k.rod(root, Vector3(0.2, y, -0.1), mast_top, 0.08, "iron")
	for side in [-1.0, 1.0]:
		k.rod(root, Vector3(0.2 + side * 0.6, y, -0.6), Vector3(0.2, y + 1.4, -0.1), 0.03, "iron", 6)
	k.pipe(root, [Vector3(-0.45, y + 0.5, -0.15), Vector3(-0.45, y + 1.0, -0.15), Vector3(0.12, y + 1.7, -0.15), mast_top + Vector3(0, -0.1, -0.3)], 0.06)
	# The great horn, flaring wide, with two smaller ones below.
	var mouth := mast_top + Vector3(0, 0.35, 1.25)
	k.cone(root, mouth, mast_top + Vector3(0, -0.1, -0.35), 0.85, 0.07, "brass", 16)
	# The dark throat, set back inside the bell.
	ModelKit.aim(k.drum(root, 0.38, 0.38, 0.02, mouth - Vector3(0, 0.35, 1.25).normalized() * 0.55, "rubber", 12), Vector3(0, 0.35, 1.25))
	ModelKit.aim(k.ring(root, 0.85, 0.05, mouth, "brass"), Vector3(0, 0.35, 1.25))
	for side in [-1.0, 1.0]:
		k.cone(root, mast_top + Vector3(side * 0.6, -0.45, 0.55), mast_top + Vector3(side * 0.1, -0.55, -0.1), 0.3, 0.04, "brass", 10)
	k.pennant(root, mast_top + Vector3(0, 0.05, -0.2), 0.9)
	k.lamp(root, Vector3(-0.45, y + 0.5, 0.25), 0.1, 0.08)
	# Turned so the horn calls out to the side: from the camera you see the
	# flare's long profile rather than a flat disc.
	var turn := Transform3D(Basis(Vector3.UP, PI * 0.4), Vector3.ZERO)
	for i in range(first, root.get_child_count()):
		var part := root.get_child(i) as Node3D
		part.transform = turn * part.transform


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


## Flak Battery, the swarm shredder: four sky guns pointing almost straight
## up from a sandbagged pit, with ready ammunition crates. Its head turns to
## face its target.
static func _flak(root: Node3D, k: ModelKit, y: float) -> void:
	var bags := k.paint(Color(0.62, 0.55, 0.4))
	# Two courses of sandbags round the pit, open at the back.
	for course in 2:
		for i in 11:
			var a := PI * 0.3 + (TAU - PI * 0.6) * (i + 0.5 * course) / 11.0
			var r := 0.98 - course * 0.04
			var bag := k.ball(root, 0.2, Vector3(sin(a) * r, y + 0.1 + course * 0.17, cos(a) * r), bags, 0.5)
			bag.rotation.y = a
			bag.scale.x *= 1.6
	k.drum(root, 0.36, 0.45, 0.3, Vector3(0, y + 0.15, 0), "steel", 10)
	k.ring(root, 0.42, 0.04, Vector3(0, y + 0.3, 0), "brass")
	var head := k.group(root, Vector3(0, y + 0.3, 0), "Head")
	k.box(head, Vector3(0.8, 0.22, 0.6), Vector3(0, 0.12, -0.05), "accent")
	k.rivets(head, 0.36, 0.2, 8)
	var up := Vector3(0, sin(deg_to_rad(70.0)), cos(deg_to_rad(70.0)))
	for x in [-0.15, 0.15]:
		for z in [-0.17, 0.08]:
			k.barrel(head, Vector3(x, 0.25, z), up, 1.4, 0.055)
	# Recoil housings, ring sight and the layer's seat.
	for side in [-1.0, 1.0]:
		k.box(head, Vector3(0.1, 0.45, 0.35), Vector3(side * 0.34, 0.4, 0.0), "accent_dark").rotation.x = -0.3
	k.rod(head, Vector3(-0.45, 0.25, 0.1), Vector3(-0.45, 0.85, 0.3), 0.02, "iron", 6)
	ModelKit.aim(k.ring(head, 0.14, 0.02, Vector3(-0.45, 0.88, 0.31), "brass"), up)
	k.box(head, Vector3(0.28, 0.08, 0.24), Vector3(0.0, 0.3, -0.45), "leather")
	# Ready ammunition in the open back of the pit.
	k.box(root, Vector3(0.42, 0.26, 0.3), Vector3(-0.4, y + 0.13, -0.85), "wood")
	k.box(root, Vector3(0.42, 0.26, 0.3), Vector3(0.12, y + 0.13, -0.92), "wood")
	for i in 3:
		k.drum(root, 0.05, 0.05, 0.26, Vector3(-0.55 + i * 0.15, y + 0.4, -0.85), "brass", 6)
	k.pennant(root, Vector3(0.62, y, -0.85), 1.1)


## Skyhook Gun, the ship anchor: a crane on a turntable whose long lattice
## boom carries the harpoon, with the cable run over the A-frame back to the
## winch and a counterweight. The tallest reach in the sky. The crane turns
## to face its target.
static func _skyhook(root: Node3D, k: ModelKit, y: float) -> void:
	var plinth := k.drum(root, 0.85, 1.0, 0.25, Vector3(0, y + 0.125, 0), "iron", 4)
	plinth.rotation.y = PI / 4.0
	k.rivets(root, 0.82, y + 0.2, 8)
	k.ring(root, 0.62, 0.05, Vector3(0, y + 0.27, 0), "brass")
	var head := k.group(root, Vector3(0, y + 0.27, 0), "Head")
	k.drum(head, 0.6, 0.62, 0.18, Vector3(0, 0.09, 0), "accent", 14)
	# Cab and counterweight at the back.
	k.box(head, Vector3(0.7, 0.45, 0.45), Vector3(0, 0.4, -0.55), "accent")
	k.box(head, Vector3(0.74, 0.06, 0.5), Vector3(0, 0.65, -0.55), "brass")
	k.box(head, Vector3(0.5, 0.3, 0.25), Vector3(0, 0.33, -0.9), "iron")
	# A-frame.
	var apex := Vector3(0, 1.6, -0.35)
	for side in [-1.0, 1.0]:
		k.rod(head, Vector3(side * 0.42, 0.18, -0.65), apex, 0.05, "iron", 6)
		k.rod(head, Vector3(side * 0.42, 0.18, 0.05), apex, 0.05, "iron", 6)
	k.ball(head, 0.09, apex, "brass")
	# Lattice boom from its pivot out and up.
	var dir := Vector3(0, sin(deg_to_rad(48.0)), cos(deg_to_rad(48.0)))
	var pivot := Vector3(0, 0.35, 0.1)
	var length := 2.4
	var tip := pivot + dir * length
	for side in [-1.0, 1.0]:
		k.rod(head, pivot + Vector3(side * 0.16, 0, 0), tip + Vector3(side * 0.06, 0, 0), 0.04, "accent_dark", 6)
	for i in 6:
		var t := (i + 0.5) / 6.0
		var w := lerpf(0.16, 0.06, t)
		k.rod(head, pivot + dir * length * t + Vector3(-w, 0, 0), pivot + dir * length * t + Vector3(w, 0, 0), 0.025, "brass", 6)
	k.rod(head, pivot + Vector3(-0.2, 0, 0), pivot + Vector3(0.2, 0, 0), 0.08, "brass", 8)
	# The harpoon at the boom's head: launcher sleeve, shaft and barbs.
	k.rod(head, tip - dir * 0.3, tip + dir * 0.15, 0.11, "steel", 10)
	k.rod(head, tip, tip + dir * 0.55, 0.035, "iron", 6)
	k.cone(head, tip + dir * 0.5, tip + dir * 0.85, 0.15, 0.0, "brass", 4)
	# Winch drum on the cab, cable over the apex to the boom's head.
	var spool := Vector3(0, 0.75, -0.55)
	k.rod(head, spool + Vector3(-0.26, 0, 0), spool + Vector3(0.26, 0, 0), 0.16, "rubber", 10)
	for side in [-1.0, 1.0]:
		k.rod(head, spool + Vector3(side * 0.26, 0, 0), spool + Vector3(side * 0.3, 0, 0), 0.22, "brass", 10)
	k.rod(head, spool + Vector3(0, 0.1, 0), apex, 0.02, "rubber", 4)
	k.rod(head, apex, tip, 0.02, "rubber", 4)
	k.lamp(head, Vector3(0.3, 0.68, -0.4), 0.15, 0.07)
	k.pennant(root, Vector3(-0.75, y, 0.6), 1.0)


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
