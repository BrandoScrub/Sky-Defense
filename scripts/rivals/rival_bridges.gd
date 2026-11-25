## Ironbell's bridge crews. The map starts with no walkways between islands,
## so Ironbell (the brute-force, ground-attack corporation) bridges its own
## way toward your Hub: one walkway span at a time, from its HQ down its chain
## of islands. Crews work steadily between waves and much faster while a wave
## is out, with the raiding party waiting at the end of the bridge.
##
## Spans that are already joined (by your walkways, say) are skipped. Vesper
## doesn't bridge: its bombers fly.
class_name RivalBridges
extends Node

## A span was finished between two platforms.
signal span_built(corp: String, from_platform: String, to_platform: String)
## The bridge reached a platform you own.
signal reached_player(corp: String, platform_name: String)

@export var region: SkyRegion
## Optional: crews speed up while a wave is out.
@export var waves: WaveManager
## Seconds per span between waves.
@export var span_seconds := 10.0
## How much faster crews work while a wave is out.
@export var wave_speedup := 3.0
## Corporations that don't bridge.
@export var fliers: Array[String] = ["Vesper"]

## corp -> {path: Array (HQ first, Hub last), next: index of the next span,
## progress: seconds}
var crews := {}


func _ready() -> void:
	for corp in region.layout.paths:
		if fliers.has(corp):
			continue
		var path: Array = region.layout.paths[corp].duplicate()
		path.reverse()
		crews[corp] = {"path": path, "next": 0, "progress": 0.0}
		_skip_linked(corp)


func _process(delta: float) -> void:
	step(delta)


## Advances every crew by `delta` seconds. Public so tests can drive it.
func step(delta: float) -> void:
	var speed := wave_speedup if waves and waves.phase == WaveManager.WAVE else 1.0
	for corp in crews:
		var crew: Dictionary = crews[corp]
		if is_done(corp) or not _hq_alive(crew.path[0]):
			continue
		crew.progress += delta * speed
		if crew.progress >= span_seconds:
			crew.progress = 0.0
			build_next_span(corp)


## Finishes the next span right away. Returns false if the bridge is done.
func build_next_span(corp: String) -> bool:
	_skip_linked(corp)
	if is_done(corp):
		return false
	var crew: Dictionary = crews[corp]
	var from: String = crew.path[crew.next]
	var to: String = crew.path[crew.next + 1]
	var span := region.planned_span_tiles(from, to)
	if not span.is_empty():
		region.add_walkway(span, "rival")
	crew.next += 1
	span_built.emit(corp, from, to)
	if region.platform_owner(to) == "player":
		reached_player.emit(corp, to)
	_skip_linked(corp)
	return true


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


func _skip_linked(corp: String) -> void:
	var crew: Dictionary = crews[corp]
	while not is_done(corp) and region.platforms_linked(crew.path[crew.next], crew.path[crew.next + 1]):
		crew.next += 1


func _hq_alive(platform_name: String) -> bool:
	for hq in get_tree().get_nodes_in_group(Headquarters.GROUP):
		if hq.platform == platform_name and hq.faction == "rival":
			return hq.is_alive()
	return true
