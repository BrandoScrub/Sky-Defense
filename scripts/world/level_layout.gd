## Builds the layout of a sky region, in hex coordinates, from a seed.
##
## Map rules (from the design brief):
## - Your Hub sits in the middle.
## - 2 to 4 rival corporations take part (see `rivals` in generate()). Each
##   rival headquarters sits in its own compass direction from the Hub, out
##   of the 8 (N, NE, E, SE, S, SW, W, NW), at least 90 degrees apart.
## - Between the Hub and each rival headquarters there's a chain of 4 to 9
##   platforms joined by walkways, with a few side platforms branching off.
## - Near the Hub: the Foundry (scrap), the Generator Rig (power socket) and
##   the Crystal Spire beyond the Foundry, each off in a direction of its own.
## - A storm cloud hangs beside the middle of each rival's chain, with
##   harvester anchors on the platforms around it.
##
## The result is a Dictionary with these keys, which SkyRegion reads:
##   platforms: [{name, kind, corp?, center, radius, capacity, features,
##     style, shape}]
##     `style` is the island type, which sets its outline: "city" (the Hub and
##     rival HQs: full hexagons), "turbine" (a hub with pinwheel blades),
##     "crystal" (a long jagged shard) or "rock" (a lumpy natural blob).
##     Crystal islands also have a `variant`: "grassy" or "overcharged".
##     `shape` is the island's hexes as offsets from `center`, all within
##     `radius` steps, so `radius` is still the island's outer bound.
##     `kind` is "hub", "neutral" or "rival". Features are [type, where]:
##     `where` is an offset from the centre (Vector2i), or the name of a
##     platform or cloud to put it on the rim facing that thing.
##   walkways: [[platform, platform]]
##   clouds: [{name, center, radius}]
##   air_lanes: [[from platform, to platform]]
##   directions: {corp: compass name}, e.g. {"Ironbell": "North", ...}
##   paths: {corp: [platform names from the Hub to that rival's HQ]}
##   seed: the seed used
class_name LevelLayout
extends RefCounted

## Centre-to-corner size of one hex tile, in world units.
const TILE_SIZE := 2.0
## Platforms between the Hub and each rival headquarters.
const MIN_BETWEEN := 4
const MAX_BETWEEN := 9
## Empty sky tiles kept between neighbouring platforms (at least).
const MIN_GAP := 2
## Longest planned walkway, in tiles (what the player can build in one go).
const MAX_SPAN := 8

## Rivals come from RivalCatalog.layout_rivals(): each {corp, hq, first},
## where first is the platform out from the Hub on its chain. A default map
## has two (SkyRegion.rival_count picks 2 to 4).

const COMPASS := ["East", "Northeast", "North", "Northwest", "West", "Southwest", "South", "Southeast"]
const CAPACITY := {1: 10, 2: 20, 3: 40}
## Original placeholder names for the platforms along the chains.
const NAMES := [
	"Gantry", "Bellows", "Cog Reach", "Lantern Deck", "Rivet Row", "Steamworks",
	"Copper Ring", "Gale Point", "Anchor Yard", "Spindle", "Furnace Rise",
	"Weather Vane", "Boiler Bay", "Pinion", "Signal Tower", "Brass Landing",
	"Kettle Drop", "Gearhouse", "Updraft", "Ballast Isle", "Chimney Stack",
	"Piston Ward", "Smokestack Quay", "Valve Court", "Tin Harbour", "Dynamo Ridge",
]


## Unit vector on the XZ plane for compass index 0..7 (0 = east, 2 = north).
## North is -Z, the top of the screen with the default camera.
static func compass_vector(index: int) -> Vector3:
	var angle := index * PI / 4.0
	return Vector3(cos(angle), 0.0, -sin(angle))


## Steps between two compass indices, 0..4.
static func compass_gap(a: int, b: int) -> int:
	var d := absi(a - b) % 8
	return mini(d, 8 - d)


## Generates a layout for 2 to 4 rivals. The same seed and rivals always
## give the same map.
static func generate(map_seed: int, rivals: Array = []) -> Dictionary:
	if rivals.is_empty():
		rivals = RivalCatalog.layout_rivals(2)
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed
	for attempt in 300:
		var layout := _attempt(rng, rivals)
		if not layout.is_empty():
			layout.seed = map_seed
			return layout
	push_error("LevelLayout: no valid map for seed %d" % map_seed)
	return {}


static func _attempt(rng: RandomNumberGenerator, rivals: Array) -> Dictionary:
	var b := _Builder.new(rng)
	b.add("Hub", "hub", Vector3.ZERO, 3, [
		["core", Vector2i(0, 0)],
		["generator_socket", Vector2i(-2, 1)],
		["generator_socket", Vector2i(2, -1)],
	])

	# Rival directions: all different, and at least 90 degrees apart.
	var taken: Array[int] = []
	var directions := {}
	for rival in rivals:
		var choices := []
		for d in 8:
			if taken.all(func(t): return compass_gap(d, t) >= 2):
				choices.append(d)
		if choices.is_empty():
			return {}
		var dir: int = choices[rng.randi_range(0, choices.size() - 1)]
		taken.append(dir)
		directions[rival.corp] = COMPASS[dir]
		if not b.chain(rival.corp, dir, rng.randi_range(MIN_BETWEEN, MAX_BETWEEN), rival.first,
				{"name": rival.hq, "corp": rival.corp}):
			return {}

	# Home platforms in directions of their own, away from the rivals.
	var nearest_rival := func(d: int) -> int:
		return taken.map(func(t): return compass_gap(d, t)).min()
	var free := []
	for d in 8:
		if nearest_rival.call(d) >= 1:
			free.append(d)
	free.sort_custom(func(x, y): return nearest_rival.call(x) > nearest_rival.call(y))
	if free.size() < 2:
		return {}
	var foundry_dir: int = free[0]
	var rig_dir: int = free[1]
	if not b.spur("Foundry", "Hub", compass_vector(foundry_dir), 2, [["scrap_heap", Vector2i(-1, 0)], ["scrap_heap", Vector2i(0, 1)]]):
		return {}
	if not b.spur("Generator Rig", "Hub", compass_vector(rig_dir), 1, [["generator_socket", Vector2i(0, 0)]]):
		return {}
	# The Crystal Spire hangs beyond the Foundry, a walkway further out.
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var spire_dir := compass_vector(foundry_dir).rotated(Vector3.UP, side * PI / 3.0)
	if not b.place_near("Crystal Spire", "Foundry", spire_dir, 2, 4, [
			["crystal_seam", Vector2i(0, 0)], ["crystal_seam", Vector2i(-1, -1)]]):
		return {}
	b.walkways.append(["Foundry", "Crystal Spire"])

	# Branches: one or two side platforms off each chain.
	for corp in b.paths:
		var path: Array = b.paths[corp]
		for i in rng.randi_range(1, 2):
			var stem: String = path[rng.randi_range(1, path.size() - 2)]
			var out := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
			b.spur(b.next_name(), stem, out, 1, [["scrap_heap" if rng.randf() < 0.5 else "generator_socket", Vector2i(0, 0)]])

	# A storm cloud beside the middle of each chain.
	var first := true
	for corp in b.paths:
		# The Hub gets an anchor for the first rival's storm.
		if not b.storm(corp, first):
			return {}
		first = false
	if not b.walkways_clear():
		return {}
	b.give_shapes()
	if not b.spans_short():
		return {}

	for rival in rivals:
		if RivalCatalog.get_data(rival.corp).get("air_lanes", false):
			b.air_lanes.append([rival.hq, "Hub"])
			b.air_lanes.append([rival.hq, "Generator Rig"])
	return {
		"platforms": b.platforms, "walkways": b.walkways,
		"clouds": b.clouds, "air_lanes": b.air_lanes, "paths": b.paths,
		"directions": directions,
	}


## Places platforms and checks they keep clear of each other.
class _Builder:
	var rng: RandomNumberGenerator
	var platforms: Array = []
	var walkways: Array = []
	var clouds: Array = []
	var air_lanes: Array = []
	var paths := {}
	var _names: Array = []
	var _by_name := {}

	func _init(r: RandomNumberGenerator) -> void:
		rng = r
		_names = LevelLayout.NAMES.duplicate()
		for i in range(_names.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var t = _names[i]
			_names[i] = _names[j]
			_names[j] = t

	func next_name() -> String:
		return _names.pop_back() if not _names.is_empty() else "Platform %d" % platforms.size()

	func hex_of(world: Vector3) -> Vector2i:
		return HexGrid.from_world(world, LevelLayout.TILE_SIZE)

	func world_of(hex: Vector2i) -> Vector3:
		return HexGrid.to_world(hex, LevelLayout.TILE_SIZE)

	## World distance between the centres of two platforms `gap` tiles apart.
	func spacing(r1: int, r2: int, gap: int) -> float:
		return (r1 + r2 + 1 + gap) * LevelLayout.TILE_SIZE * HexGrid.SQRT3

	func fits(center: Vector2i, radius: int) -> bool:
		for p in platforms:
			if HexGrid.distance(center, p.center) < p.radius + radius + 1 + LevelLayout.MIN_GAP:
				return false
		return true

	func add(platform_name: String, kind: String, world: Vector3, radius: int, features: Array, corp := "") -> bool:
		var center := hex_of(world)
		if not fits(center, radius):
			return false
		var p := {"name": platform_name, "kind": kind, "center": center, "radius": radius,
			"capacity": LevelLayout.CAPACITY[radius], "features": features}
		if corp != "":
			p.corp = corp
		platforms.append(p)
		_by_name[platform_name] = p
		return true

	func feature(platform_name: String, f: Array) -> void:
		_by_name[platform_name].features.append(f)

	## A chain of `between` platforms from the Hub toward a compass direction,
	## ending at a rival headquarters.
	func chain(corp: String, dir_index: int, between: int, first_name: String, hq: Dictionary) -> bool:
		var dir := LevelLayout.compass_vector(dir_index)
		var perp := Vector3(-dir.z, 0, dir.x)
		var prev: Dictionary = _by_name["Hub"]
		var along := 0.0
		var path := ["Hub"]
		for i in between + 1:
			var is_hq := i == between
			var radius := 3 if is_hq else (3 if rng.randf() < 0.1 else rng.randi_range(1, 2))
			# Uneven gaps and a wandering line, so islands don't sit in a row.
			along += spacing(prev.radius, radius, rng.randi_range(LevelLayout.MIN_GAP, LevelLayout.MIN_GAP + 4))
			var lateral := 0.0 if is_hq else rng.randf_range(-0.45, 0.45) * along / (i + 1)
			var pos := dir * along + perp * lateral
			var platform_name: String = hq.name if is_hq else (first_name if i == 0 else next_name())
			var features: Array = []
			if is_hq:
				features = [["rival_core", Vector2i(0, 0)]]
				features.append(["spawn", prev.name])
			else:
				var roll := rng.randf()
				if roll < 0.3:
					features.append(["scrap_heap", Vector2i(0, 0)])
				elif roll < 0.55:
					features.append(["generator_socket", Vector2i(0, 0)])
				elif roll < 0.67:
					features.append(["crystal_seam", Vector2i(0, 0)])
			if not add(platform_name, "rival" if is_hq else "neutral", pos, radius, features, hq.corp if is_hq else ""):
				return false
			walkways.append([prev.name, platform_name])
			path.append(platform_name)
			prev = _by_name[platform_name]
		paths[corp] = path
		return true

	## A platform hanging off another one, joined by a walkway.
	func spur(platform_name: String, stem: String, dir: Vector3, radius: int, features: Array) -> bool:
		if not place_near(platform_name, stem, dir, radius, rng.randi_range(LevelLayout.MIN_GAP, LevelLayout.MIN_GAP + 4), features):
			return false
		walkways.append([stem, platform_name])
		return true

	func place_near(platform_name: String, stem: String, dir: Vector3, radius: int, gap: int, features: Array) -> bool:
		var s: Dictionary = _by_name[stem]
		var pos := world_of(s.center) + dir.normalized() * spacing(s.radius, radius, gap)
		return add(platform_name, "neutral", pos, radius, features)

	## A storm cloud beside the middle of a chain, with harvester anchors on
	## the platforms either side of it (and on the Hub if it's close).
	func storm(corp: String, hub_anchor := false) -> bool:
		var path: Array = paths[corp]
		var k := clampi(path.size() / 2 - 1, 1, path.size() - 2)
		var mid: Dictionary = _by_name[path[k]]
		var nxt: Dictionary = _by_name[path[k + 1]]
		var a := world_of(mid.center)
		var b := world_of(nxt.center)
		var dir := (b - a).normalized()
		var perp := Vector3(-dir.z, 0, dir.x) * (1.0 if rng.randf() < 0.5 else -1.0)
		var center_world := (a + b) / 2.0 + perp * (LevelLayout.TILE_SIZE * HexGrid.SQRT3 * 4.0)
		var compass_name: String = LevelLayout.COMPASS[_compass_index(center_world)]
		var cloud_name := "%s Storm" % compass_name
		for c in clouds:
			if c.name == cloud_name:
				cloud_name = "%s Storm" % corp
		clouds.append({"name": cloud_name, "center": hex_of(center_world), "radius": 1, "corp": corp})
		feature(mid.name, ["harvester_anchor", cloud_name])
		feature(nxt.name, ["harvester_anchor", cloud_name])
		if hub_anchor:
			feature("Hub", ["harvester_anchor", cloud_name])
		return true

	func _compass_index(world: Vector3) -> int:
		var angle := atan2(-world.z, world.x)
		return posmod(roundi(angle / (PI / 4.0)), 8)

	## Gives every platform its island type and outline.
	func give_shapes() -> void:
		for p in platforms:
			p.style = style_for(p)
			if p.style == "crystal":
				# Grassy: ground the crystals lifted into the sky. Overcharged:
				# crackling with stored storm power.
				p.variant = "grassy" if rng.randf() < 0.5 else "overcharged"
			var shape: Dictionary = {}
			match p.style:
				"turbine":
					shape = turbine_shape(p.radius)
				"crystal":
					shape = crystal_shape(p.radius)
				"rock":
					shape = rock_shape(p.radius)
				_:
					for h in HexGrid.disk(Vector2i.ZERO, p.radius):
						shape[h] = true
			# Fixed features always sit on the island, joined to its middle.
			for f in p.features:
				if f[1] is Vector2i:
					for h in HexGrid.line(Vector2i.ZERO, f[1]):
						shape[h] = true
			var offsets: Array[Vector2i] = []
			offsets.assign(shape.keys())
			p.shape = offsets
			if p.style != "city":
				# Weight capacity follows the island's real size.
				p.capacity = maxi(5, roundi(offsets.size() * 1.4 / 5.0) * 5)

	func style_for(p: Dictionary) -> String:
		if p.kind != "neutral":
			return "city"
		for f in p.features:
			if f[0] == "crystal_seam":
				return "crystal"
		for f in p.features:
			if f[0] == "generator_socket":
				return "turbine"
		return "rock"

	## A round hub with three blades bent the same way, like a turbine.
	func turbine_shape(radius: int) -> Dictionary:
		var shape := {}
		for h in HexGrid.disk(Vector2i.ZERO, maxi(radius - 1, 1) if radius > 1 else radius):
			shape[h] = true
		if radius < 2:
			return shape
		var first := rng.randi_range(0, 1)
		for k in 3:
			var d: int = first + k * 2
			var tip: Vector2i = HexGrid.DIRECTIONS[d] * radius
			shape[tip] = true
			# Bend each blade toward the next direction round.
			shape[tip + HexGrid.DIRECTIONS[(d + 2) % 6]] = true
		return shape

	## A long jagged shard along one axis, with spikes off its sides.
	func crystal_shape(radius: int) -> Dictionary:
		var shape := {Vector2i.ZERO: true}
		var axis: Vector2i = HexGrid.DIRECTIONS[rng.randi_range(0, 2)]
		for i in range(-radius, radius + 1):
			var h: Vector2i = axis * i
			shape[h] = true
			if absi(i) < radius and rng.randf() < 0.55:
				var side: Vector2i = HexGrid.DIRECTIONS[rng.randi_range(0, 5)]
				if HexGrid.distance(Vector2i.ZERO, h + side) <= radius:
					shape[h + side] = true
		return shape

	## A lumpy natural rock: grows outward from the middle at random until it
	## covers most of its bounds.
	func rock_shape(radius: int) -> Dictionary:
		var shape := {Vector2i.ZERO: true}
		var target := roundi(HexGrid.disk(Vector2i.ZERO, radius).size() * rng.randf_range(0.55, 0.8))
		var guard := 0
		while shape.size() < target and guard < 500:
			guard += 1
			var keys := shape.keys()
			var from: Vector2i = keys[rng.randi_range(0, keys.size() - 1)]
			var h: Vector2i = from + HexGrid.DIRECTIONS[rng.randi_range(0, 5)]
			if HexGrid.distance(Vector2i.ZERO, h) <= radius:
				shape[h] = true
		return shape

	## The island hex of `p` nearest a target hex.
	func nearest_tile(p: Dictionary, target: Vector2i) -> Vector2i:
		var best: Vector2i = p.center
		var best_d := INF
		var tw := world_of(target)
		for off in p.shape:
			var d := world_of(p.center + off).distance_to(tw)
			if d < best_d:
				best_d = d
				best = p.center + off
		return best

	## True if every planned walkway is short enough to build. Where an
	## outline leaves too wide a gap, both islands grow a spit of land toward
	## each other first.
	func spans_short() -> bool:
		for w in walkways:
			var a: Dictionary = _by_name[w[0]]
			var b: Dictionary = _by_name[w[1]]
			if span_gap(a, b) > LevelLayout.MAX_SPAN:
				grow_toward(a, b)
				grow_toward(b, a)
			if span_gap(a, b) > LevelLayout.MAX_SPAN:
				return false
		return true

	func span_gap(a: Dictionary, b: Dictionary) -> int:
		return HexGrid.distance(nearest_tile(a, b.center), nearest_tile(b, a.center)) - 1

	func grow_toward(p: Dictionary, other: Dictionary) -> void:
		if p.style == "city":
			return
		var tip := Vector2i.ZERO
		var best := INF
		var tw := world_of(other.center)
		for h in HexGrid.ring(Vector2i.ZERO, p.radius):
			var d := world_of(p.center + h).distance_to(tw)
			if d < best:
				best = d
				tip = h
		for h in HexGrid.line(Vector2i.ZERO, tip):
			if not p.shape.has(h):
				p.shape.append(h)

	## True if no walkway passes over a platform other than its two ends.
	func walkways_clear() -> bool:
		for w in walkways:
			var a: Dictionary = _by_name[w[0]]
			var b: Dictionary = _by_name[w[1]]
			for hex in HexGrid.line(a.center, b.center):
				for p in platforms:
					if p == a or p == b:
						continue
					if HexGrid.distance(hex, p.center) <= p.radius + 1:
						return false
		return true
