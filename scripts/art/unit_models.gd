## The model for every unit: foot soldiers, the Commander, Ironbell's walker,
## every airship, the hangar drones and the ferry. All of them are assembled
## from the shared ModelKit parts, so they match the buildings.
##
## Troops share one body (boots, coat, belt, shoulders, head) and differ in
## the three things you can read from above: hat, backpack and weapon.
## Airships share one hull (gas bag, gondola, engine pods, tail fins) and
## differ in size, proportions and what is bolted on: bomb racks, gun
## sponsons, a crane, a troop deck. Front is +Z.
class_name UnitModels
extends RefCounted


## Builds the right model for a unit and returns its root node.
static func build(unit: Unit) -> Node3D:
	var root := Node3D.new()
	root.name = "Body"
	unit.add_child(root)
	var corp: String = unit.get_meta("corp", "")
	var k := ModelKit.shared(unit.body_color, unit.faction, corp)
	if unit.flying:
		var f := unit.footprint
		if unit.has_meta("airship"):
			match String(unit.get_meta("airship")):
				"gunship":
					_gunship(root, k, f)
				"carrier":
					_carrier(root, k, f)
				_:
					_bomber(root, k, f)
		elif unit.has_meta("ship"):
			match String(unit.get_meta("ship")):
				"interceptor":
					_interceptor(root, k, f)
				"gunboat":
					_gunboat(root, k, f)
				_:
					_tender(root, k, f, String(unit.get_meta("job", "")))
		elif unit.is_drone:
			_drone(root, k, f)
		else:
			_bomber(root, k, f)
		k.drop_shadow(unit, f * 1.4, unit.position.y)
	elif unit.unit_type == "walker":
		_walker(root, k)
	else:
		_soldier(root, k, "hero" if unit.is_hero else unit.unit_type)
		root.scale = Vector3.ONE * (1.35 if unit.is_hero else 1.0) * (unit.footprint / 0.6 if not unit.is_hero else 1.0)
	return root


# --- Troops --------------------------------------------------------------------

## A foot soldier about 1.65 tall. `kind` picks the hat, pack and weapon.
static func _soldier(root: Node3D, k: ModelKit, kind: String) -> void:
	var hero := kind == "hero"
	var bulky := kind == "shieldbearer"
	var w := 1.2 if bulky else 1.0
	# Boots and legs.
	for x in [-0.15, 0.15]:
		k.box(root, Vector3(0.2, 0.42, 0.24), Vector3(x * w, 0.3, 0), "leather")
		k.box(root, Vector3(0.22, 0.14, 0.34), Vector3(x * w, 0.07, 0.04), "rubber")
	# Coat, belt, shoulders, arms, head.
	k.drum(root, 0.27 * w, (0.46 if hero else 0.38) * w, 0.78, Vector3(0, 0.85, 0), "accent", 10)
	k.ring(root, 0.335 * w, 0.035, Vector3(0, 0.78, 0), "brass" if hero else "leather")
	k.box(root, Vector3(0.14, 0.1, 0.06), Vector3(0, 0.78, 0.36 * w), "brass")
	k.box(root, Vector3(0.78 * w, 0.2, 0.36), Vector3(0, 1.22, 0), "accent_dark")
	for side in [-1.0, 1.0]:
		k.ball(root, 0.14 if not hero else 0.17, Vector3(side * 0.4 * w, 1.27, 0), "brass")
		k.rod(root, Vector3(side * 0.4 * w, 1.2, 0), Vector3(side * 0.32 * w, 0.92, 0.3), 0.08, "accent", 6)
		k.ball(root, 0.08, Vector3(side * 0.32 * w, 0.9, 0.32), "leather")
	k.ball(root, 0.2, Vector3(0, 1.48, 0), "skin")
	match kind:
		"hero":
			_commander_kit(root, k)
		"shieldbearer":
			_shieldbearer_kit(root, k)
		"rifleman":
			_rifleman_kit(root, k)
		"sapper":
			_sapper_kit(root, k)
		"lancer":
			_lancer_kit(root, k)
		"medic":
			_medic_kit(root, k)
		_:
			_riveteer_kit(root, k)


## The standard round "kettle" helmet.
static func _helmet(root: Node3D, k: ModelKit, material: Variant = "brass") -> void:
	k.dome(root, 0.25, Vector3(0, 1.5, 0), material, 0.75)
	k.drum(root, 0.33, 0.33, 0.035, Vector3(0, 1.5, 0), material, 12)


## Riveteer: kettle helmet, air tank on the back, a stubby rivet gun on a hose.
static func _riveteer_kit(root: Node3D, k: ModelKit) -> void:
	_helmet(root, k)
	k.tank(root, Vector3(0, 1.0, -0.36), 0.14, 0.34, Vector3.UP, "copper")
	k.box(root, Vector3(0.13, 0.18, 0.4), Vector3(0.3, 0.92, 0.48), "iron")
	k.rod(root, Vector3(0.3, 0.96, 0.6), Vector3(0.3, 0.96, 0.95), 0.05, "steel", 6)
	k.rod(root, Vector3(0.3, 0.96, 0.88), Vector3(0.3, 0.96, 0.96), 0.07, "brass", 6)
	k.pipe(root, [Vector3(0.12, 1.15, -0.36), Vector3(0.45, 1.05, -0.1), Vector3(0.36, 0.9, 0.35)], 0.03, "rubber")


## Shieldbearer: visored helmet with a crest, a riveted tower shield, a baton.
static func _shieldbearer_kit(root: Node3D, k: ModelKit) -> void:
	k.dome(root, 0.26, Vector3(0, 1.48, 0), "steel", 0.85)
	k.box(root, Vector3(0.34, 0.12, 0.1), Vector3(0, 1.5, 0.2), "rubber")
	k.box(root, Vector3(0.06, 0.12, 0.5), Vector3(0, 1.72, 0), "brass")
	var shield := k.group(root, Vector3(0, 0.78, 0.6))
	k.box(shield, Vector3(1.05, 1.3, 0.09), Vector3.ZERO, "steel")
	for y in [-0.62, 0.62]:
		k.box(shield, Vector3(1.1, 0.09, 0.13), Vector3(0, y, 0), "brass")
	for x in [-0.52, 0.52]:
		k.box(shield, Vector3(0.07, 1.3, 0.13), Vector3(x, 0, 0), "brass")
	k.box(shield, Vector3(0.5, 0.08, 0.02), Vector3(0, 0.38, 0.05), "rubber")
	k.box(shield, Vector3(0.7, 0.3, 0.02), Vector3(0, -0.15, 0.05), "accent")
	k.ball(shield, 0.11, Vector3(0, -0.15, 0.07), "brass")
	k.rod(root, Vector3(0.5, 0.95, 0.1), Vector3(0.62, 1.35, 0.5), 0.045, "rubber", 6)
	k.box(root, Vector3(0.5, 0.4, 0.2), Vector3(0, 1.0, -0.36), "leather")


## Rifleman: slouch hat, bedroll, and a long bolt gun with a brass scope.
static func _rifleman_kit(root: Node3D, k: ModelKit) -> void:
	k.drum(root, 0.36, 0.36, 0.035, Vector3(0, 1.6, 0), "leather", 12)
	k.drum(root, 0.19, 0.22, 0.17, Vector3(0, 1.68, 0), "leather", 10)
	k.ring(root, 0.215, 0.02, Vector3(0, 1.63, 0), "brass")
	k.rod(root, Vector3(-0.3, 1.2, -0.3), Vector3(0.3, 1.2, -0.3), 0.12, "canvas", 8)
	k.box(root, Vector3(0.09, 0.14, 0.45), Vector3(0.3, 0.98, 0.12), "wood")
	k.rod(root, Vector3(0.3, 1.02, 0.3), Vector3(0.3, 1.06, 1.45), 0.035, "iron", 6)
	k.rod(root, Vector3(0.3, 1.11, 0.35), Vector3(0.3, 1.13, 0.8), 0.045, "brass", 6)
	k.rod(root, Vector3(0.3, 1.055, 1.38), Vector3(0.3, 1.06, 1.46), 0.05, "brass", 6)
	k.rod(root, Vector3(-0.25, 1.25, 0.2), Vector3(0.25, 0.75, 0.3), 0.04, "leather", 6)


## Sapper: lamp helmet, a toolbox of charges on the back, and a big wrench.
static func _sapper_kit(root: Node3D, k: ModelKit) -> void:
	_helmet(root, k, "copper")
	k.ball(root, 0.08, Vector3(0, 1.62, 0.24), "lamp")
	var red := k.paint(Color(0.62, 0.2, 0.14))
	k.box(root, Vector3(0.52, 0.42, 0.26), Vector3(0, 1.0, -0.38), red)
	k.box(root, Vector3(0.56, 0.06, 0.3), Vector3(0, 1.22, -0.38), "brass")
	for x in [-0.14, 0.0, 0.14]:
		k.drum(root, 0.05, 0.05, 0.3, Vector3(x, 1.38, -0.38), red, 6)
	k.box(root, Vector3(0.3, 0.26, 0.2), Vector3(-0.42, 0.62, 0.05), "leather")
	# The wrench: shaft and open jaw.
	k.rod(root, Vector3(0.32, 0.9, 0.25), Vector3(0.32, 1.25, 0.95), 0.045, "steel", 6)
	for dy in [-0.09, 0.09]:
		k.box(root, Vector3(0.07, 0.07, 0.22), Vector3(0.32, 1.3 + dy, 1.03), "steel")
	k.box(root, Vector3(0.08, 0.26, 0.08), Vector3(0.32, 1.28, 0.94), "steel")


## Lancer: finned helmet, a Hum capacitor on the back, cabled to an arc lance.
static func _lancer_kit(root: Node3D, k: ModelKit) -> void:
	k.dome(root, 0.25, Vector3(0, 1.5, 0), "steel", 0.85)
	k.box(root, Vector3(0.05, 0.2, 0.42), Vector3(0, 1.74, -0.04), "accent")
	k.drum(root, 0.2, 0.2, 0.5, Vector3(0, 1.05, -0.4), "copper", 10)
	for y in [0.9, 1.2]:
		k.ring(root, 0.2, 0.03, Vector3(0, y, -0.4), "brass")
	k.ball(root, 0.13, Vector3(0, 1.36, -0.4), "hum")
	k.pipe(root, [Vector3(0.18, 1.2, -0.4), Vector3(0.5, 1.1, -0.2), Vector3(0.34, 1.0, 0.2)], 0.035, "rubber")
	k.rod(root, Vector3(0.32, 0.98, -0.25), Vector3(0.32, 1.05, 1.4), 0.06, "iron", 8)
	for z in [0.3, 0.9]:
		k.rod(root, Vector3(0.32, 1.0 + z * 0.04, z), Vector3(0.32, 1.0 + z * 0.04, z + 0.1), 0.085, "brass", 8)
	for dx in [-0.07, 0.07]:
		k.rod(root, Vector3(0.32 + dx, 1.05, 1.38), Vector3(0.32 + dx * 0.5, 1.07, 1.72), 0.02, "copper", 6)
	k.ball(root, 0.1, Vector3(0.32, 1.065, 1.6), "hum")


## Medic: white cap and pack with a red cross on top, tonic tank and sprayer.
static func _medic_kit(root: Node3D, k: ModelKit) -> void:
	var red := k.paint(Color(0.85, 0.14, 0.12))
	k.drum(root, 0.24, 0.25, 0.14, Vector3(0, 1.66, 0), "ceramic", 10)
	k.box(root, Vector3(0.3, 0.03, 0.1), Vector3(0, 1.74, 0), red)
	k.box(root, Vector3(0.1, 0.03, 0.3), Vector3(0, 1.74, 0), red)
	k.box(root, Vector3(0.56, 0.5, 0.3), Vector3(0, 1.02, -0.4), "ceramic")
	k.box(root, Vector3(0.4, 0.03, 0.12), Vector3(0, 1.28, -0.4), red)
	k.box(root, Vector3(0.12, 0.03, 0.26), Vector3(0, 1.28, -0.4), red)
	k.box(root, Vector3(0.34, 0.1, 0.02), Vector3(0, 1.02, -0.56), red)
	k.box(root, Vector3(0.1, 0.34, 0.02), Vector3(0, 1.02, -0.56), red)
	k.drum(root, 0.1, 0.1, 0.4, Vector3(-0.4, 0.95, -0.3), k.paint(Color(0.4, 0.8, 0.55), 1.4), 8)
	k.pipe(root, [Vector3(-0.4, 1.15, -0.3), Vector3(-0.5, 1.2, 0.0), Vector3(-0.32, 0.95, 0.3)], 0.03, "rubber")
	k.rod(root, Vector3(-0.32, 0.92, 0.25), Vector3(-0.32, 1.0, 0.75), 0.035, "brass", 6)
	k.cone(root, Vector3(-0.32, 1.02, 0.86), Vector3(-0.32, 1.0, 0.75), 0.08, 0.03, "brass", 8)
	k.box(root, Vector3(0.26, 0.22, 0.14), Vector3(0.4, 0.66, 0.1), "ceramic")


## The Commander: top hat with goggles, epaulettes, a cape, sabre and pistol.
static func _commander_kit(root: Node3D, k: ModelKit) -> void:
	var black := k.paint(Color(0.1, 0.09, 0.1))
	k.drum(root, 0.36, 0.36, 0.04, Vector3(0, 1.62, 0), black, 14)
	k.drum(root, 0.23, 0.21, 0.36, Vector3(0, 1.8, 0), black, 12)
	k.ring(root, 0.225, 0.03, Vector3(0, 1.68, 0), "brass")
	for x in [-0.09, 0.09]:
		var lens := k.ring(root, 0.06, 0.02, Vector3(x, 1.74, 0.21), "brass")
		lens.rotation.x = PI / 2.0
	# Cape down the back, sash across the chest, company lamp.
	var cape := k.box(root, Vector3(0.7, 1.0, 0.06), Vector3(0, 0.8, -0.36), "accent_dark")
	cape.rotation.x = -0.18
	k.rod(root, Vector3(-0.3, 1.25, 0.22), Vector3(0.3, 0.8, 0.34), 0.045, k.paint(Color(0.6, 0.15, 0.12)), 6)
	k.ball(root, 0.045, Vector3(-0.12, 1.1, 0.33), "hum")
	# Sabre on the left hip, pistol in the right hand.
	k.rod(root, Vector3(-0.42, 0.85, 0.1), Vector3(-0.5, 0.3, -0.5), 0.03, "steel", 6)
	k.ball(root, 0.07, Vector3(-0.42, 0.87, 0.12), "brass")
	k.box(root, Vector3(0.08, 0.16, 0.12), Vector3(0.33, 0.86, 0.36), "wood")
	k.rod(root, Vector3(0.33, 0.95, 0.34), Vector3(0.33, 0.97, 0.78), 0.04, "brass", 6)


## Ironbell Walker: a riveted cab on two bent legs, boiler and smokestack on
## its back, a furnace glowing behind the front grille and a cannon arm.
static func _walker(root: Node3D, k: ModelKit) -> void:
	var fire := k.paint(Color(1.0, 0.45, 0.15), 2.5)
	for side in [-1.0, 1.0]:
		var hip := Vector3(side * 0.5, 1.25, -0.05)
		var knee := Vector3(side * 0.56, 0.72, 0.32)
		var ankle := Vector3(side * 0.56, 0.16, -0.05)
		k.ball(root, 0.16, hip, "iron")
		k.rod(root, hip, knee, 0.1, "steel", 8)
		k.ball(root, 0.14, knee, "brass")
		k.rod(root, knee, ankle, 0.08, "steel", 8)
		k.box(root, Vector3(0.32, 0.16, 0.62), Vector3(side * 0.56, 0.08, 0.06), "iron")
		k.box(root, Vector3(0.34, 0.05, 0.2), Vector3(side * 0.56, 0.18, 0.28), "brass")
	# The cab, sloped glacis and furnace grille.
	k.box(root, Vector3(1.0, 0.75, 1.05), Vector3(0, 1.55, 0), "accent")
	var glacis := k.box(root, Vector3(0.96, 0.5, 0.1), Vector3(0, 1.82, 0.5), "accent_dark")
	glacis.rotation.x = -0.5
	k.box(root, Vector3(1.04, 0.07, 1.09), Vector3(0, 1.2, 0), "brass")
	k.box(root, Vector3(0.56, 0.26, 0.04), Vector3(0, 1.42, 0.53), fire)
	k.vent(root, Vector3(0, 1.42, 0.55), Vector3(0, 0, 1), 0.6, 0.3)
	k.box(root, Vector3(0.5, 0.07, 0.04), Vector3(0, 1.78, 0.52), "lamp")
	for x in [-0.42, 0.42]:
		for z in [-0.42, 0.42]:
			k.ball(root, 0.055, Vector3(x, 1.94, z), "brass")
	# Boiler, smokestack and the company bell.
	k.tank(root, Vector3(0, 2.05, -0.2), 0.32, 0.6, Vector3(0, 0, 1), "accent_dark")
	k.stack(root, Vector3(-0.3, 2.1, -0.42), 0.75, 0.11)
	k.hatch(root, Vector3(0.22, 1.93, 0.22), 0.16)
	k.cone(root, Vector3(0.5, 1.98, -0.4), Vector3(0.5, 2.22, -0.4), 0.14, 0.05, k.paint(Color(0.75, 0.6, 0.25)), 8)
	# Cannon arm and a ram plate.
	k.box(root, Vector3(0.2, 0.3, 0.4), Vector3(0.62, 1.5, 0.15), "iron")
	k.barrel(root, Vector3(0.62, 1.5, 0.3), Vector3(0, 0, 1), 0.85, 0.08)
	k.box(root, Vector3(0.12, 0.5, 0.7), Vector3(-0.6, 1.45, 0.25), "steel")
	k.box(root, Vector3(0.14, 0.08, 0.7), Vector3(-0.6, 1.72, 0.25), "brass")


# --- Airships ------------------------------------------------------------------

## The parts every airship shares. `radius` and `length` size the gas bag
## (centred on the unit); the gondola hangs `drop` below it. Returns the
## gondola's centre.
static func _hull(root: Node3D, k: ModelKit, radius: float, length: float, gondola: Vector3, gondola_mat: Variant = "iron", hoops := 4) -> Vector3:
	k.balloon(root, Vector3.ZERO, radius, length, "accent", hoops)
	# A walkway along the top, so the ship reads as a ship from above.
	k.box(root, Vector3(radius * 0.12, radius * 0.08, length * 0.5), Vector3(0, radius * 0.99, 0), "brass")
	var at := Vector3(0, -radius - gondola.y * 0.62, 0)
	k.box(root, gondola, at, gondola_mat)
	k.box(root, Vector3(gondola.x * 1.04, gondola.y * 0.16, gondola.z * 1.02), at + Vector3(0, gondola.y * 0.5, 0), "brass")
	for side in [-1.0, 1.0]:
		k.box(root, Vector3(0.03, gondola.y * 0.28, gondola.z * 0.75), at + Vector3(side * gondola.x * 0.5, gondola.y * 0.08, 0), "glass")
		for z in [-0.3, 0.3]:
			k.rod(root, at + Vector3(side * gondola.x * 0.4, gondola.y * 0.5, z * gondola.z), Vector3(side * radius * 0.55, -radius * 0.78, z * gondola.z * 1.1), 0.03, "iron", 6)
	k.ball(root, radius * 0.1, at + Vector3(0, -gondola.y * 0.6, gondola.z * 0.4), "lamp")
	return at


## An engine pod on an outrigger with a spinning propeller behind it.
static func _engine(root: Node3D, k: ModelKit, from: Vector3, at: Vector3, size: float) -> void:
	k.rod(root, from, at, size * 0.12, "iron", 6)
	k.cone(root, at + Vector3(0, 0, size * 0.5), at + Vector3(0, 0, -size * 0.5), size * 0.3, size * 0.22, "brass", 10)
	k.rod(root, at + Vector3(0, 0, size * 0.5), at + Vector3(0, 0, size * 0.56), size * 0.25, "rubber", 10)
	k.propeller(root, at + Vector3(0, 0, -size * 0.58), Vector3(0, 0, -1), size * 0.75, 3, 0.3 if at.x >= 0.0 else -0.3)
	k.rod(root, at + Vector3(0, size * 0.25, -size * 0.1), at + Vector3(0, size * 0.42, -size * 0.45), size * 0.07, "copper", 6)


## Cross-shaped tail fins at the stern of the gas bag.
static func _fins(root: Node3D, k: ModelKit, radius: float, z: float, size: float, count := 4) -> void:
	for i in count:
		var a := TAU * i / count + (0.0 if count == 4 else PI / 2.0)
		var out := Vector3(cos(a), sin(a), 0)
		var fin := k.box(root, Vector3(size, 0.05, size * 0.9), out * (radius * 0.55 + size * 0.3) + Vector3(0, 0, z), "accent_dark" if i % 2 == 0 else "brass")
		fin.rotation.z = a
		fin.rotate_object_local(Vector3.UP, 0.0)


## Vesper Bomber: a long dark hull with bomb racks on outriggers either side.
static func _bomber(root: Node3D, k: ModelKit, f: float) -> void:
	var g := _hull(root, k, f, f * 4.4, Vector3(f * 0.7, f * 0.45, f * 1.9))
	_fins(root, k, f, -f * 1.75, f * 0.75)
	for side in [-1.0, 1.0]:
		_engine(root, k, g + Vector3(side * f * 0.3, 0, -f * 0.7), g + Vector3(side * f * 0.95, f * 0.25, -f * 0.75), f * 0.55)
		# Bomb rack: a beam with three bombs slung under it.
		var rack := g + Vector3(side * f * 0.75, -f * 0.1, f * 0.35)
		k.box(root, Vector3(f * 0.7, f * 0.07, f * 0.12), g + Vector3(side * f * 0.55, -f * 0.02, f * 0.35), "iron")
		k.box(root, Vector3(f * 0.1, f * 0.07, f * 1.1), rack + Vector3(0, f * 0.08, 0), "iron")
		for i in 3:
			var b := rack + Vector3(0, -f * 0.12, (i - 1) * f * 0.42)
			k.rod(root, b + Vector3(0, 0, -f * 0.16), b + Vector3(0, 0, f * 0.16), f * 0.11, "rubber", 8)
			k.ball(root, f * 0.11, b + Vector3(0, 0, f * 0.16), "brass")
	k.box(root, Vector3(f * 0.3, f * 0.06, f * 0.5), g + Vector3(0, -f * 0.25, 0), "lamp")


## Vesper Gunship: a slim fast hull with gun turrets on sponsons and a nose gun.
static func _gunship(root: Node3D, k: ModelKit, f: float) -> void:
	var g := _hull(root, k, f * 0.85, f * 4.6, Vector3(f * 0.6, f * 0.42, f * 1.6), "steel")
	_fins(root, k, f * 0.85, -f * 1.9, f * 0.8, 3)
	for side in [-1.0, 1.0]:
		_engine(root, k, g + Vector3(side * f * 0.25, 0, -f * 0.6), g + Vector3(side * f * 0.8, f * 0.3, -f * 0.9), f * 0.5)
		var turret := g + Vector3(side * f * 0.85, -f * 0.05, f * 0.45)
		k.box(root, Vector3(f * 0.7, f * 0.1, f * 0.2), g + Vector3(side * f * 0.55, 0, f * 0.45), "iron")
		k.ball(root, f * 0.24, turret, "steel")
		k.ring(root, f * 0.24, f * 0.03, turret, "brass")
		k.barrel(root, turret, Vector3(side * 0.15, -0.1, 1.0), f * 0.9, f * 0.055)
	k.barrel(root, g + Vector3(0, -f * 0.1, f * 0.8), Vector3(0, -0.15, 1.0), f * 0.8, f * 0.07)


## Ironbell Troop Carrier: a fat hull with side lift bags, an armoured
## gondola, a smokestack, drop lines and a ramp at the stern.
static func _carrier(root: Node3D, k: ModelKit, f: float) -> void:
	var g := _hull(root, k, f, f * 3.9, Vector3(f * 1.0, f * 0.5, f * 2.0), "iron", 5)
	_fins(root, k, f, -f * 1.55, f * 0.7)
	for side in [-1.0, 1.0]:
		k.balloon(root, Vector3(side * f * 1.05, -f * 0.45, 0), f * 0.38, f * 2.4, "canvas", 2)
		k.rod(root, Vector3(side * f * 0.8, -f * 0.3, 0), Vector3(side * f * 1.05, -f * 0.45, 0), f * 0.05, "iron", 6)
		for z in [-0.7, 0.75]:
			_engine(root, k, g + Vector3(side * f * 0.5, f * 0.1, z * f), g + Vector3(side * f * 0.85, -f * 0.1, z * f), f * 0.4)
		# Armour skirts and drop lines.
		k.box(root, Vector3(f * 0.06, f * 0.42, f * 1.7), g + Vector3(side * f * 0.55, -f * 0.12, 0), "brass")
		for z in [-0.5, 0.5]:
			k.rod(root, g + Vector3(side * f * 0.45, -f * 0.25, z * f), g + Vector3(side * f * 0.45, -f * 1.0, z * f), 0.02, "rubber", 4)
	var ramp := k.box(root, Vector3(f * 0.8, f * 0.05, f * 0.7), g + Vector3(0, -f * 0.4, -f * 1.25), "steel")
	ramp.rotation.x = -0.5
	k.stack(root, g + Vector3(f * 0.3, f * 0.2, -f * 0.9), f * 0.75, f * 0.1)
	k.box(root, Vector3(f * 0.5, f * 0.12, f * 0.04), g + Vector3(0, 0, f * 1.01), k.paint(Color(1.0, 0.45, 0.15), 2.5))


## Skyhawk Interceptor: a slim hull with stub wings, twin nose guns and a
## big pusher propeller.
static func _interceptor(root: Node3D, k: ModelKit, f: float) -> void:
	var g := _hull(root, k, f * 0.8, f * 4.6, Vector3(f * 0.5, f * 0.4, f * 1.5), "steel", 3)
	_fins(root, k, f * 0.8, -f * 1.9, f * 0.85, 3)
	for h in [0.0, 0.42]:
		k.box(root, Vector3(f * 3.2, f * 0.05, f * 0.6), g + Vector3(0, f * (h - 0.05), f * 0.15), "canvas")
	for side in [-1.0, 1.0]:
		k.rod(root, g + Vector3(side * f * 1.3, -f * 0.05, f * 0.15), g + Vector3(side * f * 1.3, f * 0.37, f * 0.15), f * 0.04, "brass", 6)
		k.barrel(root, g + Vector3(side * f * 0.3, -f * 0.05, f * 0.6), Vector3(0, 0, 1), f * 0.9, f * 0.05)
		k.box(root, Vector3(f * 0.5, f * 0.02, f * 0.5), g + Vector3(side * f * 1.2, f * 0.4, f * 0.15), "accent")
	k.cone(root, g + Vector3(0, 0, -f * 0.75), g + Vector3(0, 0, -f * 1.2), f * 0.22, f * 0.1, "brass", 8)
	k.propeller(root, g + Vector3(0, 0, -f * 1.25), Vector3(0, 0, -1), f * 0.85, 4, 0.25)


## Thunder Gunboat: a stout hull, an armoured gondola with a belly cannon
## and broadside guns.
static func _gunboat(root: Node3D, k: ModelKit, f: float) -> void:
	var g := _hull(root, k, f, f * 3.7, Vector3(f * 0.9, f * 0.5, f * 1.8), "steel")
	_fins(root, k, f, -f * 1.5, f * 0.7)
	for side in [-1.0, 1.0]:
		_engine(root, k, g + Vector3(side * f * 0.4, f * 0.1, -f * 0.75), g + Vector3(side * f * 0.95, f * 0.25, -f * 0.85), f * 0.5)
		k.box(root, Vector3(f * 0.07, f * 0.4, f * 1.5), g + Vector3(side * f * 0.5, -f * 0.1, 0), "accent_dark")
		for z in [-0.1, 0.45]:
			k.barrel(root, g + Vector3(side * f * 0.45, -f * 0.05, z * f), Vector3(side, -0.25, 0.25), f * 0.6, f * 0.06)
	# Belly turret with a heavy cannon aimed down and ahead.
	k.ball(root, f * 0.3, g + Vector3(0, -f * 0.3, f * 0.35), "iron")
	k.ring(root, f * 0.3, f * 0.035, g + Vector3(0, -f * 0.27, f * 0.35), "brass")
	k.barrel(root, g + Vector3(0, -f * 0.35, f * 0.4), Vector3(0, -0.45, 1.0), f * 1.2, f * 0.09)


## Tender: a canvas hull over a wooden cargo gondola. The job decides what is
## bolted on, and what is painted on the roof so you can tell from above:
## repair = crane and a green cross, scout = lamp and lookout, troops = an
## open deck with benches and chevrons.
static func _tender(root: Node3D, k: ModelKit, f: float, job: String) -> void:
	var g := _hull(root, k, f, f * 3.8, Vector3(f * 0.85, f * 0.45, f * 1.7), "wood")
	_fins(root, k, f, -f * 1.55, f * 0.7)
	for side in [-1.0, 1.0]:
		_engine(root, k, g + Vector3(side * f * 0.4, f * 0.1, -f * 0.7), g + Vector3(side * f * 0.9, f * 0.2, -f * 0.8), f * 0.45)
	var roof := Vector3(0, f * 1.0, f * 0.2)
	match job:
		"repair":
			var green := k.paint(Color(0.35, 0.8, 0.5), 0.6)
			k.box(root, Vector3(f * 0.9, f * 0.06, f * 0.26), roof, green)
			k.box(root, Vector3(f * 0.26, f * 0.06, f * 0.9), roof, green)
			# Crane boom over the bow, with a hook.
			var tip := g + Vector3(0, f * 0.1, f * 1.7)
			k.rod(root, g + Vector3(0, f * 0.3, f * 0.6), tip, f * 0.05, "brass", 6)
			k.rod(root, tip, tip + Vector3(0, -f * 0.5, 0), 0.02, "rubber", 4)
			k.ring(root, f * 0.08, f * 0.02, tip + Vector3(0, -f * 0.55, 0), "steel").rotation.x = PI / 2.0
			for side in [-1.0, 1.0]:
				k.box(root, Vector3(f * 0.2, f * 0.2, f * 0.3), g + Vector3(side * f * 0.3, -f * 0.3, -f * 0.3), "accent_dark")
		"scout":
			# Lookout basket on the roof, long aerial, big searchlight.
			k.drum(root, f * 0.26, f * 0.2, f * 0.22, roof + Vector3(0, f * 0.12, 0), "wood", 8)
			k.ring(root, f * 0.26, f * 0.03, roof + Vector3(0, f * 0.24, 0), "brass")
			k.rod(root, roof + Vector3(0, 0, -f * 0.9), roof + Vector3(0, f * 0.9, -f * 1.1), 0.02, "iron", 4)
			k.ball(root, f * 0.07, roof + Vector3(0, f * 0.92, -f * 1.1), "hum")
			k.cone(root, g + Vector3(0, -f * 0.1, f * 1.2), g + Vector3(0, -f * 0.05, f * 0.85), f * 0.24, f * 0.1, "brass", 10)
			k.ball(root, f * 0.17, g + Vector3(0, -f * 0.1, f * 1.15), "hum")
		_:
			# Troop deck: benches, rails, boarding ladders and roof chevrons.
			for i in 3:
				for side in [-1.0, 1.0]:
					var bar := k.box(root, Vector3(f * 0.5, f * 0.06, f * 0.12), roof + Vector3(side * f * 0.2, -f * 0.03, (i - 1) * f * 0.5), "brass")
					bar.rotation.y = side * 0.6
			for side in [-1.0, 1.0]:
				k.rod(root, g + Vector3(side * f * 0.48, f * 0.45, -f * 0.8), g + Vector3(side * f * 0.48, f * 0.45, f * 0.8), 0.025, "brass", 4)
				k.box(root, Vector3(f * 0.04, f * 0.9, f * 0.3), g + Vector3(side * f * 0.5, -f * 0.6, f * 0.2), "leather")
			k.box(root, Vector3(f * 0.6, f * 0.08, f * 1.2), g + Vector3(0, f * 0.3, 0), "leather")


## Defense Drone: no gas bag. A brass body between two shrouded rotors, with
## a lamp eye, a tail fin and a small gun slung under it.
static func _drone(root: Node3D, k: ModelKit, f: float) -> void:
	k.ball(root, f * 0.5, Vector3.ZERO, "brass", 0.8)
	k.ring(root, f * 0.5, f * 0.05, Vector3.ZERO, "accent_dark")
	k.ball(root, f * 0.2, Vector3(0, 0, f * 0.42), "lamp")
	for side in [-1.0, 1.0]:
		var at := Vector3(side * f * 1.05, f * 0.1, 0)
		k.rod(root, Vector3(side * f * 0.4, 0, 0), at, f * 0.07, "iron", 6)
		k.ring(root, f * 0.55, f * 0.06, at, "accent")
		k.propeller(root, at, Vector3.UP, f * 0.5, 3, 0.15 * side)
	k.rod(root, Vector3(0, 0, -f * 0.4), Vector3(0, f * 0.1, -f * 1.2), f * 0.06, "iron", 6)
	k.box(root, Vector3(f * 0.05, f * 0.5, f * 0.4), Vector3(0, f * 0.3, -f * 1.15), "accent")
	k.barrel(root, Vector3(0, -f * 0.4, 0), Vector3(0, -0.1, 1.0), f * 1.0, f * 0.07)
	k.rod(root, Vector3(0, -f * 0.1, 0), Vector3(0, -f * 0.45, 0), f * 0.1, "iron", 6)


## The ferry: a wide wooden deck boat under a canvas gas bag, with rails,
## bow and stern lamps and a stern propeller. Passengers stand on the deck
## (FerrySystem puts them 1.4 below the ship's origin).
static func ferry(color := Color(0.2, 0.75, 0.7)) -> Node3D:
	var ship := Node3D.new()
	var k := ModelKit.shared(color, "player")
	k.balloon(ship, Vector3(0, 1.3, 0), 1.15, 4.8, "canvas", 4)
	var stripe := k.ring(ship, 1.17, 0.09, Vector3(0, 1.3, 0), "accent")
	stripe.rotation.x = PI / 2.0
	k.box(ship, Vector3(0.14, 0.09, 2.4), Vector3(0, 2.44, 0), "brass")
	# Hull: a flat deck with a raised bow and gunwales.
	k.box(ship, Vector3(2.0, 0.4, 2.9), Vector3(0, -1.65, 0), "wood")
	k.box(ship, Vector3(2.1, 0.08, 3.0), Vector3(0, -1.42, 0), "brass")
	var bow := k.box(ship, Vector3(1.45, 0.4, 1.45), Vector3(0, -1.65, 1.45), "wood")
	bow.rotation.y = PI / 4.0
	for side in [-1.0, 1.0]:
		k.rod(ship, Vector3(side * 1.0, -1.0, -1.4), Vector3(side * 1.0, -1.0, 1.4), 0.035, "brass", 6)
		k.box(ship, Vector3(0.06, 0.22, 2.8), Vector3(side * 1.0, -1.3, 0), "accent")
		for z in [-1.4, -0.47, 0.47, 1.4]:
			k.rod(ship, Vector3(side * 1.0, -1.45, z), Vector3(side * 1.0, -1.0, z), 0.03, "brass", 6)
		for z in [-1.1, 1.1]:
			k.rod(ship, Vector3(side * 0.95, -1.0, z), Vector3(side * 0.7, 0.45, z * 1.1), 0.03, "rubber", 6)
	k.lamp(ship, Vector3(0, -1.45, 2.3), 0.5, 0.12)
	k.lamp(ship, Vector3(0, -1.45, -1.4), 0.7, 0.1)
	k.cone(ship, Vector3(0, -1.6, -1.45), Vector3(0, -1.6, -1.9), 0.25, 0.1, "brass", 8)
	k.propeller(ship, Vector3(0, -1.6, -1.95), Vector3(0, 0, -1), 0.75, 3, 0.4)
	return ship
