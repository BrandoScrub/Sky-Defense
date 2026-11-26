## Claiming platforms by presence, in the style of the reference game: units
## standing on a platform slowly claim it. If both sides have units there it's
## contested and progress pauses. With nobody there, progress drains away.
## Hubs and rival headquarters can't be claimed this way.
class_name CaptureSystem
extends Node

signal platform_claimed(platform_name: String, new_owner: String)

## Seconds one unit needs to claim a platform of radius 1; bigger platforms
## take longer, more units go faster (up to `max_units_counted`).
@export var base_seconds := 6.0
@export var seconds_per_ring := 3.0
@export var max_units_counted := 4
## How fast progress drains when nobody is there, per second.
@export var decay_per_second := 0.1

@export var region: SkyRegion

## platform name -> {"side": "player"/"rival"/"", "progress": 0..1}
var claims := {}


func _process(delta: float) -> void:
	step(delta)


## Advances every claim by `delta` seconds. Public so tests can drive it.
func step(delta: float) -> void:
	for platform_name in region.platforms:
		if not is_claimable(platform_name):
			continue
		var players := region.units_on_platform(platform_name, Unit.GROUP).size()
		var rivals := region.units_on_platform(platform_name, Unit.ENEMY_GROUP).size()
		var claim: Dictionary = claims.get(platform_name, {"side": "", "progress": 0.0})
		var holder := region.platform_owner(platform_name)

		var side := ""
		var count := 0
		if players > 0 and rivals == 0 and holder != "player":
			side = "player"
			count = players
		elif rivals > 0 and players == 0 and holder != "rival":
			side = "rival"
			count = rivals

		if players > 0 and rivals > 0:
			region.set_platform_status(platform_name, "Contested")
		elif side != "":
			if claim.side != side:
				claim = {"side": side, "progress": 0.0}
			var seconds := seconds_for(platform_name)
			claim.progress += delta * mini(count, max_units_counted) / seconds
			if claim.progress >= 1.0:
				claim = {"side": "", "progress": 0.0}
				region.set_platform_owner(platform_name, side)
				region.set_platform_status(platform_name, "")
				platform_claimed.emit(platform_name, side)
			else:
				var verb := "Claiming" if side == "player" else "%s claiming" % _rival_corp_on(platform_name)
				region.set_platform_status(platform_name, "%s %d%%" % [verb, int(claim.progress * 100)])
		else:
			claim.progress = maxf(0.0, claim.progress - decay_per_second * delta)
			if claim.progress <= 0.0:
				claim.side = ""
				region.set_platform_status(platform_name, "")
			else:
				region.set_platform_status(platform_name, "%d%%" % int(claim.progress * 100))
		claims[platform_name] = claim


## The corporation of the rival units on a platform, for its claim label.
func _rival_corp_on(platform_name: String) -> String:
	for u in region.units_on_platform(platform_name, Unit.ENEMY_GROUP):
		var corp: String = u.get_meta("corp", "")
		if corp != "":
			return corp
	return "Rival"


func is_claimable(platform_name: String) -> bool:
	var kind: String = region.platforms[platform_name].kind
	return kind != "hub" and kind != "rival"


## Seconds a single unit needs to claim this platform.
func seconds_for(platform_name: String) -> float:
	return base_seconds + seconds_per_ring * (region.platforms[platform_name].radius - 1)
