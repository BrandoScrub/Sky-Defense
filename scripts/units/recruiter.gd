## Trains units at the Hub headquarters. Each Army tab button queues one unit
## type from UnitCatalog. A unit costs scrap up front, and the queue trains
## them one at a time; each walks out of the Hub when its training time ends.
class_name Recruiter
extends Node

signal notice(text: String)
signal recruited(unit: Unit)

@export var max_queue := 5
## Most player units allowed on the field at once (the hero counts).
@export var unit_cap := 16

@export var region: SkyRegion
@export var resources: PlayerResources
## Where new units go in the scene tree.
@export var units_root: Node3D

## Type ids waiting to be trained, front first.
var queue: Array[String] = []
## Seconds left on the unit at the front of the queue.
var time_left := 0.0
var queued: int:
	get:
		return queue.size()
var _count := 0


func _process(delta: float) -> void:
	step(delta)


## Scrap cost of a unit type.
static func cost_of(type_id: String) -> int:
	return int(UnitCatalog.get_data(type_id).cost)


## Training time of a unit type, in seconds.
static func train_seconds_of(type_id: String) -> float:
	return float(UnitCatalog.get_data(type_id).train_seconds)


## How many of a type are waiting in the queue.
func queued_of(type_id: String) -> int:
	return queue.count(type_id)


## Why a unit can't be queued right now, or "" after queueing one.
func queue_one(type_id := "riveteer") -> String:
	if not UnitCatalog.has_unit(type_id):
		return "Unknown unit: %s" % type_id
	var unit_name: String = UnitCatalog.get_data(type_id).name
	if queue.size() >= max_queue:
		return "The training queue is full"
	if _field_count() + queue.size() >= unit_cap:
		return "Unit limit reached (%d)" % unit_cap
	if not resources.spend_scrap(cost_of(type_id)):
		return "Not enough scrap: a %s costs %d" % [unit_name, cost_of(type_id)]
	if queue.is_empty():
		time_left = train_seconds_of(type_id)
	queue.append(type_id)
	return ""


## Advances training by `delta` seconds. Public so tests can drive it.
func step(delta: float) -> void:
	if queue.is_empty():
		return
	time_left -= delta
	if time_left > 0.0:
		return
	var type_id: String = queue.pop_front()
	if not queue.is_empty():
		time_left = train_seconds_of(queue[0])
	var unit := UnitCatalog.make(type_id, "player")
	_count += 1
	unit.name = "%s%d" % [type_id.capitalize().replace(" ", ""), _count]
	var hub := region.hex_at(region.get_platform_position("Hub"))
	var spot := region.snap_to_walkable(region.hex_center(hub + Vector2i(0, 2)) + Vector3((_count % 3) - 1.0, 0, 0))
	unit.position = spot
	units_root.add_child(unit)
	recruited.emit(unit)


func _field_count() -> int:
	return get_tree().get_nodes_in_group(Unit.GROUP).size()
