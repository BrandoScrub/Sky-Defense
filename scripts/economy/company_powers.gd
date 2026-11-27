## Company powers: short, map-wide effects bought with energized crystals
## (the advanced resource your Cloud Harvesters pay each wave). Each one runs
## for a few seconds and then needs a cooldown before it can be used again.
##
## - Overcharge: every tower you own fires faster for a while.
class_name CompanyPowers
extends Node

signal notice(text: String)
## A power started or ended.
signal changed

const POWERS := {
	"overcharge": {
		"name": "Overcharge", "crystals": 15, "seconds": 20.0, "cooldown": 45.0,
		"blurb": "Every tower you own fires 40% faster for 20 seconds.",
	},
}
## How much faster towers fire while Overcharge runs.
const OVERCHARGE_RATE := 1.4

@export var resources: PlayerResources
@export var combat: CombatSystem

## power id -> seconds left while it runs
var running := {}
## power id -> seconds until it can be used again
var cooldowns := {}


func _process(delta: float) -> void:
	step(delta)


## Uses a power. Returns "" or why it can't be used now.
func use(id: String) -> String:
	var spec: Dictionary = POWERS[id]
	if running.has(id):
		return "%s is already running" % spec.name
	if cooldowns.get(id, 0.0) > 0.0:
		return "%s is ready again in %ds" % [spec.name, ceili(cooldowns[id])]
	if resources and not resources.spend_crystals(spec.crystals):
		return "%s needs %d crystals. Cloud Harvesters pay them each wave" % [spec.name, spec.crystals]
	running[id] = spec.seconds
	_apply()
	notice.emit("%s! %s" % [spec.name, spec.blurb])
	changed.emit()
	return ""


func is_running(id: String) -> bool:
	return running.has(id)


## Seconds until a power can be used again (0 when ready or running).
func cooldown_left(id: String) -> float:
	return cooldowns.get(id, 0.0)


## Advances timers. Public so tests can drive it.
func step(delta: float) -> void:
	var ended := false
	for id in running.keys():
		running[id] -= delta
		if running[id] <= 0.0:
			running.erase(id)
			cooldowns[id] = POWERS[id].cooldown
			notice.emit("%s has run down" % POWERS[id].name)
			ended = true
	for id in cooldowns.keys():
		cooldowns[id] -= delta
		if cooldowns[id] <= 0.0:
			cooldowns.erase(id)
			ended = true
	if ended:
		_apply()
		changed.emit()


func _apply() -> void:
	if combat:
		combat.player_tower_rate = OVERCHARGE_RATE if running.has("overcharge") else 1.0
