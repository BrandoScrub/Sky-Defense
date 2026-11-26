## Platform weight and overload, from the design doc. Every building and unit
## has weight; a platform carrying more than its capacity gets worse the
## further over it goes:
##
##   up to 100%   Stable    no effect
##   100 to 115%  Swaying   buildings sway (tower accuracy penalty later)
##   115 to 130%  Sagging   units on it move at 60% speed
##   over 130%    Failing   units at 40% speed, and every few seconds the
##                          newest building breaks off and falls
class_name LoadSystem
extends Node

signal building_lost(building_name: String, platform_name: String)

const STABLE := "Stable"
const SWAYING := "Swaying"
const SAGGING := "Sagging"
const FAILING := "Failing"

const SPEED := {STABLE: 1.0, SWAYING: 1.0, SAGGING: 0.6, FAILING: 0.4}
const SWAY := {STABLE: 0.0, SWAYING: 0.03, SAGGING: 0.06, FAILING: 0.1}

## Seconds a failing platform holds before its newest building drops.
@export var failing_seconds_per_loss := 6.0

@export var region: SkyRegion
## While true (Emergency Lift), the player's platforms count as Stable.
var ignore_player_overload := false

## platform name -> state string
var states := {}
var _failing_timers := {}
var _time := 0.0


func _process(delta: float) -> void:
	step(delta)


static func state_for(load_amount: int, capacity: int) -> String:
	var ratio := float(load_amount) / maxf(capacity, 1)
	if ratio > 1.30:
		return FAILING
	if ratio > 1.15:
		return SAGGING
	if ratio > 1.0:
		return SWAYING
	return STABLE


## Re-evaluates every platform. Public so tests can drive it.
func step(delta: float) -> void:
	_time += delta
	for platform_name in region.platforms:
		var state := state_for(region.platform_load(platform_name), region.platform_capacity(platform_name))
		if ignore_player_overload and region.platform_owner(platform_name) == "player":
			state = STABLE
		states[platform_name] = state
		region.load_states[platform_name] = state
		_sway(platform_name, state)
		if state == FAILING:
			_failing_timers[platform_name] = _failing_timers.get(platform_name, 0.0) + delta
			if _failing_timers[platform_name] >= failing_seconds_per_loss:
				_failing_timers[platform_name] = 0.0
				_drop_newest(platform_name)
		else:
			_failing_timers[platform_name] = 0.0
		region.refresh_label(platform_name)

	for group in [Unit.GROUP, Unit.ENEMY_GROUP]:
		for node in get_tree().get_nodes_in_group(group):
			var unit := node as Unit
			var here := region.platform_at(unit.position)
			unit.speed_multiplier = SPEED[states.get(here, STABLE)] if here != "" else 1.0


func state_of(platform_name: String) -> String:
	return states.get(platform_name, STABLE)


func _sway(platform_name: String, state: String) -> void:
	var amount: float = SWAY[state]
	for b in region.buildings_on(platform_name):
		b.rotation.z = sin(_time * 2.5 + b.hex.x) * amount
		b.rotation.x = cos(_time * 2.0 + b.hex.y) * amount


func _drop_newest(platform_name: String) -> void:
	var list := region.buildings_on(platform_name)
	if list.is_empty():
		return
	var b: Building = list.back()
	region.remove_building(b.hex)
	building_lost.emit(b.get_data().name, platform_name)
	# Tumble off the edge and vanish.
	if b.is_inside_tree():
		var tween := b.create_tween().set_parallel(true)
		tween.tween_property(b, "position:y", b.position.y - 25.0, 1.5).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(b, "rotation:z", 2.0, 1.5)
		tween.chain().tween_callback(b.queue_free)
	else:
		b.queue_free()
