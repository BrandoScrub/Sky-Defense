## A headquarters core: the Hub's or a rival's. It has a lot of hit points and
## a light defensive gun. Destroying a side's headquarters ends the game.
class_name Headquarters
extends Node3D

signal destroyed(hq: Headquarters)
## Took damage (the HUD flashes the Hub's health and warns the player).
signal damaged(hq: Headquarters, amount: float)

const GROUP := "headquarters"

var faction := "player"
var platform := ""
var max_hp := 2000.0
var hp := 2000.0
var cooldown_left := 0.0
## Time.get_ticks_msec() of the last hit, or -1.
var last_hit_msec := -1
var attack := {"damage": 18.0, "range": 10.0, "cooldown": 1.0}

var _health_bar: HealthBar


func _ready() -> void:
	add_to_group(GROUP)
	hp = max_hp
	_health_bar = HealthBar.new()
	_health_bar.width = 4.0
	_health_bar.height = 0.3
	_health_bar.position.y = 6.9
	add_child(_health_bar)


func get_attack() -> Dictionary:
	return attack


func is_alive() -> bool:
	return hp > 0.0 and is_inside_tree()


## Mends the headquarters (Engineers), up to full health.
func repair(amount: float) -> void:
	if hp <= 0.0:
		return
	hp = minf(max_hp, hp + amount)
	_health_bar.set_ratio(hp / max_hp, faction != "player")


func take_damage(amount: float) -> void:
	if hp <= 0.0:
		return
	hp = maxf(0.0, hp - amount)
	_health_bar.set_ratio(hp / max_hp, faction != "player")
	last_hit_msec = Time.get_ticks_msec()
	damaged.emit(self, amount)
	if hp <= 0.0:
		destroyed.emit(self)
