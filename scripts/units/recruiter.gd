## Trains Riveteers at the Hub headquarters. Press Y to queue one; each costs
## scrap up front and walks out of the Hub after a short training time.
class_name Recruiter
extends Node

signal notice(text: String)
signal recruited(unit: Unit)

@export var cost := 30
@export var train_seconds := 5.0
@export var max_queue := 5
## Most player units allowed on the field at once (the hero counts).
@export var unit_cap := 16

@export var region: SkyRegion
@export var resources: PlayerResources
## Where new units go in the scene tree.
@export var units_root: Node3D

var queued := 0
var time_left := 0.0
var _count := 0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("recruit_unit"):
		var problem := queue_one()
		notice.emit(problem if problem != "" else "Riveteer queued (%d in training)" % queued)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	step(delta)


## Why a Riveteer can't be queued right now, or "" after queueing one.
func queue_one() -> String:
	if queued >= max_queue:
		return "The training queue is full"
	if _field_count() + queued >= unit_cap:
		return "Unit limit reached (%d)" % unit_cap
	if not resources.spend_scrap(cost):
		return "Not enough scrap: a Riveteer costs %d" % cost
	if queued == 0:
		time_left = train_seconds
	queued += 1
	return ""


## Advances training by `delta` seconds. Public so tests can drive it.
func step(delta: float) -> void:
	if queued == 0:
		return
	time_left -= delta
	if time_left > 0.0:
		return
	queued -= 1
	time_left = train_seconds
	var unit := Unit.new()
	_count += 1
	unit.name = "Recruit%d" % _count
	var hub := region.hex_at(region.get_platform_position("Hub"))
	var spot := region.snap_to_walkable(region.hex_center(hub + Vector2i(0, 2)) + Vector3((_count % 3) - 1.0, 0, 0))
	unit.position = spot
	units_root.add_child(unit)
	recruited.emit(unit)


func _field_count() -> int:
	return get_tree().get_nodes_in_group(Unit.GROUP).size()
