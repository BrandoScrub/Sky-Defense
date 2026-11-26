## Ironbell's bridge crews. The map starts with no walkways between islands,
## so Ironbell (the brute-force, ground-attack corporation) bridges its own
## way toward your Hub: one walkway span at a time, from its HQ down its chain
## of islands. Crews work steadily between waves and much faster while a wave
## is out, with the raiding party waiting at the end of the bridge.
##
## Spans that are already joined (by your walkways, say) are skipped. Vesper
## doesn't bridge: its bombers fly.
##
## Cutting a bridge: a unit of yours standing on a platform right beside an
## Ironbell span, with no enemy close by, saws through its cables. After
## cut_seconds the whole span falls (anyone on it falls too) and Ironbell's
## crew has to build it again.
class_name RivalBridges
extends Node

## Your units cut a span: its tiles fell. `tiles` is how many.
signal span_cut(corp: String, tiles: int)
## Your units started sawing at a span.
signal cutting_started(corp: String)
## A span was finished between two platforms.
signal span_built(corp: String, from_platform: String, to_platform: String)
## The bridge reached a platform you own.
signal reached_player(corp: String, platform_name: String)

@export var region: SkyRegion
## Optional: crews speed up while a wave is out.
@export var waves: WaveManager
## Seconds per span between waves.
@export var span_seconds := 30.0
## How much faster crews work while a wave is out (1 = no faster).
@export var wave_speedup := 1.0
## Seconds your units need beside a span to cut it down.
@export var cut_seconds := 8.0
## Optional: cutting stops while an enemy is this close to the cutter.
@export var combat: CombatSystem
const CUT_ENEMY_RANGE := 6.0
## Corporations that don't bridge (besides any RivalCatalog says don't).
@export var fliers: Array[String] = []

## corp -> {path: Array (HQ first, Hub last), next: index of the next span,
## progress: seconds, building: true while a span is going up}
var crews := {}
## Rival walkway hex being sawn at -> seconds of sawing so far.
var cuts := {}


func _ready() -> void:
	for corp in region.layout.paths:
		if fliers.has(corp) or (RivalCatalog.has(corp) and not RivalCatalog.bridges(corp)):
			continue
		var path: Array = region.layout.paths[corp].duplicate()
		path.reverse()
		crews[corp] = {"path": path, "next": 0, "progress": 0.0, "building": false}
		_skip_linked(corp)


func _process(delta: float) -> void:
	step(delta)


## Advances every crew by `delta` seconds. Public so tests can drive it.
func step(delta: float) -> void:
	step_cutting(delta)
	var speed := wave_speedup if waves and waves.phase == WaveManager.WAVE else 1.0
	for corp in crews:
		var crew: Dictionary = crews[corp]
		if is_done(corp) or crew.building or not _hq_alive(crew.path[0]):
			continue
		crew.progress += delta * speed
		if crew.progress >= seconds_per_span(corp):
			crew.progress = 0.0
			build_next_span(corp)


## Seconds between a rival's spans: its own pace from RivalCatalog, or
## span_seconds.
func seconds_per_span(corp: String) -> float:
	return float(RivalCatalog.get_data(corp).get("span_seconds", span_seconds)) * span_seconds / 30.0


## Starts the next span: harpoons fire and the tiles go down one by one
## (at once with SkyRegion.instant_walkways). Returns false if the bridge is
## done or a span is already going up.
func build_next_span(corp: String) -> bool:
	_skip_linked(corp)
	var crew: Dictionary = crews[corp]
	if is_done(corp) or crew.building:
		return false
	var from: String = crew.path[crew.next]
	var to: String = crew.path[crew.next + 1]
	var span := region.planned_span_tiles(from, to)
	var a: Dictionary = region.platforms[from]
	var b: Dictionary = region.platforms[to]
	crew.building = true
	crew.span = span
	var done := func(): _span_done(corp, from, to)
	region.build_walkway(span, "rival", region.hex_center(region.rim_toward(a, b.center, true)),
		region.hex_center(region.rim_toward(b, a.center, true)), done)
	return true


func _span_done(corp: String, from: String, to: String) -> void:
	var crew: Dictionary = crews[corp]
	crew.building = false
	# Remember whose span it is, for cutting.
	for hex in crew.get("span", []):
		if region.tiles.has(hex):
			region.tiles[hex].corp = corp
	# Work out where the bridge ends from scratch: a span may have been cut
	# while this one went up.
	crew.next = 0
	_skip_linked(corp)
	span_built.emit(corp, from, to)
	if region.platform_owner(to) == "player":
		reached_player.emit(corp, to)
	_skip_linked(corp)


func is_done(corp: String) -> bool:
	var crew: Dictionary = crews[corp]
	return crew.next >= crew.path.size() - 1


## The platform at the end of a corporation's bridge so far, where its raiders
## wait for the next span.
func frontier(corp: String) -> String:
	var crew: Dictionary = crews.get(corp, {})
	if crew.is_empty():
		return ""
	return crew.path[mini(crew.next, crew.path.size() - 1)]


## Spans built so far.
func spans_built(corp: String) -> int:
	return crews[corp].next if crews.has(corp) else 0


## Your units beside an Ironbell span saw at it. Public so tests can drive it.
func step_cutting(delta: float) -> void:
	if not is_inside_tree():
		return
	var touched := {}
	for node in get_tree().get_nodes_in_group(Unit.GROUP):
		var unit := node as Unit
		if unit.flying or unit.hp <= 0.0 or unit.is_moving():
			continue
		var hex := region.hex_at(unit.position)
		if region.tiles.get(hex, {}).get("platform", "") == "":
			continue
		if combat and combat.nearest_enemy(unit.global_position, "player", CUT_ENEMY_RANGE) != null:
			continue
		for d in HexGrid.DIRECTIONS:
			var next: Vector2i = hex + d
			if _is_rival_walkway(next) and not touched.has(next):
				touched[next] = true
				if not cuts.has(next):
					cutting_started.emit(_corp_of_span(next))
				cuts[next] = cuts.get(next, 0.0) + delta
	for hex in cuts.keys():
		if not touched.has(hex):
			cuts.erase(hex)
		elif cuts[hex] >= cut_seconds:
			cuts.erase(hex)
			cut_span(hex)


## Drops the whole Ironbell span that `hex` is part of. Units on it fall.
## Returns how many tiles fell.
func cut_span(hex: Vector2i) -> int:
	if not _is_rival_walkway(hex):
		return 0
	var corp := _corp_of_span(hex)
	var span := {hex: true}
	var todo: Array[Vector2i] = [hex]
	while not todo.is_empty():
		var here: Vector2i = todo.pop_back()
		for d in HexGrid.DIRECTIONS:
			var next: Vector2i = here + d
			if not span.has(next) and _is_rival_walkway(next):
				span[next] = true
				todo.append(next)
	for group in [Unit.GROUP, Unit.ENEMY_GROUP]:
		for node in get_tree().get_nodes_in_group(group):
			var unit := node as Unit
			if not unit.flying and span.has(region.hex_at(unit.position)):
				unit.take_damage(1.0e9)
	region.remove_tiles(span.keys())
	region.walkways_changed.emit()
	for c in crews:
		crews[c].next = 0
		crews[c].progress = 0.0
		_skip_linked(c)
	span_cut.emit(corp, span.size())
	return span.size()


## Seconds of sawing so far at the most-sawn span, or 0.
func cut_progress() -> float:
	var most := 0.0
	for hex in cuts:
		most = maxf(most, cuts[hex])
	return most


func _is_rival_walkway(hex: Vector2i) -> bool:
	var t: Dictionary = region.tiles.get(hex, {})
	return t.get("type", "") == "walkway" and t.get("builder", "") == "rival"


func _corp_of_span(hex: Vector2i) -> String:
	var corp: String = region.tiles.get(hex, {}).get("corp", "")
	if corp == "" and not crews.is_empty():
		corp = crews.keys()[0]
	return corp


## True while the bridge hasn't reached `corp`'s target yet and `unit` is
## waiting at its end (RivalRaids: camped raiders don't hold up a wave).
func is_waiting_at_frontier(corp: String, unit: Unit) -> bool:
	if not crews.has(corp) or is_done(corp) or unit.is_moving():
		return false
	return region.platform_at(unit.position) == frontier(corp)


func _skip_linked(corp: String) -> void:
	var crew: Dictionary = crews[corp]
	while not is_done(corp) and region.platforms_linked(crew.path[crew.next], crew.path[crew.next + 1]):
		crew.next += 1


func _hq_alive(platform_name: String) -> bool:
	for hq in get_tree().get_nodes_in_group(Headquarters.GROUP):
		if hq.platform == platform_name and hq.faction == "rival":
			return hq.is_alive()
	return true
