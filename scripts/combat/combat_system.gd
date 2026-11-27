## Runs every fight in the region: picks targets, applies damage on cooldown,
## draws tracers, pays bounties and clears out the dead.
##
## - Units shoot the nearest enemy in range. Idle or attack-moving units also
##   walk toward enemies within their aggro range. A plain move order ignores
##   enemies until the unit arrives (like the reference game's RTS controls).
## - Towers shoot the nearest enemy in range. Flak (air_only) sees only
##   aircraft; ground defenses can't see aircraft at all. Their fire rate scales with grid
##   efficiency.
## - Headquarters have a light gun of their own.
## - Your troops fight troops first: they shoot an enemy unit in range before
##   any building or headquarters. Every unit turns to face what it shoots.
## - Shots from range (units with a long reach, towers, headquarters guns) are
##   shells that fly for a moment; the hit lands when the shell arrives. A
##   shielded unit (Shieldbearer) stops most of a shell from the front, and
##   catches shells that would fly past it toward an ally behind. Shots from
##   the side or back get through. Melee hits, lightning and bombs from the
##   air aren't blocked.
## - Heavy hitters (Lancers, walkers) stagger what they hit: a shove back and
##   a pause before its next attack. A Shieldbearer facing the hit braces.
## - Engineers heal the most wounded ally in range before anything else, and
##   repair damaged buildings in range when there's no enemy to fight.
class_name CombatSystem
extends Node

signal building_destroyed(building_name: String, faction: String)
signal headquarters_destroyed(faction: String, platform: String)
## A headquarters was hit: faction, platform, damage.
signal headquarters_damaged(faction: String, platform: String, amount: float)
signal unit_killed(unit: Unit)

## Fire-rate multiplier for the player's towers (Overcharge sets it).
var player_tower_rate := 1.0

## Share of a rival's bounty paid for killing it. Half, so most scrap comes
## from the islands you hold rather than from kills.
const BOUNTY_SHARE := 0.5

## Engineers mend a headquarters at this share of their building repair rate.
const HQ_REPAIR_SHARE := 0.4

## How far an Arc Coil's lightning can jump between targets.
const CHAIN_JUMP := 5.0
## How far to either side of a shot's path a shield still catches it, added
## to the shield bearer's footprint.
const SHIELD_REACH := 0.5
## Anti-armor shots (attackers with bonus damage against armor, like Lancers)
## punch through: shields stop this much less of them.
const PIERCE_SHARE := 0.6
## A shield covers shots from this wide a front (cosine of half the arc:
## 0.5 is 120 degrees).
const SHIELD_ARC_COS := 0.5
## How far a heavy hit shoves a unit (half that for heavy units like walkers),
## and how long it holds off the unit's next attack.
const KNOCKBACK := 0.8
const STAGGER_SECONDS := 0.45
## Shell speed for towers and headquarters guns, units per second.
const TOWER_SHELL_SPEED := 60.0
## How each tower's fire looks, by its attack "shot": shell colour and size,
## shell speed, and the muzzle's height above the deck (models differ).
const TOWER_SHOTS := {
	"rivet": {"color": Color(1.0, 0.8, 0.4), "size": 0.16, "speed": 70.0, "muzzle": 1.1},
	"bolt": {"color": Color(0.6, 0.7, 1.0), "size": 0.0, "speed": 0.0, "muzzle": 3.9},
	"flak": {"color": Color(1.0, 0.6, 0.3), "size": 0.2, "speed": 60.0, "muzzle": 2.3},
	"harpoon": {"color": Color(0.8, 0.72, 0.55), "size": 0.3, "speed": 34.0, "muzzle": 3.0},
	"shell": {"color": Color(1.0, 0.85, 0.4), "size": 0.24, "speed": 60.0, "muzzle": 1.2},
}
## Flak bursts: aircraft near the one hit take this share of the damage.
const BURST_SHARE := 0.5
## Bombs: seconds to fall, blast radius.
const BOMB_FALL := 0.9
const BOMB_RADIUS := 1.7
## A downed heavy airship: seconds to fall, crush radius and damage.
const WRECK_FALL := 1.2
const WRECK_RADIUS := 2.2
const WRECK_DAMAGE := 30.0
## A shell whose target falls before it lands hits an enemy this close to
## where it comes down instead.
const SHELL_STRAY := 1.5

@export var region: SkyRegion
@export var resources: PlayerResources

var rng := RandomNumberGenerator.new()
var _chase_timer := 0.0
## Shells in flight: {hit, target, amount, color, left, total, from, fx}.
var _shots: Array = []
## Bombs and wrecks falling: {at, left, amount, radius, hit, sides, big}.
var _blasts: Array = []
## Skyhook cables still drawn: {"mesh", "from", "target", "left"}.
var _cables: Array = []


func _ready() -> void:
	rng.seed = 1234


func _process(delta: float) -> void:
	step(delta)


## Spawns a Headquarters on every core tile. Called once after the region is built.
func spawn_headquarters() -> void:
	for hex in region.tiles:
		var t: Dictionary = region.tiles[hex]
		if t.type == "core" or t.type == "rival_core":
			var hq := Headquarters.new()
			hq.name = "HQ_" + t.platform.replace(" ", "")
			hq.faction = "player" if t.type == "core" else "rival"
			hq.platform = t.platform
			if hq.faction == "rival":
				hq.max_hp = 800.0
			hq.position = region.hex_center(hex)
			region.add_child(hq)
			hq.destroyed.connect(_on_headquarters_destroyed)
			hq.damaged.connect(func(h, a): headquarters_damaged.emit(h.faction, h.platform, a))


## Advances all fighting by `delta` seconds. Public so tests can drive it.
func step(delta: float) -> void:
	_chase_timer -= delta
	var chase := _chase_timer <= 0.0
	if chase:
		_chase_timer = 0.5
	_fly_shells(delta)
	_land_blasts(delta)
	_reel_cables(delta)

	for faction in ["player", "rival"]:
		for unit in _units(faction):
			if not unit.is_alive() or unit.riding:
				continue
			unit.cooldown_left -= delta
			# Bombers drop their bombs as they fly over (VesperFleet runs them).
			if unit.has_meta("bomb_runs"):
				continue
			# Engineers patch up a wounded ally first, then fight or repair.
			if unit.heal_power > 0.0 and _tend(unit, faction, delta):
				continue
			var target = _pick_target(unit, faction)
			if target is bool:
				# A hunter (Vesper gunship) with prey in sight keeps flying to it.
				continue
			if target != null:
				if not unit.is_moving() or unit.attack_move:
					unit.stop()
				if not unit.is_moving():
					unit.face(target.global_position)
				if unit.cooldown_left <= 0.0 and not unit.is_moving():
					unit.cooldown_left = unit.get_attack_cooldown()
					fire(unit, target, unit.get_damage(), Color(0.55, 0.8, 1.0) if unit.heavy_hits else Color(1.0, 0.85, 0.4))
			elif unit.repair_power > 0.0 and not unit.is_moving() and _repair(unit, faction, delta):
				pass
			elif chase and not unit.flying and (not unit.is_moving() or unit.attack_move):
				var prey = nearest_enemy_unit(unit.global_position, faction, unit.aggro_range, unit.hits_air) if unit.targets_units and faction == "player" else null
				if prey == null:
					prey = nearest_enemy(unit.global_position, faction, unit.aggro_range, unit.hits_air, unit.targets_units)
				if prey == null and faction == "player" and not unit.is_moving():
					prey = _intruder_on_platform(unit)
				if prey != null:
					var route := region.find_route(unit.position, region.snap_to_walkable(prey.global_position))
					if not route.is_empty():
						unit.set_route(route, true)

	for b in region.buildings.values().duplicate():
		var attack: Dictionary = b.get_attack()
		if attack.is_empty() or not b.is_alive():
			continue
		var rate := player_tower_rate if b.faction == "player" else 1.0
		b.cooldown_left -= delta * maxf(b.efficiency, 0.05) * rate
		if b.cooldown_left > 0.0:
			continue
		var target = nearest_enemy(b.global_position, b.faction, attack.range, attack.has("air"))
		if target == null:
			continue
		var amount: float = attack.air if target is Unit and target.flying else attack.damage
		b.cooldown_left = attack.cooldown
		b.aim_at(target.global_position)
		var look: Dictionary = TOWER_SHOTS.get(attack.get("shot", "shell"), TOWER_SHOTS.shell)
		if attack.has("chain"):
			CombatFx.bolt(region, _muzzle(b), _aim_point(target), look.color)
			deal_hit(b, target, amount, look.color, false, "none")
			_chain(target, b.faction, amount * 0.7, int(attack.chain) - 1)
		else:
			fire(b, target, amount, look.color, true)

	for hq in get_tree().get_nodes_in_group(Headquarters.GROUP):
		if not hq.is_alive():
			continue
		hq.cooldown_left -= delta
		if hq.cooldown_left > 0.0:
			continue
		var target = nearest_enemy(hq.global_position, hq.faction, hq.attack.range, true)
		if target != null:
			hq.cooldown_left = hq.attack.cooldown
			fire(hq, target, hq.attack.damage, Color(1.0, 0.6, 0.3), true)


## The closest living enemy of `faction` within `max_range`: a unit, a
## building or a headquarters. Null if none. Aircraft only count when
## `hits_air`; bombers pass `hits_units` false to ignore units entirely, and
## flak passes `air_only` to see nothing but aircraft.
func nearest_enemy(from: Vector3, faction: String, max_range: float, hits_air := false, hits_units := true, air_only := false):
	var best = null
	var best_d := max_range
	var other := "rival" if faction == "player" else "player"
	for unit in _units(other):
		if not hits_units or (unit.flying and not hits_air) or (air_only and not unit.flying):
			continue
		if unit.is_alive() and not unit.riding:
			var d := _flat_distance(from, unit.global_position)
			if d <= best_d:
				best_d = d
				best = unit
	if air_only:
		return best
	for b in region.buildings.values():
		if b.faction == other and b.is_alive():
			var d := _flat_distance(from, b.global_position)
			if d <= best_d:
				best_d = d
				best = b
	for hq in get_tree().get_nodes_in_group(Headquarters.GROUP):
		if hq.faction == other and hq.is_alive():
			# Headquarters are big: count range from their edge.
			var d := _flat_distance(from, hq.global_position) - region.tile_size
			if d <= best_d:
				best_d = d
				best = hq
	return best


## What a unit shoots this tick. Your troops fight troops first: the nearest
## enemy unit in range, and only with none in range a building or
## headquarters. Rival raiders are after your Hub, so they shoot whatever is
## nearest, buildings included (your headquarters soaks fire your troops
## would otherwise take).
## Units with a "hunt_range" meta (Vesper gunships) also keep flying toward
## enemy units within hunt range instead of stopping at buildings: they
## return true (keep flying) while prey is near but out of reach.
func _pick_target(unit: Unit, faction: String):
	var reach := unit.get_attack_range()
	if unit.has_meta("hunt_range"):
		var prey = nearest_enemy_unit(unit.global_position, faction, reach, unit.hits_air)
		if prey != null:
			return prey
		if nearest_enemy_unit(unit.global_position, faction, unit.get_meta("hunt_range"), unit.hits_air) != null:
			return true
	if unit.targets_units and faction == "player":
		var troop = nearest_enemy_unit(unit.global_position, faction, reach, unit.hits_air, unit.air_only)
		if troop != null:
			return troop
	return nearest_enemy(unit.global_position, faction, reach, unit.hits_air, unit.targets_units, unit.air_only)


## The closest living enemy unit or drone (no buildings or headquarters)
## within `max_range`, or null.
func nearest_enemy_unit(from: Vector3, faction: String, max_range: float, hits_air := false, air_only := false):
	var best = null
	var best_d := max_range
	var other := "rival" if faction == "player" else "player"
	for unit in _units(other):
		if (unit.flying and not hits_air) or (air_only and not unit.flying) or not unit.is_alive() or unit.riding:
			continue
		var d := _flat_distance(from, unit.global_position)
		if d <= best_d:
			best_d = d
			best = unit
	return best


## An enemy unit standing on the same platform as an idle player unit, so a
## squad parked anywhere on the Hub defends all of it.
func _intruder_on_platform(unit: Unit):
	var here := region.platform_at(unit.position)
	if here == "" or region.platform_owner(here) != "player":
		return null
	var best = null
	var best_d := INF
	for foe in _units("rival"):
		if foe.is_alive() and not foe.riding and (not foe.flying or unit.hits_air) and region.platform_at(foe.position) == here:
			var d := _flat_distance(unit.global_position, foe.global_position)
			if d < best_d:
				best_d = d
				best = foe
	return best


## Deals damage from an attacker to a target right now. With `projectile`
## true (the default for ranged units), a shield in the way catches the shot.
## Use fire() for shots that should fly to their target first.
func deal_hit(attacker: Node3D, target: Node3D, amount: float, color: Color, projectile = null, style := "") -> void:
	var hit := _snapshot(attacker, projectile)
	if not hit.projectile and attacker is Unit and hit.unit:
		hit.style = "spark"
	if style != "":
		hit.style = style
	_resolve(hit, target, amount, color)


## Fires a shell from `attacker` at `target`. It flies at the attacker's
## shell speed and the hit lands when it arrives, so a target that dies
## first wastes the shot. Melee attackers hit at once.
func fire(attacker: Node3D, target: Node3D, amount: float, color: Color, projectile = null) -> void:
	var hit := _snapshot(attacker, projectile)
	if not hit.ranged:
		hit.style = "spark"
		_resolve(hit, target, amount, color)
		return
	var from := attacker.global_position + Vector3.UP * 1.2
	var speed: float = attacker.shell_speed if attacker is Unit else TOWER_SHELL_SPEED
	var size := 0.4 if hit.heavy else 0.24
	var look: Dictionary = {}
	if attacker is Building:
		look = TOWER_SHOTS.get(attacker.get_attack().get("shot", "shell"), TOWER_SHOTS.shell)
		from = _muzzle(attacker)
		speed = look.speed
		size = look.size
	var time := from.distance_to(_aim_point(target)) / maxf(speed, 1.0)
	hit.style = "spark"
	CombatFx.flash(region, from, color, 0.18 if size < 0.25 else 0.32, 0.08)
	var shot := {"hit": hit, "target": target, "amount": amount, "color": color, "left": time, "total": time,
		"from": from, "last_aim": _aim_point(target), "air": target is Unit and (target as Unit).flying, "fx": CombatFx.shell(region, from, color, size)}
	if not hit.hook.is_empty():
		shot.cable = CombatFx.cable(region, from, from)
	_shots.append(shot)


## Where a tower's shots leave its model: the gun's height for its kind.
func _muzzle(b: Building) -> Vector3:
	var look: Dictionary = TOWER_SHOTS.get(b.get_attack().get("shot", "shell"), TOWER_SHOTS.shell)
	return b.global_position + Vector3.UP * float(look.muzzle)


## Moves shells along and lands the ones that arrive.
func _fly_shells(delta: float) -> void:
	if _shots.is_empty():
		return
	var still: Array = []
	for shot in _shots:
		var target = shot.target
		var alive: bool = is_instance_valid(target) and target.is_alive()
		if alive:
			shot.last_aim = _aim_point(target)
		shot.left -= delta
		if shot.left > 0.0:
			if shot.fx:
				var k: float = 1.0 - shot.left / maxf(shot.total, 0.001)
				var aim: Vector3 = shot.last_aim
				shot.fx.global_position = (shot.from as Vector3).lerp(aim, k)
				if shot.fx.global_position.distance_to(aim) > 0.05:
					shot.fx.look_at(aim, Vector3.UP if absf((aim - shot.fx.global_position).normalized().y) < 0.99 else Vector3.RIGHT)
				if shot.get("cable"):
					CombatFx.stretch(shot.cable, shot.from, shot.fx.global_position)
			still.append(shot)
			continue
		if shot.fx and is_instance_valid(shot.fx):
			shot.fx.queue_free()
		if shot.get("cable") and is_instance_valid(shot.cable):
			# The harpoon bites: the cable stays on its ship while it's hooked.
			if alive:
				_cables.append({"mesh": shot.cable, "from": shot.from, "target": target, "left": float(shot.hit.hook.seconds)})
			else:
				shot.cable.queue_free()
		if not alive and shot.left <= 0.0:
			# Its target fell first: the shell hits whoever stands where it lands.
			target = _unit_near(shot.last_aim, shot.hit.faction, SHELL_STRAY, shot.air)
			alive = target != null
		if alive:
			_resolve(shot.hit, target, shot.amount, shot.color)
	_shots = still


## The enemy unit of `faction` nearest `point` within `reach`, or null:
## aircraft only when `air`, otherwise ground units only.
func _unit_near(point: Vector3, faction: String, reach: float, air := false):
	if faction == "":
		return null
	var best = null
	var best_d := reach
	for u in _units("rival" if faction == "player" else "player"):
		if not u.is_alive() or u.riding or u.flying != air:
			continue
		var d := _aim_point(u).distance_to(point)
		if d <= best_d:
			best_d = d
			best = u
	return best


func _aim_point(target: Node3D) -> Vector3:
	return target.global_position + Vector3.UP * (0.0 if target is Unit and (target as Unit).flying else 1.0)


## What a hit needs to know about its attacker, taken when it fires (the
## attacker may be gone by the time a shell lands).
func _snapshot(attacker: Node3D, projectile) -> Dictionary:
	var hit := {"from": attacker.global_position, "unit": attacker is Unit,
		"faction": attacker.faction if "faction" in attacker else "", "vs_armor": 1.0,
		"vs_buildings": 1.0, "heavy": false, "ranged": true, "style": "tracer",
		"vs_light": 1.0, "vs_heavy": 1.0, "splash": 0.0, "hook": {}}
	if attacker.has_method("get_attack"):
		var attack: Dictionary = attacker.get_attack()
		hit.vs_light = attack.get("vs_light", 1.0)
		hit.vs_heavy = attack.get("vs_heavy", 1.0)
		hit.splash = attack.get("splash", 0.0)
		hit.hook = attack.get("hook", {})
	if attacker is Unit:
		var a := attacker as Unit
		hit.vs_armor = a.vs_armor
		hit.vs_buildings = a.vs_buildings
		hit.heavy = a.heavy_hits
		hit.ranged = a.is_ranged()
		if projectile == null:
			projectile = a.is_ranged() and not a.flying
	hit.projectile = projectile == true
	return hit


func _resolve(hit: Dictionary, target: Node3D, amount: float, color: Color) -> void:
	if not is_instance_valid(target) or not target.is_alive():
		return
	if hit.unit:
		if target is Building or target is Headquarters:
			amount *= hit.vs_buildings
		elif target is Unit and (target as Unit).armored:
			amount *= hit.vs_armor
	if target is Unit and (target as Unit).hull != "":
		amount *= hit.get("vs_" + (target as Unit).hull, 1.0)
	var blocked := false
	if hit.projectile and not (target is Unit and (target as Unit).flying):
		var blocker := shield_in_path(hit.from, target)
		if blocker != null:
			target = blocker
		if target is Unit and (target as Unit).shield > 0.0 and (target as Unit).is_facing(hit.from, SHIELD_ARC_COS):
			var pierce: bool = hit.vs_armor > 1.0
			var stopped: float = (target as Unit).shield * ((1.0 - PIERCE_SHARE) if pierce else 1.0)
			amount *= 1.0 - stopped
			color = Color(0.75, 0.8, 0.9)
			blocked = true
	var at := _aim_point(target)
	if hit.splash > 0.0 and target is Unit and (target as Unit).flying:
		_burst(hit, target, amount, color)
	if hit.style == "tracer":
		_tracer(hit.from + Vector3.UP * 1.2, at, color)
	elif hit.style == "burst":
		# A flak shell bursting: a black smoke puff with a flash inside.
		CombatFx.puff(region, at, hit.splash * 0.3, 0.7)
	elif hit.style != "none":
		CombatFx.flash(region, at, color, 0.22 if not hit.heavy else 0.4, 0.12 if not blocked else 0.18)
	if target is Building:
		var b := target as Building
		if b.take_damage(amount):
			region.remove_building(b.hex)
			building_destroyed.emit(b.get_data().name, b.faction)
			CombatFx.puff(region, b.global_position + Vector3.UP * 0.8, 1.6)
			b.queue_free()
	elif target is Unit:
		var u := target as Unit
		var was_alive := u.hp > 0.0
		u.take_damage(amount)
		if not hit.get("hook", {}).is_empty() and u.flying:
			u.add_buff("hooked", {"speed": float(hit.hook.slow)}, float(hit.hook.seconds))
		if was_alive and u.hp <= 0.0:
			if u.faction == "rival" and resources:
				resources.add_scrap(int(round(u.bounty * BOUNTY_SHARE)))
			CombatFx.puff(region, u.global_position + Vector3.UP * 0.6, u.footprint * 1.4)
			if u.flying and u.hull == "heavy":
				_crash(u)
			unit_killed.emit(u)
		elif hit.heavy and not u.flying and not u.riding:
			_stagger(u, hit.from, hit.ranged)
	else:
		target.take_damage(amount)


## Flak burst: other enemy aircraft within the splash radius of a hit take
## BURST_SHARE of it (after their own hull's multiplier).
func _burst(hit: Dictionary, target: Unit, amount: float, color: Color) -> void:
	# The burst's base damage, before the hit target's own hull multiplier.
	var side: float = amount / maxf(hit.get("vs_" + target.hull, 1.0), 0.01)
	var shard := hit.duplicate()
	shard.splash = 0.0
	shard.style = "none"
	shard.projectile = false
	for u in _units(target.faction):
		if u == target or not u.flying or not u.is_alive():
			continue
		if _aim_point(u).distance_to(_aim_point(target)) <= hit.splash:
			_resolve(shard, u, side * BURST_SHARE, color)
	if hit.style != "none":
		hit.style = "burst"


## Drops a bomb from `faction`: it lands after BOMB_FALL seconds at the deck
## under `at` (a shadow shows where), then blasts every enemy unit on the
## ground, building and headquarters within `radius`.
func drop_bomb(at: Vector3, faction: String, amount: float, radius := BOMB_RADIUS) -> void:
	var ground := Vector3(at.x, 0.0, at.z)
	CombatFx.shadow(region, ground, radius, BOMB_FALL)
	CombatFx.falling(region, at, ground, 0.35, BOMB_FALL, Color(0.15, 0.14, 0.13))
	_blasts.append({"at": ground, "left": BOMB_FALL, "amount": amount, "radius": radius,
		"hit": {"from": ground + Vector3.UP * 8.0, "unit": false, "faction": faction, "vs_armor": 1.0,
			"vs_buildings": 1.0, "heavy": false, "ranged": false, "style": "none", "projectile": false,
			"vs_light": 1.0, "vs_heavy": 1.0, "splash": 0.0},
		"sides": ["rival" if faction == "player" else "player"], "big": false})


## A heavy airship goes down: its wreck falls for WRECK_FALL seconds and, if
## it lands on an island, crushes whatever is under it, on either side.
func _crash(u: Unit) -> void:
	var ground := Vector3(u.global_position.x, 0.0, u.global_position.z)
	var radius := WRECK_RADIUS * clampf(u.footprint / 0.9, 0.8, 1.4)
	if region.platform_at(ground) != "":
		CombatFx.shadow(region, ground, radius, WRECK_FALL)
	var lands := ground if region.platform_at(ground) != "" else ground + Vector3.DOWN * 14.0
	CombatFx.falling(region, u.global_position, lands, u.footprint * 1.2, WRECK_FALL, u.body_color.darkened(0.7), true)
	_blasts.append({"at": ground, "left": WRECK_FALL, "amount": WRECK_DAMAGE, "radius": radius,
		"hit": {"from": ground + Vector3.UP * 8.0, "unit": false, "faction": "", "vs_armor": 1.0,
			"vs_buildings": 1.0, "heavy": true, "ranged": false, "style": "none", "projectile": false,
			"vs_light": 1.0, "vs_heavy": 1.0, "splash": 0.0},
		"sides": ["player", "rival"], "big": true})


## Counts falling bombs and wrecks down and blasts the ones that land.
func _land_blasts(delta: float) -> void:
	if _blasts.is_empty():
		return
	var still: Array = []
	var landed: Array = []
	for b in _blasts:
		b.left -= delta
		if b.left > 0.0:
			still.append(b)
		else:
			landed.append(b)
	_blasts = still
	for b in landed:
		var on_island := region.platform_at(b.at) != ""
		if b.big and not on_island:
			# Down into the clouds: nothing under it.
			continue
		CombatFx.flash(region, b.at + Vector3.UP * 0.5, Color(1.0, 0.6, 0.25, 0.9), b.radius * 0.6, 0.3)
		CombatFx.puff(region, b.at + Vector3.UP * 0.4, b.radius * 0.7)
		for victim in _in_blast(b.at, b.radius, b.sides):
			_resolve(b.hit, victim, b.amount, Color.WHITE)


## Every ground unit, building and headquarters of `sides` within `radius`
## of a point on the deck (headquarters count from their edge).
func _in_blast(at: Vector3, radius: float, sides: Array) -> Array:
	var out := []
	for side in sides:
		for u in _units(side):
			if u.is_alive() and not u.flying and not u.riding and _flat_distance(at, u.global_position) <= radius:
				out.append(u)
	for b in region.buildings.values():
		if b.is_alive() and sides.has(b.faction) and _flat_distance(at, b.global_position) <= radius + Building.SIZE * 0.4:
			out.append(b)
	for hq in get_tree().get_nodes_in_group(Headquarters.GROUP):
		if hq.is_alive() and sides.has(hq.faction) and _flat_distance(at, hq.global_position) - region.tile_size <= radius:
			out.append(hq)
	return out


## A heavy hit shoves a ground unit away from the attacker and delays its
## next attack, unless it's a Shieldbearer facing the blow.
func _stagger(u: Unit, from: Vector3, ranged := true) -> void:
	if u.shield > 0.0 and u.is_facing(from, SHIELD_ARC_COS):
		return
	var push := u.global_position - from
	push.y = 0.0
	if push.length() < 0.01:
		push = -u.forward()
	var dest := u.global_position + push.normalized() * KNOCKBACK * (0.5 if u.weight >= 3 else 1.0)
	# Melee blows only rock the target in place: a shove would knock it
	# out of reach and hand a ranged victim a free retreat.
	if not ranged or region == null or not region.is_walkable(dest):
		dest = u.global_position
	u.stagger(dest, STAGGER_SECONDS)


## The shielded unit that would catch a projectile flying from `from` to
## `target`, or null. Only shields on the target's side count, and only ones
## standing between the two and facing the shooter (the one nearest the
## shooter wins).
func shield_in_path(from: Vector3, target: Node3D) -> Unit:
	if not ("faction" in target):
		return null
	var side: String = target.faction
	var a := Vector2(from.x, from.z)
	var b := Vector2(target.global_position.x, target.global_position.z)
	var path := b - a
	var length := path.length()
	if length < 0.01:
		return null
	var best: Unit = null
	var best_t := INF
	for u in _units(side):
		if u == target or u.shield <= 0.0 or not u.is_alive() or u.riding or u.flying:
			continue
		# Only a shield facing the shooter covers the allies behind it.
		if not u.is_facing(from, SHIELD_ARC_COS):
			continue
		var p := Vector2(u.global_position.x, u.global_position.z)
		var t := (p - a).dot(path) / (length * length)
		if t <= 0.0 or t >= 1.0:
			continue
		if (a + path * t).distance_to(p) <= u.footprint + SHIELD_REACH and t < best_t:
			best_t = t
			best = u
	return best


## Engineer: heal the most wounded ally in range. Returns true if it healed
## someone (and so doesn't shoot this tick).
func _tend(engineer: Unit, faction: String, delta: float) -> bool:
	var best: Unit = null
	var worst := 1.0
	var reach := engineer.get_attack_range()
	for u in _units(faction):
		if u == engineer or not u.is_alive() or u.riding or u.flying or u.hp >= u.max_hp:
			continue
		if _flat_distance(engineer.global_position, u.global_position) > reach:
			continue
		var ratio := u.hp / u.max_hp
		if ratio < worst:
			worst = ratio
			best = u
	if best == null:
		return false
	best.heal(engineer.heal_power * engineer.buff_multiplier("healing") * delta)
	if engineer.cooldown_left <= 0.0:
		engineer.cooldown_left = 0.6
		_tracer(engineer.global_position + Vector3.UP * 1.2, best.global_position + Vector3.UP * 1.0, Color(0.5, 1.0, 0.6))
	return true


## Engineer: repair the most damaged friendly building in range. Returns true
## if it repaired something.
func _repair(engineer: Unit, faction: String, delta: float) -> bool:
	var best: Building = null
	var worst := 1.0
	for b in region.buildings.values():
		if b.faction != faction or not b.is_alive() or b.hp >= b.max_hp:
			continue
		if _flat_distance(engineer.global_position, b.global_position) > engineer.get_attack_range() + Building.SIZE * 0.5:
			continue
		if b.hp / b.max_hp < worst:
			worst = b.hp / b.max_hp
			best = b
	var amount := engineer.repair_power * engineer.buff_multiplier("healing") * delta
	if best == null:
		# With every building whole, Engineers patch up their own headquarters,
		# slowly: bombs that land are not gone for good, but it takes time.
		for hq in get_tree().get_nodes_in_group(Headquarters.GROUP):
			if hq.faction == faction and hq.is_alive() and hq.hp < hq.max_hp \
					and _flat_distance(engineer.global_position, hq.global_position) <= engineer.get_attack_range() + region.tile_size * 1.5:
				hq.repair(amount * HQ_REPAIR_SHARE)
				if engineer.cooldown_left <= 0.0:
					engineer.cooldown_left = 0.6
					_tracer(engineer.global_position + Vector3.UP * 1.2, hq.global_position + Vector3.UP * 2.0, Color(0.9, 0.8, 0.4))
				return true
		return false
	best.repair(amount)
	if engineer.cooldown_left <= 0.0:
		engineer.cooldown_left = 0.6
		_tracer(engineer.global_position + Vector3.UP * 1.2, best.global_position + Vector3.UP * 1.0, Color(0.9, 0.8, 0.4))
	return true


## Keeps each Skyhook cable stretched from its gun to its hooked ship, and
## drops it when the hook comes loose or the ship goes down.
func _reel_cables(delta: float) -> void:
	if _cables.is_empty():
		return
	var still: Array = []
	for c in _cables:
		c.left -= delta
		var ok: bool = c.left > 0.0 and is_instance_valid(c.target) and c.target.is_alive() and is_instance_valid(c.mesh)
		if not ok:
			if is_instance_valid(c.mesh):
				c.mesh.queue_free()
			continue
		CombatFx.stretch(c.mesh, c.from, _aim_point(c.target))
		still.append(c)
	_cables = still


func _chain(first: Node3D, faction: String, amount: float, jumps: int) -> void:
	var hit := [first]
	var from := first
	for i in jumps:
		var next = null
		var best := CHAIN_JUMP
		for unit in _units("rival" if faction == "player" else "player"):
			if unit.is_alive() and not unit.flying and not hit.has(unit):
				var d := _flat_distance(from.global_position, unit.global_position)
				if d <= best:
					best = d
					next = unit
		if next == null:
			return
		CombatFx.bolt(region, _aim_point(from), _aim_point(next), Color(0.6, 0.7, 1.0))
		deal_hit(from, next, amount, Color(0.6, 0.7, 1.0), null, "none")
		hit.append(next)
		from = next


## Every unit of a faction, including its hangar drones.
func _units(faction: String) -> Array[Unit]:
	var out: Array[Unit] = []
	for node in get_tree().get_nodes_in_group(Unit.GROUP if faction == "player" else Unit.ENEMY_GROUP):
		out.append(node as Unit)
	for node in get_tree().get_nodes_in_group(Unit.DRONE_GROUP):
		if node.faction == faction:
			out.append(node as Unit)
	return out


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


## The living headquarters on a platform, or null.
func headquarters_on(platform_name: String) -> Headquarters:
	for hq in get_tree().get_nodes_in_group(Headquarters.GROUP):
		if hq.platform == platform_name and hq.is_alive():
			return hq
	return null


func _on_headquarters_destroyed(hq: Headquarters) -> void:
	headquarters_destroyed.emit(hq.faction, hq.platform)


## A short-lived line from shooter to target.
func _tracer(from: Vector3, to: Vector3, color: Color) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var line := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	var length := from.distance_to(to)
	mesh.size = Vector3(0.08, 0.08, length)
	line.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	line.material_override = mat
	region.add_child(line)
	line.global_position = (from + to) / 2.0
	if length > 0.01:
		line.look_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)
	var tween := line.create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.15)
	tween.tween_callback(line.queue_free)
