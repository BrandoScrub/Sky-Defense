## Headquarters models, built on the core tile's hex plinth from the shared
## ModelKit parts. Yours is a brass clock tower; each rival's shows what the
## corporation is about: Ironbell a blast furnace and bell, Vesper an
## aerodrome tower with a moored ship, Nimbus a storm dome with lightning
## rods, Aurum a stepped vault under a crystal spire. Every one has the same
## light defence gun and a beacon in its lamp colour. `y` is the plinth top.
class_name HqModels
extends RefCounted


## Wall paint per corporation ("" is yours).
const PAINT := {
	"": Color(0.56, 0.4, 0.22),
	"Ironbell": Color(0.36, 0.13, 0.1),
	"Vesper": Color(0.25, 0.33, 0.55),
	"Nimbus": Color(0.42, 0.5, 0.62),
	"Aurum": Color(0.34, 0.17, 0.13),
}


## `corp` is the rival corporation, or "" for the player's headquarters.
static func build(plinth: Node3D, corp: String, top: float) -> void:
	# Modelled at 1:1 on the plinth top, then drawn larger: a headquarters
	# should tower over ordinary buildings.
	var root := Node3D.new()
	root.name = "Headquarters"
	root.position.y = top
	root.scale = Vector3.ONE * 1.1
	plinth.add_child(root)
	var y := 0.0
	var k := ModelKit.shared(PAINT.get(corp, PAINT.Ironbell), "player" if corp == "" else "rival", corp)
	# Shared footing: trim ring, corner lamps and the defence gun.
	var trim := k.drum(root, 1.4, 1.4, 0.06, Vector3(0, y + 0.03, 0), "brass", 6)
	trim.rotation.y = PI / 6.0
	for i in 3:
		var a := TAU * i / 3.0 + PI / 2.0
		k.lamp(root, Vector3(cos(a) * 1.3, y, sin(a) * 1.3), 0.45, 0.09)
	var gun := k.group(root, Vector3(0.5, y, 1.2), "Gun")
	k.drum(gun, 0.25, 0.3, 0.3, Vector3(0, 0.15, 0), "steel", 8)
	k.barrel(gun, Vector3(0, 0.3, 0), Vector3(0, 0.25, 1.0), 0.75, 0.06)
	match corp:
		"":
			_company_house(root, k, y)
		"Vesper":
			_aerodrome(root, k, y)
		"Nimbus":
			_storm_station(root, k, y)
		"Aurum":
			_bastion(root, k, y)
		_:
			_foundry(root, k, y)


## Your headquarters: a hall with lit windows under a four-faced clock tower,
## brass dome, chimneys and the company beacon.
static func _company_house(root: Node3D, k: ModelKit, y: float) -> void:
	var hall := k.drum(root, 1.15, 1.3, 1.1, Vector3(0, y + 0.55, 0), "accent", 6)
	hall.rotation.y = PI / 6.0
	k.drum(root, 1.2, 1.2, 0.2, Vector3(0, y + 0.65, 0), "glass", 6).rotation.y = PI / 6.0
	k.drum(root, 1.25, 1.2, 0.1, Vector3(0, y + 1.13, 0), "brass", 6).rotation.y = PI / 6.0
	k.box(root, Vector3(0.9, 1.8, 0.9), Vector3(0, y + 2.0, 0), "accent")
	k.box(root, Vector3(1.0, 0.1, 1.0), Vector3(0, y + 2.9, 0), "brass")
	for i in 4:
		var n := Vector3(sin(i * PI / 2.0), 0, cos(i * PI / 2.0))
		var face := k.drum(root, 0.32, 0.32, 0.04, Vector3(0, y + 2.45, 0) + n * 0.46, "ceramic", 14)
		ModelKit.aim(face, n)
		ModelKit.aim(k.ring(root, 0.32, 0.03, Vector3(0, y + 2.45, 0) + n * 0.47, "brass"), n)
		k.box(root, Vector3(0.04, 0.24, 0.04), Vector3(0, y + 2.53, 0) + n * 0.49, "rubber")
		k.box(root, Vector3(0.3, 0.3, 0.04) if i % 2 == 0 else Vector3(0.04, 0.3, 0.3), Vector3(0, y + 1.6, 0) + n * 0.46, "glass")
	k.dome(root, 0.62, Vector3(0, y + 2.95, 0), "brass", 0.9)
	k.drum(root, 0.16, 0.2, 0.3, Vector3(0, y + 3.6, 0), "brass", 8)
	k.rod(root, Vector3(0, y + 3.7, 0), Vector3(0, y + 4.4, 0), 0.04, "iron", 6)
	k.ball(root, 0.24, Vector3(0, y + 4.5, 0), "lamp")
	for x in [-1.0, 1.0]:
		k.stack(root, Vector3(x * 0.8, y + 1.1, -0.45), 1.5, 0.15)
		k.pipe(root, [Vector3(x * 0.5, y + 1.6, 0.2), Vector3(x * 0.85, y + 1.6, 0.35), Vector3(x * 0.85, y + 1.15, 0.35)], 0.06)
	k.pennant(root, Vector3(0.38, y + 2.95, 0.38), 1.0)


## Ironbell: a banded blast furnace with a glowing mouth, three smokestacks
## and the great bell on a gantry.
static func _foundry(root: Node3D, k: ModelKit, y: float) -> void:
	var fire := k.paint(Color(1.0, 0.45, 0.15), 2.6)
	k.drum(root, 0.75, 1.15, 2.4, Vector3(0, y + 1.2, -0.1), "accent", 10)
	for h in [0.5, 1.2, 1.9]:
		k.ring(root, 1.12 - h * 0.165, 0.06, Vector3(0, y + h, -0.1), "brass")
	k.drum(root, 0.85, 0.75, 0.25, Vector3(0, y + 2.5, -0.1), "iron", 10)
	k.ball(root, 0.5, Vector3(0, y + 2.55, -0.1), fire, 0.5)
	k.box(root, Vector3(0.7, 0.5, 0.2), Vector3(0, y + 0.3, 0.95), "iron")
	k.box(root, Vector3(0.5, 0.3, 0.06), Vector3(0, y + 0.3, 1.06), fire)
	var heights := [3.6, 3.0, 2.4]
	for i in 3:
		var a := PI * 0.75 + i * PI * 0.5
		k.stack(root, Vector3(cos(a) * 1.05, y, sin(a) * 1.05 - 0.1), heights[i], 0.2)
	# The bell on its gantry.
	for x in [-0.45, 0.45]:
		k.rod(root, Vector3(x, y + 2.6, -0.1), Vector3(x, y + 3.9, -0.1), 0.06, "iron", 6)
	k.box(root, Vector3(1.1, 0.12, 0.14), Vector3(0, y + 3.9, -0.1), "iron")
	var bronze := k.paint(Color(0.78, 0.6, 0.25))
	k.drum(root, 0.16, 0.42, 0.55, Vector3(0, y + 3.5, -0.1), bronze, 12)
	k.ball(root, 0.09, Vector3(0, y + 3.2, -0.1), "iron")
	k.ball(root, 0.2, Vector3(0, y + 4.15, -0.1), "lamp")
	k.pipe(root, [Vector3(0.9, y + 0.6, 0.4), Vector3(1.25, y + 0.6, 0.5), Vector3(1.25, y, 0.5)], 0.09)


## Vesper: a slim control tower with a glazed cab and signal lamps, a
## hangar vault at its foot and a courier ship on the mooring arm.
static func _aerodrome(root: Node3D, k: ModelKit, y: float) -> void:
	k.rod(root, Vector3(-1.0, y + 0.1, -0.35), Vector3(1.0, y + 0.1, -0.35), 0.7, "accent_dark", 14)
	for x in [-1.0, 0.0, 1.0]:
		ModelKit.aim(k.ring(root, 0.7, 0.04, Vector3(x, y + 0.1, -0.35), "brass"), Vector3.RIGHT)
	k.drum(root, 0.42, 0.6, 3.0, Vector3(0, y + 1.5, 0.2), "accent", 10)
	for h in [1.0, 2.0]:
		k.ring(root, 0.57 - h * 0.06, 0.04, Vector3(0, y + h, 0.2), "brass")
	k.drum(root, 0.75, 0.55, 0.2, Vector3(0, y + 3.05, 0.2), "iron", 12)
	k.drum(root, 0.7, 0.7, 0.4, Vector3(0, y + 3.35, 0.2), "glass", 12)
	k.drum(root, 0.5, 0.85, 0.25, Vector3(0, y + 3.65, 0.2), "accent_dark", 12)
	for i in 4:
		var a := TAU * i / 4.0 + PI / 4.0
		k.ball(root, 0.09, Vector3(cos(a) * 0.82, y + 3.55, sin(a) * 0.82 + 0.2), "lamp")
	k.rod(root, Vector3(0, y + 3.75, 0.2), Vector3(0, y + 4.6, 0.2), 0.035, "iron", 6)
	k.ball(root, 0.18, Vector3(0, y + 4.7, 0.2), "lamp")
	# Mooring arm with a courier ship nosed up to it.
	k.rod(root, Vector3(0, y + 2.6, 0.2), Vector3(1.3, y + 2.75, 0.2), 0.05, "iron", 6)
	k.ring(root, 0.14, 0.03, Vector3(1.38, y + 2.75, 0.2), "brass")
	var ship := k.balloon(root, Vector3(2.15, y + 2.75, 0.2), 0.32, 1.4, "accent", 2)
	ship.rotation.y = PI / 2.0
	k.box(root, Vector3(0.6, 0.14, 0.2), Vector3(2.15, y + 2.36, 0.2), "iron")
	k.pennant(root, Vector3(-0.9, y + 0.75, -0.35), 1.0)


## Nimbus: a ribbed storm dome wound with copper, a spinning wind gauge on
## top and three lightning rods feeding it.
static func _storm_station(root: Node3D, k: ModelKit, y: float) -> void:
	var blue := k.paint(Color(0.42, 0.5, 0.62))
	k.drum(root, 1.1, 1.2, 0.8, Vector3(0, y + 0.4, 0), blue, 12)
	k.drum(root, 1.14, 1.14, 0.16, Vector3(0, y + 0.5, 0), "glass", 12)
	k.dome(root, 1.1, Vector3(0, y + 0.8, 0), blue, 0.9)
	for h in [0.85, 1.25, 1.6]:
		k.ring(root, 1.1 * sqrt(maxf(0.05, 1.0 - pow((h - 0.8) / 1.0, 2.0))), 0.05, Vector3(0, y + h, 0), "copper")
	k.drum(root, 0.25, 0.3, 0.3, Vector3(0, y + 1.85, 0), "brass", 8)
	k.rod(root, Vector3(0, y + 1.9, 0), Vector3(0, y + 3.2, 0), 0.04, "iron", 6)
	var gauge := k.propeller(root, Vector3(0, y + 3.2, 0), Vector3.UP, 0.55, 3, 1.2, "brass")
	gauge.name = "WindGauge"
	k.ball(root, 0.22, Vector3(0, y + 2.5, 0), "lamp")
	for i in 3:
		var a := TAU * i / 3.0 + PI / 6.0
		var foot := Vector3(cos(a) * 1.25, y, sin(a) * 1.25)
		k.rod(root, foot, foot + Vector3(0, 3.6 - i * 0.4, 0), 0.04, "copper", 6)
		for h in [0.8, 1.5]:
			k.ring(root, 0.1, 0.03, foot + Vector3(0, h, 0), "ceramic")
		k.ball(root, 0.11, foot + Vector3(0, 3.65 - i * 0.4, 0), "lamp")
		k.rod(root, foot + Vector3(0, 1.2, 0), Vector3(cos(a) * 0.75, y + 1.5, sin(a) * 0.75), 0.03, "rubber", 6)


## Aurum: a stepped, gilt-banded vault with corner gun towers and a great
## crystal spire.
static func _bastion(root: Node3D, k: ModelKit, y: float) -> void:
	var gold := k.paint(Color(0.9, 0.72, 0.28))
	var crystal := k.paint(Color(0.3, 0.95, 0.9), 2.0)
	var h := y
	for step in [[1.35, 0.8], [1.0, 0.7], [0.68, 0.6]]:
		k.drum(root, step[0] * 0.92, step[0], step[1], Vector3(0, h + step[1] / 2.0, 0), "accent", 6).rotation.y = PI / 6.0
		k.drum(root, step[0] * 0.95, step[0] * 0.95, 0.08, Vector3(0, h + step[1], 0), gold, 6).rotation.y = PI / 6.0
		h += step[1]
	k.dome(root, 0.5, Vector3(0, h, 0), gold, 0.8)
	k.drum(root, 0.0, 0.28, 1.5, Vector3(0, h + 1.05, 0), crystal, 4)
	for i in 3:
		var a := TAU * i / 3.0
		var shard := k.drum(root, 0.0, 0.14, 0.7, Vector3(cos(a) * 0.35, h + 0.6, sin(a) * 0.35), crystal, 4)
		shard.rotation = Vector3(sin(a) * 0.4, 0, -cos(a) * 0.4)
	for i in 3:
		var a := TAU * i / 3.0 - PI / 2.0
		var at := Vector3(cos(a) * 1.2, y, sin(a) * 1.2)
		k.drum(root, 0.22, 0.26, 1.3, at + Vector3(0, 0.65, 0), "accent_dark", 8)
		k.drum(root, 0.3, 0.24, 0.14, at + Vector3(0, 1.35, 0), gold, 8)
		k.barrel(root, at + Vector3(0, 1.5, 0), Vector3(cos(a), 0.3, sin(a)), 0.6, 0.05)
	k.box(root, Vector3(0.5, 0.6, 0.08), Vector3(0, y + 0.3, 1.2), "rubber")
	k.box(root, Vector3(0.6, 0.08, 0.1), Vector3(0, y + 0.62, 1.2), gold)
