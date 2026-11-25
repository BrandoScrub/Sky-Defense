## Balloon platforms: small islands held up by gas bags that drift between two
## moorings along a set track, one whole hex at a time, so they always sit on
## the hex grid. (The world doc's towable balloon platforms.)
##
## Each balloon runs a loop:
##   1. Moored: a short walkway joins it to the platform at its mooring.
##   2. Warning: for `warning_seconds` the walkway flashes amber, every unit
##      standing on it gets a caution sign over its head, and a klaxon sounds
##      (then a beep each second) while any of your units are still on it.
##   3. Cast off: the walkway breaks away and falls. Any unit still on it falls
##      with it and is lost (the Commander comes back at the Hub as usual).
##      Units on the balloon itself are safe: they ride along.
##   4. Drifting: the balloon hops one hex at a time down its track.
##   5. It moors at the far end, a new walkway reaches out to the platform
##      there, and the loop starts again in the other direction.
##
## The track and its moorings are picked from the map seed, through open sky
## well clear of other tiles. Walkways can't be built across a track (see
## SkyRegion.reserved_hexes); if something does block it, the balloon waits.
class_name DriftSystem
extends Node

## A walkway is about to break off. `player_units` are your units on it.
signal warning_started(balloon_name: String, platform_name: String, seconds: float, player_units: int)
## The walkway broke off; `fallen` units (both sides) fell with it.
signal cast_off(balloon_name: String, platform_name: String, fallen: Array)
## The balloon reached a mooring and its walkway reconnected.
signal moored(balloon_name: String, platform_name: String)

@export var region: SkyRegion
@export var max_balloons := 2
## Seconds a balloon stays moored before the warning starts.
@export var moored_seconds := 35.0
## Seconds of warning before the walkway breaks off.
@export var warning_seconds := 6.0
## Seconds per one-hex hop while drifting.
@export var hop_seconds := 1.1
## Seconds a unit takes to fall out of sight.
@export var fall_seconds := 1.4

const RADIUS := 1
## Tiles of walkway between a moored balloon and its platform.
const WALKWAY_TILES := 2
const MIN_TRACK := 3
const MAX_TRACK := 14
const NAMES := ["Zephyr Barge", "Gasbag Wharf", "Drifting Anchorage", "Tethered Isle"]
const CAUTION_NAME := "DriftCaution"

const MOORED := "moored"
const WARNING := "warning"
const DRIFTING := "drifting"

## One entry per balloon: {name, track: Array[Vector2i], ends: [platform,
## platform], index (position on the track), dir (+1/-1), state, timer,
## walkway: Array[Vector2i], hop (0..1), riders: Array[Unit], root: Node3D,
## sign: Label3D, beep (seconds to next beep)}
var balloons: Array[Dictionary] = []

var _klaxon: AudioStreamPlayer
var _beep: AudioStreamPlayer
var _warn_mat: StandardMaterial3D
var _flash := 0.0


func _ready() -> void:
	_klaxon = _player("Klaxon", _tone([660.0, 440.0, 660.0, 440.0], 0.16, 0.5))
	_beep = _player("Beep", _tone([880.0], 0.12, 0.4))
	_warn_mat = StandardMaterial3D.new()
	_warn_mat.albedo_color = Color(1.0, 0.6, 0.1)
	_warn_mat.emission_enabled = true
	_warn_mat.emission = Color(1.0, 0.5, 0.0)
	_warn_mat.emission_energy_multiplier = 1.2
	_place_balloons()


func _process(delta: float) -> void:
	step(delta)


## Advances every balloon by `delta` seconds. Public so tests can drive it.
func step(delta: float) -> void:
	_flash += delta
	for b in balloons:
		b.timer -= delta
		match b.state:
			MOORED:
				if b.timer <= 0.0:
					_start_warning(b)
			WARNING:
				_update_warning(b, delta)
				if b.timer <= 0.0:
					_cast_off(b)
			DRIFTING:
				_drift(b, delta)
		_update_sign(b)


## The balloon entry with this name, or {}.
func get_balloon(balloon_name: String) -> Dictionary:
	for b in balloons:
		if b.name == balloon_name:
			return b
	return {}


## Hex the balloon's centre is on now.
func center_of(b: Dictionary) -> Vector2i:
	return b.track[b.index]


## The platform the balloon is moored to, or "" while drifting.
func moored_to(b: Dictionary) -> String:
	if b.state == DRIFTING:
		return ""
	return b.ends[0] if b.index == 0 else b.ends[1]


## Units standing on the walkway that's about to break.
func endangered_units(b: Dictionary) -> Array[Unit]:
	var out: Array[Unit] = []
	if b.state == DRIFTING:
		return out
	var on_walkway := {}
	for hex in b.walkway:
		on_walkway[hex] = true
	for group in [Unit.GROUP, Unit.ENEMY_GROUP]:
		for node in get_tree().get_nodes_in_group(group):
			var unit := node as Unit
			if unit.flying or unit.riding or not unit.is_alive():
				continue
			if on_walkway.has(region.hex_at(unit.global_position)):
				out.append(unit)
	return out


# --- The loop ---------------------------------------------------------------

func _start_warning(b: Dictionary) -> void:
	b.state = WARNING
	b.timer = warning_seconds
	b.beep = 1.0
	var players := _player_count(endangered_units(b))
	if players > 0:
		_klaxon.play()
	warning_started.emit(b.name, moored_to(b), warning_seconds, players)
	_update_warning(b, 0.0)


func _update_warning(b: Dictionary, delta: float) -> void:
	var endangered := endangered_units(b)
	_set_cautions(b, endangered)
	# Flash the walkway amber.
	var on := fmod(_flash, 0.5) < 0.25
	for hex in b.walkway:
		var node := region.tile_node(hex)
		if node:
			if not b.plain_mats.has(hex):
				b.plain_mats[hex] = node.material_override
			node.material_override = _warn_mat if on else b.plain_mats[hex]
	b.beep -= delta
	if b.beep <= 0.0:
		b.beep = 1.0
		if _player_count(endangered) > 0 and not _klaxon.playing:
			_beep.play()


func _cast_off(b: Dictionary) -> void:
	var platform_name := moored_to(b)
	var fallen := endangered_units(b)
	_set_cautions(b, [])
	for unit in fallen:
		_fall(unit)
	_drop_walkway(b)
	b.state = DRIFTING
	b.dir = 1 if b.index == 0 else -1
	b.hop = 0.0
	b.riders = []
	cast_off.emit(b.name, platform_name, fallen)


func _drift(b: Dictionary, delta: float) -> void:
	var next: Vector2i = b.track[b.index + b.dir]
	if b.hop == 0.0:
		if not _clear_to(b, next):
			return  # Something is in the way: wait for it to clear.
		b.riders = _units_aboard(b)
		for unit in b.riders:
			unit.stop()
	var step_vec := region.hex_center(next) - region.hex_center(center_of(b))
	var before: float = b.hop
	b.hop = minf(1.0, b.hop + delta / hop_seconds)
	var moved := step_vec * (_ease(b.hop) - _ease(before))
	var offset := step_vec * _ease(b.hop)
	# Glide the deck, buildings and riders; the grid catches up at the end.
	for hex in HexGrid.disk(center_of(b), RADIUS):
		var node := region.tile_node(hex)
		if node:
			node.position = _tile_base(hex) + offset
		var building: Building = region.buildings.get(hex)
		if building:
			building.position = region.hex_center(hex) + offset
	for unit in b.riders:
		if is_instance_valid(unit):
			unit.position += moved
	b.root.position = region.hex_center(center_of(b)) + offset
	_place_label(b, offset)
	if b.hop >= 1.0:
		_commit_hop(b)


## Moves the balloon's tiles and buildings one hex along the track.
func _commit_hop(b: Dictionary) -> void:
	var old_center := center_of(b)
	b.index += b.dir
	var shift: Vector2i = center_of(b) - old_center
	var old_hexes := HexGrid.disk(old_center, RADIUS)
	var moved_tiles := {}
	for hex in old_hexes:
		moved_tiles[hex + shift] = region.get_tile(hex).duplicate()
	var moving := []
	for hex in old_hexes:
		if region.buildings.has(hex):
			moving.append(region.buildings[hex])
			region.buildings.erase(hex)
	region.remove_tiles(old_hexes)
	for building in moving:
		building.hex += shift
		building.position = region.hex_center(building.hex)
		region.buildings[building.hex] = building
	region.add_tiles(moved_tiles)
	region.platforms[b.name].center = center_of(b)
	b.root.position = region.hex_center(center_of(b))
	_place_label(b, Vector3.ZERO)
	b.hop = 0.0
	b.riders = []
	# The deck tiles are new nodes now (fog of war tracks map pieces by node).
	region.walkways_changed.emit()
	if b.index == 0 or b.index == b.track.size() - 1:
		_moor(b)


func _moor(b: Dictionary) -> void:
	b.state = MOORED
	b.timer = moored_seconds
	_lay_walkway(b)
	moored.emit(b.name, moored_to(b))


# --- Walkways ---------------------------------------------------------------

## The walkway hexes between the balloon at its current spot and the
## platform it moors to there.
func _walkway_hexes(b: Dictionary) -> Array[Vector2i]:
	var platform: Dictionary = region.platforms[moored_to(b)]
	return _corridor(center_of(b), platform)


func _corridor(center: Vector2i, platform: Dictionary) -> Array[Vector2i]:
	var from := _rim(center, RADIUS, platform.center)
	var to := _rim(platform.center, platform.radius, center)
	var out: Array[Vector2i] = []
	for hex in HexGrid.line(from, to):
		if HexGrid.distance(hex, center) > RADIUS and HexGrid.distance(hex, platform.center) > platform.radius:
			out.append(hex)
	return out


func _lay_walkway(b: Dictionary) -> void:
	b.walkway = _walkway_hexes(b)
	var new_tiles := {}
	for hex in b.walkway:
		new_tiles[hex] = {"type": "walkway", "platform": ""}
	region.add_tiles(new_tiles)
	# Extend the planks out from the balloon.
	for i in b.walkway.size():
		var node := region.tile_node(b.walkway[i])
		if node:
			node.scale = Vector3(0.05, 1, 0.05)
			var tween := node.create_tween()
			tween.tween_interval(0.15 * i)
			tween.tween_property(node, "scale", Vector3.ONE, 0.3)
	region.walkways_changed.emit()


## Removes the walkway and lets copies of its planks tumble into the clouds.
func _drop_walkway(b: Dictionary) -> void:
	for hex in b.walkway:
		var node := region.tile_node(hex)
		if node == null:
			continue
		var debris := node.duplicate() as MeshInstance3D
		debris.material_override = b.plain_mats.get(hex, node.material_override)
		region.add_child(debris)
		var tween := debris.create_tween().set_parallel()
		tween.tween_property(debris, "position:y", debris.position.y - 30.0, fall_seconds).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(debris, "rotation", Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)), fall_seconds)
		tween.chain().tween_callback(debris.queue_free)
	region.remove_tiles(b.walkway)
	b.walkway = []
	b.plain_mats = {}
	region.walkways_changed.emit()


func _fall(unit: Unit) -> void:
	unit.stop()
	unit.riding = true  # Stops it walking and fighting on the way down.
	var tween := unit.create_tween().set_parallel()
	tween.tween_property(unit, "position:y", unit.position.y - 30.0, fall_seconds).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(unit, "rotation:z", 1.5, fall_seconds)
	tween.chain().tween_callback(func(): unit.take_damage(unit.hp + 1.0))


# --- Caution signs and sound ------------------------------------------------

func _set_cautions(b: Dictionary, units: Array) -> void:
	var keep := {}
	for unit in units:
		keep[unit] = true
		if not unit.has_node(CAUTION_NAME):
			unit.add_child(_caution_sign(unit))
	for unit in b.get("cautioned", []):
		if is_instance_valid(unit) and not keep.has(unit):
			var sign_node: Node = unit.get_node_or_null(CAUTION_NAME)
			if sign_node:
				sign_node.queue_free()
				unit.remove_child(sign_node)
	b.cautioned = units.duplicate()
	for unit in units:
		var sign_node := unit.get_node(CAUTION_NAME) as Node3D
		sign_node.position.y = (3.9 if unit.is_hero else 3.3) + sin(_flash * 8.0) * 0.15


## An amber warning triangle with an exclamation mark, always facing the camera.
func _caution_sign(unit: Unit) -> Node3D:
	var root := Node3D.new()
	root.name = CAUTION_NAME
	var tri := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(1.7, 1.45, 0.05)
	tri.mesh = prism
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.75, 0.1)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.no_depth_test = true
	tri.material_override = mat
	root.add_child(tri)
	var mark := Label3D.new()
	mark.text = "!"
	mark.font_size = 72
	mark.outline_size = 0
	mark.modulate = Color(0.1, 0.08, 0.05)
	mark.pixel_size = 0.016
	mark.position.y = -0.12
	mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mark.no_depth_test = true
	mark.render_priority = 1
	root.add_child(mark)
	root.position.y = 3.9 if unit.is_hero else 3.3
	return root


func _player_count(units: Array) -> int:
	return units.filter(func(u): return u.faction == "player").size()


func _player(node_name: String, stream: AudioStream) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = node_name
	p.stream = stream
	p.volume_db = -6.0
	add_child(p)
	return p


## A placeholder alarm: square-ish tones, one after another.
func _tone(freqs: Array, seconds_each: float, volume: float) -> AudioStreamWAV:
	var rate := 22050
	var data := PackedByteArray()
	for f in freqs:
		var n := int(rate * seconds_each)
		for i in n:
			var t := float(i) / rate
			var env := minf(1.0, minf(i, n - i) / (rate * 0.01))
			var s := (sin(TAU * f * t) + 0.3 * sin(TAU * f * 3.0 * t)) * volume * env
			var v := clampi(int(s * 32767.0), -32768, 32767)
			data.append(v & 0xFF)
			data.append((v >> 8) & 0xFF)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = data
	return wav


# --- Placement --------------------------------------------------------------

## Picks tracks for up to `max_balloons` balloons and puts each at its first
## mooring.
func _place_balloons() -> void:
	var hub: Vector3 = region.get_platform_position("Hub")
	var candidates := []
	var names := []
	var linked := region.planned_reachable("Hub")
	for platform_name in region.platforms:
		var p: Dictionary = region.platforms[platform_name]
		if p.kind == "rival" or p.get("balloon", false):
			continue
		# Only platforms the planned walkways link to the Hub (not the
		# ferry-only Spire).
		if linked.has(platform_name):
			names.append(platform_name)
	names.sort()
	for i in names.size():
		for j in range(i + 1, names.size()):
			# Moor facing each other, or angled off a little if that's blocked.
			for turn in [[0.0, 0.0], [0.5, -0.5], [-0.5, 0.5], [0.5, 0.0], [-0.5, 0.0], [0.0, 0.5], [0.0, -0.5]]:
				var c := _candidate(names[i], names[j], hub, turn[0], turn[1])
				if not c.is_empty():
					candidates.append(c)
					break
	# Nearest the Hub first, so the first balloon is one you'll see early.
	candidates.sort_custom(func(x, y): return x.score < y.score)
	var taken := {}
	for c in candidates:
		if balloons.size() >= max_balloons:
			break
		if c.footprint.any(func(h): return taken.has(h)):
			continue
		for h in c.footprint:
			taken[h] = true
		# Keep a tile of sky between two balloons' paths.
		for h in c.footprint:
			for n in HexGrid.neighbors(h):
				taken[n] = true
		_spawn(c)


## A possible track between two platforms, or {} if they don't suit.
## `turn_a` and `turn_b` angle each mooring off the line between the two
## platforms (radians).
func _candidate(a_name: String, b_name: String, hub: Vector3, turn_a := 0.0, turn_b := 0.0) -> Dictionary:
	var a: Dictionary = region.platforms[a_name]
	var b: Dictionary = region.platforms[b_name]
	var wa := region.hex_center(a.center)
	var wb := region.hex_center(b.center)
	var dir := (wb - wa).normalized()
	var start := _mooring(a, dir.rotated(Vector3.UP, turn_a))
	var end := _mooring(b, (-dir).rotated(Vector3.UP, turn_b))
	var track := HexGrid.line(start, end)
	if track.size() - 1 < MIN_TRACK or track.size() - 1 > MAX_TRACK:
		return {}
	# The whole path, plus a tile of margin, must be open sky.
	var footprint := {}
	for hex in track:
		for h in HexGrid.disk(hex, RADIUS):
			footprint[h] = true
		for h in HexGrid.disk(hex, RADIUS + 1):
			if region.tiles.has(h) or region.planned_hexes.has(h):
				return {}
	# Each mooring walkway must cross open sky and touch only its two ends.
	for end_info in [[start, a], [end, b]]:
		var corridor := _corridor(end_info[0], end_info[1])
		if corridor.size() < 1 or corridor.size() > WALKWAY_TILES + 1:
			return {}
		var ends := {}
		for h in HexGrid.disk(end_info[0], RADIUS):
			ends[h] = true
		for h in corridor:
			ends[h] = true
			footprint[h] = true
		for h in corridor:
			if region.tiles.has(h) or region.planned_hexes.has(h):
				return {}
			for n in HexGrid.neighbors(h):
				if region.planned_hexes.has(n):
					return {}
				if region.tiles.has(n) and region.get_tile(n).platform != end_info[1].name:
					return {}
	var mid := (region.hex_center(start) + region.hex_center(end)) / 2.0
	return {"ends": [a_name, b_name], "track": track, "footprint": footprint.keys(),
		"score": mid.distance_to(hub)}


## Where a balloon moors beside a platform, facing `dir`.
func _mooring(p: Dictionary, dir: Vector3) -> Vector2i:
	var steps: int = p.radius + RADIUS + 1 + WALKWAY_TILES
	var world := region.hex_center(p.center) + dir * steps * region.tile_size * HexGrid.SQRT3
	return region.hex_at(world)


## The rim hex of a disk closest to a target hex.
func _rim(center: Vector2i, radius: int, target: Vector2i) -> Vector2i:
	var target_world := region.hex_center(target)
	var best := center
	var best_d := INF
	for hex in HexGrid.ring(center, radius):
		var d := region.hex_center(hex).distance_to(target_world)
		if d < best_d:
			best_d = d
			best = hex
	return best


func _spawn(c: Dictionary) -> void:
	var balloon_name: String = NAMES[balloons.size() % NAMES.size()]
	var track: Array[Vector2i] = []
	track.assign(c.track)
	var b := {
		"name": balloon_name, "track": track, "ends": c.ends, "index": 0, "dir": 1,
		"state": MOORED, "timer": moored_seconds * (1.0 + 0.4 * balloons.size()),
		"walkway": [], "hop": 0.0, "riders": [], "beep": 1.0, "cautioned": [], "plain_mats": {},
	}
	region.add_platform({"name": balloon_name, "kind": "neutral", "balloon": true,
		"center": track[0], "radius": RADIUS, "capacity": LevelLayout.CAPACITY[RADIUS], "features": []})
	var new_tiles := {}
	for hex in HexGrid.disk(track[0], RADIUS):
		new_tiles[hex] = {"type": "deck", "platform": balloon_name}
	region.add_tiles(new_tiles)
	for hex in c.footprint:
		if not region.tiles.has(hex):
			region.reserved_hexes[hex] = true
	b.root = _build_hull(balloon_name)
	b.root.position = region.hex_center(track[0])
	region.add_child(b.root)
	b.sign = Label3D.new()
	b.sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	b.sign.no_depth_test = true
	b.sign.font_size = 56
	b.sign.outline_size = 10
	b.sign.pixel_size = 0.02
	# Above the platform name and load label.
	b.sign.position.y = 13.0
	b.root.add_child(b.sign)
	_draw_track(b)
	balloons.append(b)
	_lay_walkway(b)
	_place_label(b, Vector3.ZERO)
	_update_sign(b)


func _clear_to(b: Dictionary, next: Vector2i) -> bool:
	for h in HexGrid.disk(next, RADIUS + 1):
		if region.tiles.has(h) and region.get_tile(h).platform != b.name:
			return false
	return true


func _units_aboard(b: Dictionary) -> Array[Unit]:
	var out: Array[Unit] = []
	for group in [Unit.GROUP, Unit.ENEMY_GROUP]:
		for unit in region.units_on_platform(b.name, group):
			out.append(unit as Unit)
	return out


# --- Visuals ----------------------------------------------------------------

func _tile_base(hex: Vector2i) -> Vector3:
	return region.hex_center(hex) + Vector3.DOWN * SkyRegion.DECK_HEIGHT / 2.0


func _place_label(b: Dictionary, offset: Vector3) -> void:
	var label := region.platform_label(b.name)
	if label:
		label.position = region.hex_center(center_of(b)) + offset + Vector3.UP * (6.0 + RADIUS)


func _update_sign(b: Dictionary) -> void:
	match b.state:
		MOORED:
			b.sign.text = "Moored at %s\nCasts off in %ds" % [moored_to(b), ceili(maxf(b.timer, 0.0) + warning_seconds)]
			b.sign.modulate = Color(0.75, 0.95, 1.0)
		WARNING:
			b.sign.text = "CASTING OFF IN %d\nClear the walkway!" % ceili(maxf(b.timer, 0.0))
			b.sign.modulate = Color(1.0, 0.65, 0.15) if fmod(_flash, 0.5) < 0.25 else Color(1.0, 0.9, 0.4)
		DRIFTING:
			var to: String = b.ends[1] if b.dir > 0 else b.ends[0]
			b.sign.text = "Drifting to %s" % to
			b.sign.modulate = Color(0.75, 0.95, 1.0)


## Faint markers along the track so you can see where the balloon goes.
func _draw_track(b: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "Track_" + b.name.replace(" ", "")
	region.add_child(root)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.85, 1.0, 0.65)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mesh := CylinderMesh.new()
	mesh.top_radius = region.tile_size * 0.35
	mesh.bottom_radius = region.tile_size * 0.35
	mesh.height = 0.05
	mesh.radial_segments = 6
	for hex in b.track:
		var dot := MeshInstance3D.new()
		dot.mesh = mesh
		dot.material_override = mat
		dot.position = region.hex_center(hex) + Vector3.DOWN * 0.3
		root.add_child(dot)


## Placeholder hull: a wooden keel under the deck, gas bags on struts at the
## sides and a propeller at the back.
func _build_hull(balloon_name: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Balloon_" + balloon_name.replace(" ", "")
	var wood := _mat(Color(0.42, 0.28, 0.16))
	var canvas := _mat(Color(0.86, 0.78, 0.6))
	var brass := _mat(Color(0.75, 0.56, 0.26))
	var span := region.tile_size * HexGrid.SQRT3 * (RADIUS + 0.45)
	var keel := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = span
	cone.bottom_radius = span * 0.4
	cone.height = 1.6
	cone.radial_segments = 6
	keel.mesh = cone
	keel.rotation.y = PI / 6.0
	keel.position.y = -SkyRegion.DECK_HEIGHT - 0.8
	keel.material_override = wood
	root.add_child(keel)
	for i in 3:
		var angle := TAU * i / 3.0 + PI / 6.0
		var out := Vector3(cos(angle), 0, sin(angle))
		var bag := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.9
		capsule.height = 3.2
		bag.mesh = capsule
		bag.rotation = Vector3(PI / 2.0, -angle + PI / 2.0, 0)
		bag.position = out * (span + 0.9) + Vector3.UP * 0.6
		bag.material_override = canvas
		root.add_child(bag)
		var strut := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1.2, 0.12, 0.12)
		strut.mesh = box
		strut.rotation.y = -angle
		strut.position = out * (span + 0.2) + Vector3.UP * 0.1
		strut.material_override = brass
		root.add_child(strut)
	var prop := MeshInstance3D.new()
	var blade := BoxMesh.new()
	blade.size = Vector3(0.12, 1.8, 0.25)
	prop.mesh = blade
	prop.position = Vector3(0, -1.2, span * 0.75)
	prop.material_override = brass
	root.add_child(prop)
	return root


func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.7
	return m


func _ease(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)
